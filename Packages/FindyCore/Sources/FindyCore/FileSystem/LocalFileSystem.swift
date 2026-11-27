import Foundation

/// `FileSystemProviding` backed by the real disk.
public struct LocalFileSystem: FileSystemProviding {
    // Fetched in bulk with the listing, so building a `FileItem` costs no extra `stat`.
    // None of these keys downloads the content of a cloud-only (File Provider) file.
    private static let itemKeys: Set<URLResourceKey> = [
        .nameKey,
        .isDirectoryKey,
        .isPackageKey,
        .isSymbolicLinkKey,
        .isHiddenKey,
        .fileSizeKey,
        .contentModificationDateKey,
        // The Finder label lives in the catalog entry, next to the dates: measured at 5 ms more for
        // 10,000 files. The names of tags are in an extended attribute and would triple the listing.
        .labelNumberKey,
    ]

    public init() {}

    public func contents(of directory: URL) async throws -> [FileItem] {
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(Self.itemKeys),
            options: []
        )
        try Task.checkCancellation()
        return urls.map { Self.makeItem($0) }
    }

    public func search(
        in directory: URL, matching query: String, includingHidden: Bool
    ) -> AsyncStream<[FileItem]> {
        AsyncStream { continuation in
            let task = Task.detached(priority: .userInitiated) {
                Self.walk(directory, matching: query, includingHidden: includingHidden) { batch in
                    continuation.yield(batch)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func items(labeled label: FileLabel) -> AsyncStream<[FileItem]> {
        AsyncStream { continuation in
            let task = Task.detached(priority: .userInitiated) {
                let paths = LabelQuery.paths(labeled: label)
                // Attributes are read 200 entries at a time, so the first rows show at once.
                var start = 0
                while start < paths.count, !Task.isCancelled {
                    let end = min(start + 200, paths.count)
                    continuation.yield(Self.labeledItems(at: paths[start..<end], label: label))
                    start = end
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Reads the entries the index named. The index can lag behind the disk: an entry that is
    /// gone, or whose label was changed since, is left out.
    static func labeledItems(at paths: some Sequence<String>, label: FileLabel) -> [FileItem] {
        paths.compactMap { path in
            let url = URL(filePath: path)
            guard let values = try? url.resourceValues(forKeys: [.labelNumberKey]),
                values.labelNumber == label.rawValue
            else { return nil }
            return makeItem(url)
        }
    }

    /// The search itself. Synchronous: a directory enumerator cannot be iterated from async code.
    /// It checks for cancellation at every entry, so a new query stops the old walk at once.
    private static func walk(
        _ directory: URL, matching query: String, includingHidden: Bool, yield: ([FileItem]) -> Void
    ) {
        // The enumerator spells paths its own way (`/private/tmp/x` for `/tmp/x`). Starting from
        // the resolved path makes every result a plain suffix of it, which is then re-attached to
        // `directory`: results are spelled like the folder being searched.
        guard let resolved = realpath(directory.path, nil) else { return }
        let root = String(cString: resolved)
        free(resolved)
        var options: FileManager.DirectoryEnumerationOptions = [.skipsPackageDescendants]
        if !includingHidden { options.insert(.skipsHiddenFiles) }
        guard
            let enumerator = FileManager.default.enumerator(
                at: URL(filePath: root, directoryHint: .isDirectory),
                includingPropertiesForKeys: Array(itemKeys), options: options,
                // A folder that cannot be read is skipped: partial results beat none.
                errorHandler: { _, _ in true })
        else { return }

        let prefix = root.hasSuffix("/") ? root : root + "/"
        var batch: [FileItem] = []
        var lastYield = ContinuousClock.now
        for case let url as URL in enumerator {
            if Task.isCancelled { return }
            guard url.lastPathComponent.localizedStandardContains(query), url.path.hasPrefix(prefix) else {
                continue
            }
            let relative = String(url.path.dropFirst(prefix.count))
            batch.append(makeItem(url, shownAs: directory.appendingPathComponent(relative)))
            // The first results show up quickly; later ones come in larger lots.
            if batch.count >= 200 || ContinuousClock.now - lastYield > .milliseconds(100) {
                yield(batch)
                batch = []
                lastYield = .now
            }
        }
        if !batch.isEmpty, !Task.isCancelled { yield(batch) }
    }

    public func details(of url: URL) async throws -> FileDetails {
        // None of these keys opens the file, and a link is described, not followed.
        let values = try url.resourceValues(forKeys: [
            .nameKey, .localizedTypeDescriptionKey, .isDirectoryKey, .isPackageKey, .isSymbolicLinkKey,
            .fileSizeKey, .totalFileAllocatedSizeKey, .creationDateKey, .contentModificationDateKey,
        ])
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let isDirectory = values.isDirectory ?? false
        let isFolder = isDirectory && !(values.isPackage ?? false)
        return FileDetails(
            url: url,
            name: values.name ?? url.lastPathComponent,
            kind: values.localizedTypeDescription,
            isFolder: isFolder,
            size: isDirectory ? nil : values.fileSize.map(Int64.init),
            sizeOnDisk: isDirectory ? nil : values.totalFileAllocatedSize.map(Int64.init),
            creationDate: values.creationDate,
            modificationDate: values.contentModificationDate,
            owner: attributes[.ownerAccountName] as? String,
            group: attributes[.groupOwnerAccountName] as? String,
            permissions: (attributes[.posixPermissions] as? NSNumber)?.uint16Value,
            linkDestination: values.isSymbolicLink == true
                ? try? FileManager.default.destinationOfSymbolicLink(atPath: url.path) : nil)
    }

    public func directorySize(of directory: URL) async throws -> Int64 {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey]
        // Subfolders that cannot be read are skipped: a partial size beats no size.
        guard
            let enumerator = FileManager.default.enumerator(
                at: directory, includingPropertiesForKeys: Array(keys), options: [],
                errorHandler: { _, _ in true })
        else {
            throw CocoaError(.fileReadNoPermission, userInfo: [NSFilePathErrorKey: directory.path])
        }
        var total: Int64 = 0
        var visited = 0
        // The enumerator never descends into symbolic links, and a link is not a regular file.
        while let url = enumerator.nextObject() as? URL {
            visited += 1
            if visited.isMultiple(of: 256) { try Task.checkCancellation() }
            guard let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true else {
                continue
            }
            total += Int64(values.fileSize ?? 0)
        }
        try Task.checkCancellation()
        return total
    }

    public func diskUsage(of directory: URL) -> AsyncThrowingStream<DiskUsageEvent, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task.detached(priority: .userInitiated) {
                do {
                    try DiskUsageScanner.scan(directory) { continuation.yield($0) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func changes(in directory: URL) -> AsyncStream<Void> {
        DirectoryWatcher.changes(in: directory)
    }

    public func changes(under root: URL) -> AsyncStream<Void> {
        DirectoryWatcher.changes(in: root, recursive: true, latency: 1)
    }

    public func mountedVolumes() async -> [Volume] {
        let urls =
            FileManager.default.mountedVolumeURLs(
                includingResourceValuesForKeys: Array(Self.volumeKeys),
                options: [.skipHiddenVolumes]
            ) ?? []
        return urls.map { url in
            let values = try? url.resourceValues(forKeys: Self.volumeKeys)
            // The startup disk reports itself as internal and is never offered for ejection.
            let isEjectable =
                url.path != "/"
                && (values?.volumeIsEjectable == true || values?.volumeIsRemovable == true
                    || values?.volumeIsInternal == false)
            return Volume(
                url: url, name: values?.volumeLocalizedName ?? url.lastPathComponent, isEjectable: isEjectable)
        }
    }

    private static let volumeKeys: Set<URLResourceKey> = [
        .volumeLocalizedNameKey, .volumeIsEjectableKey, .volumeIsRemovableKey, .volumeIsInternalKey,
    ]

    public func eject(_ volume: URL) async throws {
        // Every partition goes with it: a drive with two volumes cannot be unplugged while one of
        // them is still mounted. The system's error already names the volume and what holds it.
        try await FileManager.default.unmountVolume(at: volume, options: [.allPartitionsAndEjectDisk])
    }

    public func cloudLocations() async -> [Volume] {
        Self.cloudLocations(home: FileManager.default.homeDirectoryForCurrentUser)
    }

    public func isBrowsableFolder(_ url: URL) async -> Bool {
        // `resourceValues` reads the link itself, so a link to a folder is resolved first.
        let values = try? url.resolvingSymlinksInPath().resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
        return (values?.isDirectory ?? false) && !(values?.isPackage ?? false)
    }

    public func gitInfo(for directory: URL) async -> GitInfo? {
        GitRepository.info(for: directory)
    }

    public func gitChanges(inRepositoryAt root: URL) async -> GitChanges? {
        await GitStatusReader.changes(inRepositoryAt: root)
    }

    public func availableSpace(at directory: URL) async -> Int64? {
        // The figure Finder shows: it counts the space the system can free on demand.
        let values = try? directory.resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey,
        ])
        if let important = values?.volumeAvailableCapacityForImportantUsage, important > 0 { return important }
        // Network and external volumes often report only the plain figure.
        return values?.volumeAvailableCapacity.map(Int64.init)
    }

    /// Cloud folders live at fixed places under the home folder: iCloud Drive in `Mobile Documents`,
    /// every File Provider service (Google Drive, OneDrive, Dropbox…) in `CloudStorage`.
    /// Only names are read here, so nothing gets downloaded.
    static func cloudLocations(home: URL) -> [Volume] {
        var locations: [Volume] = []

        let iCloud = home.appending(path: "Library/Mobile Documents/com~apple~CloudDocs", directoryHint: .isDirectory)
        if (try? iCloud.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
            locations.append(Volume(url: iCloud.canonicalLocation, name: "iCloud Drive"))
        }

        let storage = home.appending(path: "Library/CloudStorage", directoryHint: .isDirectory)
        // A Mac without any cloud service has no such folder: that is an empty list, not an error.
        let folders =
            (try? FileManager.default.contentsOfDirectory(
                at: storage, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
        let services =
            folders
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .map { (url: $0, name: cloudServiceName(folderName: $0.lastPathComponent)) }
        for service in services {
            // Two accounts of the same service would read the same: keep the full folder name then.
            let isAmbiguous = services.filter { $0.name == service.name }.count > 1
            locations.append(
                Volume(
                    url: service.url.canonicalLocation,
                    name: isAmbiguous ? service.url.lastPathComponent : service.name))
        }
        return locations
    }

    /// `CloudStorage` folders are named `<Service>-<account>`, for example `GoogleDrive-me@example.com`.
    /// The system gives them no nicer display name (checked on macOS 26.3), so the service part is used.
    static func cloudServiceName(folderName: String) -> String {
        let service = folderName.split(separator: "-", maxSplits: 1).first.map(String.init) ?? folderName
        return service == "GoogleDrive" ? "Google Drive" : service
    }

    /// - Parameter shown: the location the item is given, when it should differ from the URL its
    ///   attributes are read from.
    private static func makeItem(_ url: URL, shownAs shown: URL? = nil) -> FileItem {
        // An entry can vanish between the listing and this read. It is still listed, by name only,
        // rather than failing the whole directory.
        guard let values = try? url.resourceValues(forKeys: itemKeys) else {
            return FileItem(url: shown ?? url)
        }
        let isDirectory = values.isDirectory ?? false
        let isSymbolicLink = values.isSymbolicLink ?? false
        // Only links pay for a second lookup, to learn whether double-clicking them opens a folder.
        var linksToFolder = false
        if isSymbolicLink,
            let target = try? url.resolvingSymlinksInPath().resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
        {
            linksToFolder = (target.isDirectory ?? false) && !(target.isPackage ?? false)
        }
        return FileItem(
            url: shown ?? url,
            name: values.name,
            isDirectory: isDirectory,
            isPackage: values.isPackage ?? false,
            isSymbolicLink: isSymbolicLink,
            linksToFolder: linksToFolder,
            isHidden: values.isHidden ?? false,
            size: isDirectory ? nil : values.fileSize.map(Int64.init),
            modificationDate: values.contentModificationDate,
            label: values.labelNumber.flatMap(FileLabel.init(rawValue:))
        )
    }
}

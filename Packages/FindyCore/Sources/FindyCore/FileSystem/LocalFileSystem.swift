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
    ]

    public init() {}

    public func contents(of directory: URL) async throws -> [FileItem] {
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(Self.itemKeys),
            options: []
        )
        try Task.checkCancellation()
        return urls.map(Self.makeItem)
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

    public func changes(in directory: URL) -> AsyncStream<Void> {
        DirectoryWatcher.changes(in: directory)
    }

    public func mountedVolumes() async -> [Volume] {
        let urls =
            FileManager.default.mountedVolumeURLs(
                includingResourceValuesForKeys: [.volumeLocalizedNameKey],
                options: [.skipHiddenVolumes]
            ) ?? []
        return urls.map { url in
            let name = (try? url.resourceValues(forKeys: [.volumeLocalizedNameKey]))?.volumeLocalizedName
            return Volume(url: url, name: name ?? url.lastPathComponent)
        }
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

    private static func makeItem(_ url: URL) -> FileItem {
        // An entry can vanish between the listing and this read. It is still listed, by name only,
        // rather than failing the whole directory.
        guard let values = try? url.resourceValues(forKeys: itemKeys) else {
            return FileItem(url: url)
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
            url: url,
            name: values.name,
            isDirectory: isDirectory,
            isPackage: values.isPackage ?? false,
            isSymbolicLink: isSymbolicLink,
            linksToFolder: linksToFolder,
            isHidden: values.isHidden ?? false,
            size: isDirectory ? nil : values.fileSize.map(Int64.init),
            modificationDate: values.contentModificationDate
        )
    }
}

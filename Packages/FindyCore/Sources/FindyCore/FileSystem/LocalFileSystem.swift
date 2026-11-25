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

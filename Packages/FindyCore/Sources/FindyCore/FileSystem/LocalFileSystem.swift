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
        return FileItem(
            url: url,
            name: values.name,
            isDirectory: isDirectory,
            isPackage: values.isPackage ?? false,
            isSymbolicLink: values.isSymbolicLink ?? false,
            isHidden: values.isHidden ?? false,
            size: isDirectory ? nil : values.fileSize.map(Int64.init),
            modificationDate: values.contentModificationDate
        )
    }
}

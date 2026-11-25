import Foundation

/// The only door to the disk. Views and models go through it so tests can swap in a fake.
public protocol FileSystemProviding: Sendable {
    /// Lists the direct children of `directory`, hidden files included, in no particular order.
    func contents(of directory: URL) async throws -> [FileItem]

    /// Adds up the logical sizes of every file under `directory`, at any depth.
    /// Symbolic links are not followed and cloud-only files are not downloaded.
    func directorySize(of directory: URL) async throws -> Int64

    /// Yields each time the direct children of `directory` change, until the consumer stops iterating.
    func changes(in directory: URL) -> AsyncStream<Void>

    /// Lists the volumes the user can browse.
    func mountedVolumes() async -> [Volume]

    /// Lists the cloud storage folders synced on this Mac (iCloud Drive, Google Drive…).
    func cloudLocations() async -> [Volume]

    /// Whether `url` is a folder the user can browse (a package such as an app is not).
    func isBrowsableFolder(_ url: URL) async -> Bool

    /// The Git repository `directory` belongs to, if any. Read from the repository's own files.
    func gitInfo(for directory: URL) async -> GitInfo?

    /// What changed in the working tree whose top folder is `root`. `nil` when Git is not
    /// installed or the folder is not a working tree.
    func gitChanges(inRepositoryAt root: URL) async -> GitChanges?

    /// The space left on the volume holding `directory`, in bytes, when the volume reports it.
    func availableSpace(at directory: URL) async -> Int64?
}

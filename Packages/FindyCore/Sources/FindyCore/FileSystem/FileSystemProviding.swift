import Foundation

/// The only door to the disk. Views and models go through it so tests can swap in a fake.
public protocol FileSystemProviding: Sendable {
    /// Lists the direct children of `directory`, hidden files included, in no particular order.
    func contents(of directory: URL) async throws -> [FileItem]

    /// Yields each time the direct children of `directory` change, until the consumer stops iterating.
    func changes(in directory: URL) -> AsyncStream<Void>

    /// Lists the volumes the user can browse.
    func mountedVolumes() async -> [Volume]
}

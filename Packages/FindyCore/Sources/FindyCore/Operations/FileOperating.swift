import Foundation

/// The operations that change the disk, one item at a time.
///
/// None of them overwrites an existing item: when the destination is taken they throw
/// `FileOperationError.nameAlreadyExists`. Callers decide what to do about a conflict.
public protocol FileOperating: Sendable {
    /// Creates a folder in `directory`. If `name` is taken, a free variant is used. Returns the folder.
    func createFolder(in directory: URL, named name: String) async throws -> URL

    /// Renames an item in place. Returns its new location.
    func rename(_ url: URL, to newName: String) async throws -> URL

    /// Moves an item to the Trash. Returns its location there.
    func trash(_ url: URL) async throws -> URL

    /// Moves an item to exactly `destination`. Across volumes this is a full copy followed by the
    /// removal of the source, and the source is removed only once the copy is complete.
    ///
    /// `onBytesCopied` receives the bytes written since its previous call. It is only called when
    /// data is really copied: a move within a volume writes nothing.
    func move(_ url: URL, to destination: URL, onBytesCopied: (@Sendable (Int64) -> Void)?) async throws

    /// Copies an item to exactly `destination`. A copy that fails or is cancelled, even in the
    /// middle of a file, leaves nothing behind.
    ///
    /// `onBytesCopied` receives the bytes written since its previous call. A copy that shares the
    /// data with the original (an APFS clone) is instant and reports nothing.
    func copy(_ url: URL, to destination: URL, onBytesCopied: (@Sendable (Int64) -> Void)?) async throws

    /// The number of bytes a copy of `urls` would have to write, folders included at every depth.
    /// What cannot be read counts for nothing.
    func totalSize(of urls: [URL]) async -> Int64

    /// Whether anything, including a broken symbolic link, exists at `url`.
    func itemExists(at url: URL) async -> Bool

    /// A location in `directory` that is free: `name` itself, else `name 2`, `name 3`…
    /// With `keepingExtension`, the number goes before the extension (`photo 2.jpg`).
    func availableURL(for name: String, in directory: URL, keepingExtension: Bool) async -> URL
}

extension FileOperating {
    public func move(_ url: URL, to destination: URL) async throws {
        try await move(url, to: destination, onBytesCopied: nil)
    }

    public func copy(_ url: URL, to destination: URL) async throws {
        try await copy(url, to: destination, onBytesCopied: nil)
    }
}

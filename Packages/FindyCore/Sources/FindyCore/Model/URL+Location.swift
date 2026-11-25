import Foundation

extension URL {
    /// The same location in one canonical spelling: standardized path, no trailing slash.
    ///
    /// Foundation hands out both `file:///a/b` and `file:///a/b/` for the same folder, and they
    /// compare unequal. Every location kept in history or compared for selection goes through this.
    /// It never touches the disk.
    public var canonicalLocation: URL {
        URL(filePath: standardizedFileURL.path, directoryHint: .notDirectory)
    }
}

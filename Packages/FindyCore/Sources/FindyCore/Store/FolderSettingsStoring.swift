import Foundation

/// Remembers view settings folder by folder.
public protocol FolderSettingsStoring: Sendable {
    /// The settings saved for `folder`, or `nil` if the user never changed anything there.
    func settings(for folder: URL) async throws -> FolderSettings?

    func save(_ settings: FolderSettings, for folder: URL) async throws
}

import Foundation

/// A copy or move waiting for the user to say what to do about names that are already taken.
public struct PendingTransfer: Identifiable, Sendable {
    public let id = UUID()
    /// Everything the user asked to bring here.
    let sources: [URL]
    let isMove: Bool
    let directory: URL
    /// The sources whose name already exists in `directory`.
    public let conflicts: [URL]

    public var conflictNames: [String] { conflicts.map(\.lastPathComponent) }
}

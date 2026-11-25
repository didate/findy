import Foundation

/// How far a working tree is from its last commit and from its upstream branch.
public struct GitChanges: Hashable, Sendable {
    /// Files modified, added, deleted, renamed, in conflict or untracked.
    public let changedFiles: Int
    /// Commits not pushed yet. `nil` when the branch has no upstream.
    public let ahead: Int?
    /// Commits not pulled yet. `nil` when the branch has no upstream.
    public let behind: Int?

    public init(changedFiles: Int, ahead: Int? = nil, behind: Int? = nil) {
        self.changedFiles = changedFiles
        self.ahead = ahead
        self.behind = behind
    }
}

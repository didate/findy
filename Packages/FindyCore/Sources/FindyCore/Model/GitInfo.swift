import Foundation

/// What Findy shows about the Git repository a folder belongs to.
public struct GitInfo: Hashable, Sendable {
    /// The branch checked out, or the short commit hash when `HEAD` is detached.
    public let head: String
    /// True when no branch is checked out (a tag, a commit, a rebase in progress).
    public let isDetached: Bool
    /// The top folder of the working tree.
    public let root: URL
    /// Where the repository keeps `HEAD`: `.git` itself, or the folder a linked worktree points to.
    public let gitDirectory: URL

    public init(head: String, isDetached: Bool, root: URL, gitDirectory: URL) {
        self.head = head
        self.isDetached = isDetached
        self.root = root
        self.gitDirectory = gitDirectory
    }
}

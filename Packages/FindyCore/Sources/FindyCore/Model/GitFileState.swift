/// What Git says about one entry of a working tree.
public enum GitFileState: String, Hashable, Sendable {
    case modified
    /// New and already staged.
    case added
    case deleted
    case renamed
    case conflicted
    /// New and not staged yet.
    case untracked
    case ignored
    /// A folder with changed entries somewhere below it.
    case containsChanges
}

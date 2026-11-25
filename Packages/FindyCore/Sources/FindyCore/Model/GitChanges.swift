import Foundation

/// How far a working tree is from its last commit and from its upstream branch.
public struct GitChanges: Hashable, Sendable {
    /// Files modified, added, deleted, renamed, in conflict or untracked.
    public let changedFiles: Int
    /// Commits not pushed yet. `nil` when the branch has no upstream.
    public let ahead: Int?
    /// Commits not pulled yet. `nil` when the branch has no upstream.
    public let behind: Int?
    /// The state of each entry Git reported, and of the folders above the changed ones, by path
    /// relative to the top of the working tree.
    private let states: [String: GitFileState]

    /// - Parameter states: states by path relative to the top of the working tree, as Git reports
    ///   them: a folder may end with `/`.
    public init(changedFiles: Int, ahead: Int? = nil, behind: Int? = nil, states: [String: GitFileState] = [:]) {
        self.changedFiles = changedFiles
        self.ahead = ahead
        self.behind = behind

        var all: [String: GitFileState] = [:]
        for (path, state) in states {
            all[Self.key(path)] = state
        }
        // A folder is flagged when something changed below it, so changes can be found from the top.
        for (path, state) in states where state != .ignored {
            var parent = Self.key(path)
            while let slash = parent.lastIndex(of: "/") {
                parent = String(parent[..<slash])
                if all[parent] == nil { all[parent] = .containsChanges }
            }
        }
        self.states = all
    }

    /// The state of the entry at `path`, relative to the top of the working tree. `nil` when it
    /// is tracked and unchanged.
    public func state(forRelativePath path: String) -> GitFileState? {
        let key = Self.key(path)
        if let state = states[key] { return state }
        // Git reports a whole untracked or ignored folder as one entry: what is inside shares its state.
        var parent = key
        while let slash = parent.lastIndex(of: "/") {
            parent = String(parent[..<slash])
            if let state = states[parent], state == .untracked || state == .ignored { return state }
        }
        return nil
    }

    /// Git on macOS reports names in composed form (`core.precomposeUnicode`) while the disk may
    /// hold them decomposed: "é" would not match "é" without this.
    private static func key(_ path: String) -> String {
        let trimmed = path.hasSuffix("/") ? String(path.dropLast()) : path
        return trimmed.precomposedStringWithCanonicalMapping
    }
}

import Foundation

/// One entry of a disk usage report: a folder with what it holds, a file, or the small files of
/// a folder counted together.
public struct DiskUsageNode: Sendable, Identifiable {
    public enum Kind: Sendable {
        case folder
        case file
        /// The files of a folder too small to be listed one by one.
        case smallerFiles
    }

    /// The name on disk. Empty for `smallerFiles`, which stands for no single entry.
    public let name: String
    public let kind: Kind
    /// Space taken on the volume, in bytes, everything inside included.
    public let size: Int64
    /// How many files this stands for: one for a file, all those inside for a folder.
    public let fileCount: Int
    /// Folders inside that could not be read, and whose size is therefore missing.
    public let unreadableCount: Int
    /// What a folder holds, largest first. Empty for anything else.
    public let children: [DiskUsageNode]

    /// Names are unique within a folder, and `smallerFiles` appears at most once in it.
    public var id: String { name }

    public init(
        name: String, kind: Kind, size: Int64, fileCount: Int = 1, unreadableCount: Int = 0,
        children: [DiskUsageNode] = []
    ) {
        self.name = name
        self.kind = kind
        self.size = size
        self.fileCount = fileCount
        self.unreadableCount = unreadableCount
        self.children = children
    }

    /// A folder made of `children`, which are sorted and added up here.
    public static func folder(named name: String, children: [DiskUsageNode], unreadableCount: Int = 0) -> Self {
        DiskUsageNode(
            name: name, kind: .folder,
            size: children.reduce(0) { $0 + $1.size },
            fileCount: children.reduce(0) { $0 + $1.fileCount },
            unreadableCount: children.reduce(unreadableCount) { $0 + $1.unreadableCount },
            children: children.sorted(by: Self.largestFirst))
    }

    /// Largest first; equal sizes are ordered by name so the list does not shuffle between scans.
    public static func largestFirst(_ a: DiskUsageNode, _ b: DiskUsageNode) -> Bool {
        a.size != b.size ? a.size > b.size : a.name.localizedStandardCompare(b.name) == .orderedAscending
    }

    /// The node at `path`, a list of names going down from this folder. `nil` when it is not there.
    public func descendant(at path: some Collection<String>) -> DiskUsageNode? {
        guard let first = path.first else { return self }
        return children.first { $0.name == first && $0.kind != .smallerFiles }?.descendant(at: path.dropFirst())
    }

    /// This folder without the entry at `path`, every size above it lowered accordingly.
    /// Unchanged when there is nothing at `path`.
    public func removing(at path: some Collection<String>) -> DiskUsageNode {
        guard let first = path.first,
            let index = children.firstIndex(where: { $0.name == first && $0.kind != .smallerFiles })
        else { return self }
        var remaining = children
        if path.count == 1 {
            remaining.remove(at: index)
        } else {
            remaining[index] = remaining[index].removing(at: path.dropFirst())
        }
        // Unreadable folders directly inside this one are not children: they are what is left of
        // the count once the children's own are taken out.
        let ownUnreadable = unreadableCount - children.reduce(0) { $0 + $1.unreadableCount }
        return .folder(named: name, children: remaining, unreadableCount: ownUnreadable)
    }
}

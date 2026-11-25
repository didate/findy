import Foundation

/// How a directory listing is ordered.
public struct FileSort: Equatable, Sendable {
    public enum Key: String, Sendable, CaseIterable {
        case name
        case dateModified
        case size
    }

    public var key: Key
    public var ascending: Bool
    /// Folders stay grouped at the top whatever the direction.
    public var foldersFirst: Bool

    public init(key: Key = .name, ascending: Bool = true, foldersFirst: Bool = true) {
        self.key = key
        self.ascending = ascending
        self.foldersFirst = foldersFirst
    }

    public func sorted(_ items: [FileItem]) -> [FileItem] {
        items.sorted { lhs, rhs in
            if foldersFirst, lhs.isFolder != rhs.isFolder {
                return lhs.isFolder
            }
            let primary = compare(lhs, rhs)
            if primary != .orderedSame {
                return primary == (ascending ? .orderedAscending : .orderedDescending)
            }
            // Ties always fall back to the name, ascending, so the order is stable for the user.
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    private func compare(_ lhs: FileItem, _ rhs: FileItem) -> ComparisonResult {
        switch key {
        case .name:
            return lhs.name.localizedStandardCompare(rhs.name)
        case .dateModified:
            return Self.order(lhs.modificationDate ?? .distantPast, rhs.modificationDate ?? .distantPast)
        case .size:
            // Unknown sizes (folders not computed yet) sort before every known size.
            return Self.order(lhs.size ?? -1, rhs.size ?? -1)
        }
    }

    private static func order<T: Comparable>(_ lhs: T, _ rhs: T) -> ComparisonResult {
        if lhs < rhs { return .orderedAscending }
        if lhs > rhs { return .orderedDescending }
        return .orderedSame
    }
}

import Foundation

/// How the user likes to see one particular folder.
public struct FolderSettings: Equatable, Sendable {
    public var sort: FileSort
    public var showsHiddenFiles: Bool
    /// Whether the list is split in sections by modification date (Today, Yesterday…).
    public var groupsByDate: Bool

    public init(sort: FileSort = FileSort(), showsHiddenFiles: Bool = false, groupsByDate: Bool = false) {
        self.sort = sort
        self.showsHiddenFiles = showsHiddenFiles
        self.groupsByDate = groupsByDate
    }
}

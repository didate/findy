import Foundation

/// How the user likes to see one particular folder.
public struct FolderSettings: Equatable, Sendable {
    public var sort: FileSort
    public var showsHiddenFiles: Bool

    public init(sort: FileSort = FileSort(), showsHiddenFiles: Bool = false) {
        self.sort = sort
        self.showsHiddenFiles = showsHiddenFiles
    }
}

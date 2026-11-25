import Foundation

/// One entry of a directory listing, with the attributes the list view displays.
public struct FileItem: Identifiable, Hashable, Sendable {
    public let url: URL
    public let name: String
    public let isDirectory: Bool
    /// A directory presented as a single file (`.app`, `.bundle`…).
    public let isPackage: Bool
    public let isSymbolicLink: Bool
    /// A symbolic link whose target is a folder the user can navigate into.
    public let linksToFolder: Bool
    public let isHidden: Bool
    /// Logical size in bytes. `nil` for directories until it is computed in the background.
    public var size: Int64?
    public let modificationDate: Date?

    public var id: URL { url }

    /// A directory the user can navigate into.
    public var isFolder: Bool { (isDirectory && !isPackage) || linksToFolder }

    public init(
        url: URL,
        name: String? = nil,
        isDirectory: Bool = false,
        isPackage: Bool = false,
        isSymbolicLink: Bool = false,
        linksToFolder: Bool = false,
        isHidden: Bool = false,
        size: Int64? = nil,
        modificationDate: Date? = nil
    ) {
        self.url = url
        self.name = name ?? url.lastPathComponent
        self.isDirectory = isDirectory
        self.isPackage = isPackage
        self.isSymbolicLink = isSymbolicLink
        self.linksToFolder = linksToFolder
        self.isHidden = isHidden
        self.size = size
        self.modificationDate = modificationDate
    }
}

import Foundation

/// Everything Get Info shows about one entry. Read from its attributes alone: the content of a
/// file is never opened, so a cloud-only file is not downloaded.
public struct FileDetails: Hashable, Sendable {
    public let url: URL
    public let name: String
    /// The system's description of the type ("PDF document", "Folder"), in the user's language.
    public let kind: String?
    /// A directory the user can navigate into. Its size has to be added up separately.
    public let isFolder: Bool
    /// Logical size in bytes. `nil` for a folder.
    public let size: Int64?
    /// Space taken on the volume, which differs from `size` for sparse, compressed or tiny files.
    public let sizeOnDisk: Int64?
    public let creationDate: Date?
    public let modificationDate: Date?
    public let owner: String?
    public let group: String?
    /// The POSIX permission bits, for example `0o755`.
    public let permissions: UInt16?
    /// Where a symbolic link points, as written in the link.
    public let linkDestination: String?

    public init(
        url: URL, name: String, kind: String? = nil, isFolder: Bool = false, size: Int64? = nil,
        sizeOnDisk: Int64? = nil, creationDate: Date? = nil, modificationDate: Date? = nil, owner: String? = nil,
        group: String? = nil, permissions: UInt16? = nil, linkDestination: String? = nil
    ) {
        self.url = url
        self.name = name
        self.kind = kind
        self.isFolder = isFolder
        self.size = size
        self.sizeOnDisk = sizeOnDisk
        self.creationDate = creationDate
        self.modificationDate = modificationDate
        self.owner = owner
        self.group = group
        self.permissions = permissions
        self.linkDestination = linkDestination
    }

    /// The permissions the way `ls -l` writes them, for example `rwxr-xr-x`.
    public var permissionString: String? {
        guard let permissions else { return nil }
        let letters: [Character] = ["r", "w", "x"]
        return String(
            (0..<9).map { index in
                permissions & (0o400 >> UInt16(index)) != 0 ? letters[index % 3] : "-"
            })
    }
}

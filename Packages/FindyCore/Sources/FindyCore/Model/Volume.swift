import Foundation

/// A place shown under Locations in the sidebar: a mounted volume or a cloud storage folder.
public struct Volume: Identifiable, Hashable, Sendable {
    public let url: URL
    public let name: String
    /// True for what the user plugs in and must eject before unplugging: USB drives, SD cards,
    /// disk images, network shares.
    public let isEjectable: Bool

    public var id: URL { url }

    public init(url: URL, name: String, isEjectable: Bool = false) {
        self.url = url
        self.name = name
        self.isEjectable = isEjectable
    }
}

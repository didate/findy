import Foundation

/// A place shown under Locations in the sidebar: a mounted volume or a cloud storage folder.
public struct Volume: Identifiable, Hashable, Sendable {
    public let url: URL
    public let name: String

    public var id: URL { url }

    public init(url: URL, name: String) {
        self.url = url
        self.name = name
    }
}

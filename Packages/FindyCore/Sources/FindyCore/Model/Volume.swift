import Foundation

/// A mounted volume shown in the sidebar.
public struct Volume: Identifiable, Hashable, Sendable {
    public let url: URL
    public let name: String

    public var id: URL { url }

    public init(url: URL, name: String) {
        self.url = url
        self.name = name
    }
}

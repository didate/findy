import Foundation

/// What Get Info was asked about: one entry, or several.
public struct InfoTarget: Identifiable, Hashable, Sendable {
    public let urls: [URL]

    public var id: [URL] { urls }

    public init(urls: [URL]) {
        self.urls = urls
    }
}

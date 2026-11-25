import Foundation

/// One clickable segment of the path bar.
public struct PathCrumb: Identifiable, Hashable, Sendable {
    public let name: String
    public let url: URL

    public var id: URL { url }
}

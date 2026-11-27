import Foundation

/// The folder a Disk Usage sheet was opened on.
public struct DiskUsageTarget: Identifiable, Hashable, Sendable {
    public let url: URL

    public var id: URL { url }

    public init(url: URL) {
        self.url = url
    }
}

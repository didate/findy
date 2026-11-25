import Foundation

/// Where an item was and where it is now. Enough to put it back.
public struct Relocation: Hashable, Sendable {
    public let source: URL
    public let destination: URL

    public init(source: URL, destination: URL) {
        self.source = source
        self.destination = destination
    }

    /// The same move, the other way round.
    public var reversed: Relocation {
        Relocation(source: destination, destination: source)
    }
}

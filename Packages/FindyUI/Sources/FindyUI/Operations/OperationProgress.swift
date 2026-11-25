import Foundation

/// How far a copy or a move has got.
public struct OperationProgress: Equatable, Sendable {
    public let isMove: Bool
    /// Bytes written so far.
    public var completedBytes: Int64 = 0
    /// Bytes to write in all. `nil` until the items have been measured, which runs alongside the
    /// copy so that it starts at once.
    public var totalBytes: Int64?

    /// Between 0 and 1, or `nil` while the total is unknown.
    public var fraction: Double? {
        guard let totalBytes, totalBytes > 0 else { return nil }
        return min(1, Double(completedBytes) / Double(totalBytes))
    }
}

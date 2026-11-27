import Foundation

/// What a disk usage scan reports while it runs.
public enum DiskUsageEvent: Sendable {
    /// How far the scan is: files counted and bytes added up so far, the whole tree included.
    case progress(files: Int, bytes: Int64)
    /// A direct child of the folder scanned, complete with everything under it.
    case entry(DiskUsageNode)
    /// Folders directly inside the folder scanned were skipped because they could not be read.
    case unreadable(Int)
}

import Foundation

/// Why a file operation was refused before touching the disk.
/// Failures of the disk itself surface as the system's own errors, which already name the file.
public enum FileOperationError: Error, Equatable, Sendable {
    /// Something already exists at the destination. Nothing is ever overwritten silently.
    case nameAlreadyExists(URL)
    /// The name is empty, is `.` or `..`, or contains a path separator.
    case invalidName(String)
    /// A folder cannot be copied or moved into itself or one of its own subfolders.
    case destinationInsideSource(source: URL, destination: URL)
}

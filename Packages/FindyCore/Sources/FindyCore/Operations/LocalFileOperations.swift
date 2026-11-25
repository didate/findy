import Foundation

/// `FileOperating` on the real disk.
public struct LocalFileOperations: FileOperating {
    public init() {}

    public func createFolder(in directory: URL, named name: String) async throws -> URL {
        try Self.validate(name)
        let url = Self.freeURL(for: name, in: directory, keepingExtension: false)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }

    public func rename(_ url: URL, to newName: String) async throws -> URL {
        try Self.validate(newName)
        let destination = url.deletingLastPathComponent().appendingPathComponent(newName)
        guard destination.lastPathComponent != url.lastPathComponent else { return url }
        // On a case-insensitive volume `a.txt` → `A.txt` finds itself at the destination: that is
        // not a conflict.
        if Self.exists(destination), !Self.isSameItem(url, destination) {
            throw FileOperationError.nameAlreadyExists(destination)
        }
        try FileManager.default.moveItem(at: url, to: destination)
        return destination
    }

    public func trash(_ url: URL) async throws -> URL {
        var trashed: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &trashed)
        guard let trashed = trashed as URL? else {
            // Some volumes have no Trash and delete at once; the system reports that as an error
            // before we get here. This is the case where it claims success without a location.
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: url.path])
        }
        return trashed
    }

    public func move(_ url: URL, to destination: URL) async throws {
        try Self.checkDestination(destination, forSource: url)
        if Self.isOnSameVolume(url, as: destination.deletingLastPathComponent()) {
            try FileManager.default.moveItem(at: url, to: destination)
        } else {
            try Self.copyAtomically(url, to: destination)
            try FileManager.default.removeItem(at: url)
        }
    }

    public func copy(_ url: URL, to destination: URL) async throws {
        try Self.checkDestination(destination, forSource: url)
        try Task.checkCancellation()
        try Self.copyAtomically(url, to: destination)
    }

    public func itemExists(at url: URL) async -> Bool {
        Self.exists(url)
    }

    public func availableURL(for name: String, in directory: URL, keepingExtension: Bool) async -> URL {
        Self.freeURL(for: name, in: directory, keepingExtension: keepingExtension)
    }

    // MARK: Helpers

    private static func validate(_ name: String) throws {
        if name.isEmpty || name == "." || name == ".." || name.contains("/") {
            throw FileOperationError.invalidName(name)
        }
    }

    private static func checkDestination(_ destination: URL, forSource source: URL) throws {
        let sourcePath = source.standardizedFileURL.path
        let destinationPath = destination.standardizedFileURL.path
        if destinationPath == sourcePath || destinationPath.hasPrefix(sourcePath + "/") {
            throw FileOperationError.destinationInsideSource(source: source, destination: destination)
        }
        if exists(destination) {
            throw FileOperationError.nameAlreadyExists(destination)
        }
    }

    /// Copies under a temporary hidden name, then renames: the destination name only ever holds a
    /// complete copy. Symbolic links are copied as links, never followed.
    private static func copyAtomically(_ source: URL, to destination: URL) throws {
        let partial = destination.deletingLastPathComponent()
            .appendingPathComponent(".findy-partial-\(UUID().uuidString)")
        do {
            try FileManager.default.copyItem(at: source, to: partial)
            try FileManager.default.moveItem(at: partial, to: destination)
        } catch {
            // Best-effort cleanup of our own half-written copy; the error worth reporting is the
            // one that interrupted the copy.
            try? FileManager.default.removeItem(at: partial)
            throw error
        }
    }

    /// `lstat`, not `fileExists`: a broken symbolic link still occupies its name.
    private static func exists(_ url: URL) -> Bool {
        var info = stat()
        return lstat(url.path, &info) == 0
    }

    private static func isSameItem(_ first: URL, _ second: URL) -> Bool {
        var firstInfo = stat()
        var secondInfo = stat()
        guard lstat(first.path, &firstInfo) == 0, lstat(second.path, &secondInfo) == 0 else { return false }
        return firstInfo.st_dev == secondInfo.st_dev && firstInfo.st_ino == secondInfo.st_ino
    }

    private static func isOnSameVolume(_ first: URL, as second: URL) -> Bool {
        var firstInfo = stat()
        var secondInfo = stat()
        guard lstat(first.path, &firstInfo) == 0, stat(second.path, &secondInfo) == 0 else { return false }
        return firstInfo.st_dev == secondInfo.st_dev
    }

    private static func freeURL(for name: String, in directory: URL, keepingExtension: Bool) -> URL {
        let candidate = directory.appendingPathComponent(name)
        guard exists(candidate) else { return candidate }
        let fileExtension = keepingExtension ? (name as NSString).pathExtension : ""
        let stem = fileExtension.isEmpty ? name : (name as NSString).deletingPathExtension
        var number = 2
        while true {
            let numbered = fileExtension.isEmpty ? "\(stem) \(number)" : "\(stem) \(number).\(fileExtension)"
            let url = directory.appendingPathComponent(numbered)
            if !exists(url) { return url }
            number += 1
        }
    }
}

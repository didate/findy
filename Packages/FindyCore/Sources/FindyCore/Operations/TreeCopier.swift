import Darwin
import Foundation

/// Copies a file or a whole folder tree with `copyfile(3)`.
///
/// `FileManager.copyItem` can neither report progress nor stop in the middle of a large file.
/// `copyfile` calls back as data is written, and stops when the callback says so.
enum TreeCopier {
    // The header defines these as macros Swift cannot import.
    private static let flagAll: UInt32 = 0b1111  // ACL, stat, extended attributes and data.
    private static let flagRecursive: UInt32 = 1 << 15
    private static let flagNoFollow: UInt32 = (1 << 18) | (1 << 19)
    private static let flagClone: UInt32 = 1 << 24
    private static let stateStatusCallback: UInt32 = 6
    private static let stateStatusContext: UInt32 = 7
    private static let stateCopied: UInt32 = 8
    private static let whatFile: Int32 = 1
    private static let whatData: Int32 = 4
    private static let stageStart: Int32 = 1
    private static let stageError: Int32 = 3
    private static let stageProgress: Int32 = 4
    private static let continueCopy: Int32 = 0
    private static let quitCopy: Int32 = 2

    /// Copies `source` to `destination`, which must not exist. Symbolic links are copied as links.
    ///
    /// - Parameters:
    ///   - allowingClones: on a volume that supports it, share the data instead of duplicating it.
    ///     A clone is instant and reports no bytes.
    ///   - onBytesCopied: called with the number of bytes written since the previous call.
    /// - Throws: `CancellationError` if the current task is cancelled, even in the middle of a
    ///   file. What was written so far is left for the caller to remove.
    static func copy(
        from source: URL, to destination: URL, allowingClones: Bool,
        onBytesCopied: (@Sendable (Int64) -> Void)?
    ) throws {
        guard let state = copyfile_state_alloc() else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(ENOMEM))
        }
        defer { copyfile_state_free(state) }

        let context = Context(onBytesCopied: onBytesCopied)
        let info = Unmanaged.passRetained(context)
        defer { info.release() }
        copyfile_state_set(state, stateStatusCallback, unsafeBitCast(callback, to: UnsafeRawPointer.self))
        copyfile_state_set(state, stateStatusContext, info.toOpaque())

        var flags = flagAll | flagRecursive | flagNoFollow
        if allowingClones { flags |= flagClone }

        guard copyfile(source.path, destination.path, state, flags) == 0 else {
            let code = errno
            if context.wasCancelled || code == ECANCELED { throw CancellationError() }
            throw NSError(
                domain: NSPOSIXErrorDomain, code: Int(code),
                userInfo: [NSFilePathErrorKey: context.failedPath ?? source.path])
        }
    }

    /// State of one `copy` call. Only touched by the callback, which `copyfile` runs synchronously
    /// on the thread that called it.
    private final class Context {
        let onBytesCopied: (@Sendable (Int64) -> Void)?
        /// Bytes of the file being copied that were already reported.
        var reportedForCurrentFile: Int64 = 0
        var wasCancelled = false
        var failedPath: String?

        init(onBytesCopied: (@Sendable (Int64) -> Void)?) {
            self.onBytesCopied = onBytesCopied
        }
    }

    private static let callback: copyfile_callback_t = { what, stage, state, source, _, info in
        guard let info else { return continueCopy }
        let context = Unmanaged<Context>.fromOpaque(info).takeUnretainedValue()

        // `copyfile` runs inside the task that asked for the copy, so that task's cancellation
        // is visible here.
        if Task.isCancelled {
            context.wasCancelled = true
            return quitCopy
        }
        if stage == stageError {
            context.failedPath = source.map { String(cString: $0) }
            return quitCopy
        }
        if what == whatFile, stage == stageStart {
            context.reportedForCurrentFile = 0
        } else if what == whatData, stage == stageProgress, let state {
            var copied: off_t = 0
            if copyfile_state_get(state, stateCopied, &copied) == 0 {
                // A single file copied without recursion never announces itself with a start.
                if copied < context.reportedForCurrentFile { context.reportedForCurrentFile = 0 }
                let delta = Int64(copied) - context.reportedForCurrentFile
                context.reportedForCurrentFile = Int64(copied)
                if delta > 0 { context.onBytesCopied?(delta) }
            }
        }
        return continueCopy
    }
}

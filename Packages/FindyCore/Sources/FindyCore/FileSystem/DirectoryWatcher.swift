import CoreServices
import Foundation

/// Reports changes to a directory, using FSEvents: to its direct children, or to its whole tree.
enum DirectoryWatcher {
    /// A stream that yields each time something is added to, removed from, renamed in or modified
    /// directly inside `directory`, or when `directory` itself moves or disappears.
    ///
    /// Changes deeper in the tree are ignored unless `recursive` is set. Bursts are coalesced: a
    /// slow consumer gets one pending element, not a backlog. The watch stops when the consumer
    /// stops iterating.
    static func changes(
        in directory: URL, recursive: Bool = false, latency: TimeInterval = 0.2
    ) -> AsyncStream<Void> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            // FSEvents reports resolved paths (`/private/tmp/x`, never `/tmp/x`).
            guard let watchedPath = realPath(of: directory.path) else {
                continuation.finish()
                return
            }
            let state = State(watchedPath: watchedPath, isRecursive: recursive, continuation: continuation)
            let info = Unmanaged.passRetained(state)
            var context = FSEventStreamContext(
                version: 0, info: info.toOpaque(), retain: nil, release: nil, copyDescription: nil)
            let flags =
                kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents
                | kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagWatchRoot

            guard
                let stream = FSEventStreamCreate(
                    nil, callback, &context, [watchedPath] as CFArray,
                    FSEventStreamEventId(kFSEventStreamEventIdSinceNow), latency, UInt32(flags))
            else {
                info.release()
                continuation.finish()
                return
            }
            // FSEvents has no async API: it delivers on a dispatch queue.
            let queue = DispatchQueue(label: "app.findy.directory-watcher")
            FSEventStreamSetDispatchQueue(stream, queue)
            FSEventStreamStart(stream)

            let handle = StreamHandle(stream: stream, info: info)
            continuation.onTermination = { _ in
                // Torn down on the delivery queue, so no callback can run during or after it.
                queue.async { handle.tearDown() }
            }
        }
    }

    private static let callback: FSEventStreamCallback = { _, info, count, paths, flags, _ in
        guard let info else { return }
        let state = Unmanaged<State>.fromOpaque(info).takeUnretainedValue()
        let paths = unsafeBitCast(paths, to: NSArray.self) as? [String] ?? []
        let structural = UInt32(kFSEventStreamEventFlagRootChanged | kFSEventStreamEventFlagMustScanSubDirs)
        for index in 0..<count {
            let flag = flags[index]
            if flag & structural != 0 || (index < paths.count && state.concerns(paths[index])) {
                state.continuation.yield()
                return
            }
        }
    }

    private static func realPath(of path: String) -> String? {
        guard let resolved = realpath(path, nil) else { return nil }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    private final class State: Sendable {
        let watchedPath: String
        let isRecursive: Bool
        let continuation: AsyncStream<Void>.Continuation

        init(watchedPath: String, isRecursive: Bool, continuation: AsyncStream<Void>.Continuation) {
            self.watchedPath = watchedPath
            self.isRecursive = isRecursive
            self.continuation = continuation
        }

        /// True for the watched directory itself and for its direct children; for anything
        /// FSEvents reports when the whole tree is watched.
        func concerns(_ path: String) -> Bool {
            if isRecursive { return true }
            var path = path
            if path.count > 1, path.hasSuffix("/") { path.removeLast() }
            return path == watchedPath || (path as NSString).deletingLastPathComponent == watchedPath
        }
    }

    /// Owns the FSEvents stream and the retained `State` until `tearDown`.
    ///
    /// `@unchecked Sendable` is safe: the pointers are written once here and read once, by
    /// `tearDown`, which always runs on the stream's own serial queue.
    private final class StreamHandle: @unchecked Sendable {
        private let stream: FSEventStreamRef
        private let info: Unmanaged<State>

        init(stream: FSEventStreamRef, info: Unmanaged<State>) {
            self.stream = stream
            self.info = info
        }

        func tearDown() {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            info.release()
        }
    }
}

import Foundation
import Testing

@testable import FindyCore

@Suite struct DirectoryWatcherTests {
    private func withScratchDirectory(_ body: (URL) async throws -> Void) async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FindyCoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try await body(directory)
    }

    /// Runs `trigger` once the watch is live, and reports whether a change arrived within `timeout`.
    private func changeArrives(
        in directory: URL, recursive: Bool = false, timeout: Duration,
        after trigger: @escaping @Sendable () throws -> Void
    ) async throws -> Bool {
        let changes = DirectoryWatcher.changes(in: directory, recursive: recursive, latency: 0.05)
        return try await withThrowingTaskGroup(of: Bool.self) { group in
            group.addTask {
                for await _ in changes { return true }
                return false
            }
            group.addTask {
                // FSEvents needs a moment before it reports events for a new stream.
                try await Task.sleep(for: .milliseconds(300))
                try trigger()
                try await Task.sleep(for: timeout)
                return false
            }
            let first = try await group.next() ?? false
            group.cancelAll()
            return first
        }
    }

    @Test func reportsANewFile() async throws {
        try await withScratchDirectory { directory in
            let arrived = try await changeArrives(in: directory, timeout: .seconds(5)) {
                try Data("x".utf8).write(to: directory.appendingPathComponent("new.txt"))
            }
            #expect(arrived)
        }
    }

    @Test func reportsARemovedFile() async throws {
        try await withScratchDirectory { directory in
            let file = directory.appendingPathComponent("old.txt")
            try Data().write(to: file)
            let arrived = try await changeArrives(in: directory, timeout: .seconds(5)) {
                try FileManager.default.removeItem(at: file)
            }
            #expect(arrived)
        }
    }

    @Test func ignoresChangesDeeperInTheTree() async throws {
        try await withScratchDirectory { directory in
            let deep = directory.appendingPathComponent("a/b", isDirectory: true)
            try FileManager.default.createDirectory(at: deep, withIntermediateDirectories: true)
            // Let the events of the setup above drain before watching.
            try await Task.sleep(for: .milliseconds(500))
            let arrived = try await changeArrives(in: directory, timeout: .seconds(1)) {
                try Data("x".utf8).write(to: deep.appendingPathComponent("deep.txt"))
            }
            #expect(!arrived)
        }
    }

    @Test func reportsChangesDeeperInTheTreeWhenAskedTo() async throws {
        try await withScratchDirectory { directory in
            let deep = directory.appendingPathComponent("a/b", isDirectory: true)
            try FileManager.default.createDirectory(at: deep, withIntermediateDirectories: true)
            try await Task.sleep(for: .milliseconds(500))
            let arrived = try await changeArrives(in: directory, recursive: true, timeout: .seconds(5)) {
                try Data("x".utf8).write(to: deep.appendingPathComponent("deep.txt"))
            }
            #expect(arrived)
        }
    }

    @Test func finishesAtOnceForAMissingDirectory() async {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("FindyCoreTests-missing-\(UUID().uuidString)")
        var count = 0
        for await _ in DirectoryWatcher.changes(in: missing) { count += 1 }
        #expect(count == 0)
    }
}

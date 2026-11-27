import Foundation
import Testing

@testable import FindyCore

@Suite struct DiskUsageScannerTests {
    private func withScratchDirectory(_ body: (URL) async throws -> Void) async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FindyCoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try await body(directory)
    }

    private func write(_ bytes: Int, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 7, count: bytes).write(to: url)
    }

    /// Runs a whole scan and gathers what it reported.
    private func scan(_ directory: URL) async throws -> (entries: [DiskUsageNode], files: Int, unreadable: Int) {
        var entries: [DiskUsageNode] = []
        var files = 0
        var unreadable = 0
        for try await event in LocalFileSystem().diskUsage(of: directory) {
            switch event {
            case .entry(let node): entries.append(node)
            case .progress(let count, _): files = count
            case .unreadable(let count): unreadable = count
            }
        }
        return (entries.sorted(by: DiskUsageNode.largestFirst), files, unreadable)
    }

    @Test func addsUpEveryLevelAndListsTheLargestFirst() async throws {
        try await withScratchDirectory { directory in
            try write(300_000, to: directory.appendingPathComponent("Big/deep/down/movie.bin"))
            try write(50_000, to: directory.appendingPathComponent("Big/notes.txt"))
            try write(20_000, to: directory.appendingPathComponent("Small/a.txt"))
            try write(100_000, to: directory.appendingPathComponent("été 🌞.dat"))

            let result = try await scan(directory)

            #expect(result.entries.map(\.name) == ["Big", "été 🌞.dat", "Small"])
            #expect(result.files == 4)
            let big = try #require(result.entries.first)
            #expect(big.fileCount == 2)
            #expect(big.children.map(\.name) == ["deep", "notes.txt"])
            #expect(big.size == big.children.reduce(0) { $0 + $1.size })
            // On disk a file takes whole blocks: at least its length, never much more.
            let movie = try #require(big.descendant(at: ["deep", "down", "movie.bin"]))
            #expect(movie.size >= 300_000 && movie.size < 400_000)
            #expect(movie.kind == .file)
        }
    }

    @Test func doesNotFollowSymbolicLinks() async throws {
        try await withScratchDirectory { directory in
            let outside = directory.appendingPathComponent("outside")
            try write(500_000, to: outside.appendingPathComponent("huge.bin"))
            let scanned = directory.appendingPathComponent("scanned")
            try write(10_000, to: scanned.appendingPathComponent("real.txt"))
            try FileManager.default.createSymbolicLink(
                at: scanned.appendingPathComponent("link"), withDestinationURL: outside)

            let result = try await scan(scanned)

            let link = try #require(result.entries.first { $0.name == "link" })
            #expect(link.kind == .file)
            #expect(link.size < 10_000)
            #expect(result.files == 2)
        }
    }

    @Test func countsFoldersThatCannotBeRead() async throws {
        try await withScratchDirectory { directory in
            let locked = directory.appendingPathComponent("Open/locked")
            try write(10_000, to: locked.appendingPathComponent("secret.txt"))
            try write(10_000, to: directory.appendingPathComponent("Top/secret.txt"))
            let top = directory.appendingPathComponent("Top")
            try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
            try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: top.path)
            defer {
                try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path)
                try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: top.path)
            }

            let result = try await scan(directory)

            #expect(result.entries.map(\.name) == ["Open"])
            #expect(result.entries.first?.unreadableCount == 1)
            #expect(result.entries.first?.size == 0)
            #expect(result.unreadable == 1)
        }
    }

    @Test func countsTheSmallFilesOfACrowdedFolderTogether() async throws {
        try await withScratchDirectory { directory in
            let crowded = directory.appendingPathComponent("Crowded")
            for index in 0..<70 {
                try write(index == 0 ? 50_000 : 10, to: crowded.appendingPathComponent("file-\(index).txt"))
            }

            let result = try await scan(directory)

            let folder = try #require(result.entries.first)
            #expect(folder.fileCount == 70)
            #expect(folder.children.count == DiskUsageScanner.listedFilesPerFolder + 1)
            #expect(folder.children.first?.name == "file-0.txt")
            let rest = try #require(folder.children.first { $0.kind == .smallerFiles })
            #expect(rest.fileCount == 70 - DiskUsageScanner.listedFilesPerFolder)
            #expect(folder.size == folder.children.reduce(0) { $0 + $1.size })
        }
    }

    @Test func failsWhenTheFolderItselfCannotBeRead() async throws {
        try await withScratchDirectory { directory in
            await #expect(throws: (any Error).self) {
                _ = try await scan(directory.appendingPathComponent("missing"))
            }
        }
    }

    @Test func stopsWhenTheConsumerStopsListening() async throws {
        try await withScratchDirectory { directory in
            for index in 0..<30 {
                try write(10, to: directory.appendingPathComponent("Folder-\(index)/file.txt"))
            }

            var seen = 0
            for try await event in LocalFileSystem().diskUsage(of: directory) {
                if case .entry = event {
                    seen += 1
                    break
                }
            }

            #expect(seen == 1)
        }
    }

    @Test func removingAnEntryLowersEverySizeAboveIt() {
        let tree = DiskUsageNode.folder(
            named: "root",
            children: [
                .folder(
                    named: "a",
                    children: [
                        DiskUsageNode(name: "x", kind: .file, size: 100),
                        DiskUsageNode(name: "y", kind: .file, size: 40),
                    ], unreadableCount: 2),
                DiskUsageNode(name: "b", kind: .file, size: 10),
            ])

        let pruned = tree.removing(at: ["a", "x"])

        #expect(pruned.size == 50)
        #expect(pruned.fileCount == 2)
        #expect(pruned.unreadableCount == 2)
        #expect(pruned.descendant(at: ["a"])?.size == 40)
        #expect(pruned.descendant(at: ["a", "x"]) == nil)
        #expect(tree.removing(at: ["nowhere"]).size == 150)
        #expect(tree.removing(at: ["a"]).children.map(\.name) == ["b"])
    }
}

import Foundation
import Testing

@testable import FindyCore

@Suite struct LocalFileSystemTests {
    /// Creates a scratch directory, runs `body`, then removes it.
    private func withScratchDirectory(_ body: (URL) async throws -> Void) async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FindyCoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try await body(directory)
    }

    @Test func listsFilesFoldersAndHiddenEntries() async throws {
        try await withScratchDirectory { directory in
            try Data("hello".utf8).write(to: directory.appendingPathComponent("notes.txt"))
            try Data().write(to: directory.appendingPathComponent(".hidden"))
            try FileManager.default.createDirectory(
                at: directory.appendingPathComponent("Folder"), withIntermediateDirectories: false)

            let items = try await LocalFileSystem().contents(of: directory)
            let byName = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0) })

            #expect(items.count == 3)
            #expect(byName["notes.txt"]?.size == 5)
            #expect(byName["notes.txt"]?.isFolder == false)
            #expect(byName["notes.txt"]?.modificationDate != nil)
            #expect(byName["Folder"]?.isFolder == true)
            #expect(byName["Folder"]?.size == nil)
            #expect(byName[".hidden"]?.isHidden == true)
        }
    }

    @Test func keepsUnicodeAndEmojiNames() async throws {
        try await withScratchDirectory { directory in
            let names = ["été à Conakry.txt", "📁 projets 🚀.md", "日本語.txt"]
            for name in names {
                try Data().write(to: directory.appendingPathComponent(name))
            }

            let items = try await LocalFileSystem().contents(of: directory)

            // The file system may store names decomposed (NFD); `==` on String compares canonically.
            #expect(Set(items.map(\.name)) == Set(names))
        }
    }

    @Test func reportsSymbolicLinksWithoutFollowingThem() async throws {
        try await withScratchDirectory { directory in
            let target = directory.appendingPathComponent("Target")
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
            try FileManager.default.createSymbolicLink(
                at: directory.appendingPathComponent("link"), withDestinationURL: target)

            let items = try await LocalFileSystem().contents(of: directory)
            let link = try #require(items.first { $0.name == "link" })

            #expect(link.isSymbolicLink)
            #expect(!link.isDirectory)
        }
    }

    @Test func throwsForMissingDirectory() async {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("FindyCoreTests-missing-\(UUID().uuidString)")

        await #expect(throws: (any Error).self) {
            try await LocalFileSystem().contents(of: missing)
        }
    }

    @Test func listsAtLeastTheBootVolume() async {
        let volumes = await LocalFileSystem().mountedVolumes()

        #expect(volumes.contains { $0.url.path == "/" })
    }
}

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
            #expect(link.linksToFolder)
            #expect(link.isFolder)
        }
    }

    @Test func linksToFilesAndBrokenLinksAreNotFolders() async throws {
        try await withScratchDirectory { directory in
            let file = directory.appendingPathComponent("file.txt")
            try Data().write(to: file)
            try FileManager.default.createSymbolicLink(
                at: directory.appendingPathComponent("to-file"), withDestinationURL: file)
            try FileManager.default.createSymbolicLink(
                at: directory.appendingPathComponent("broken"),
                withDestinationURL: directory.appendingPathComponent("nowhere"))

            let items = try await LocalFileSystem().contents(of: directory)

            #expect(items.first { $0.name == "to-file" }?.isFolder == false)
            #expect(items.first { $0.name == "broken" }?.isFolder == false)
        }
    }

    @Test func sumsFileSizesAtEveryDepthWithoutFollowingLinks() async throws {
        try await withScratchDirectory { directory in
            let outside = directory.appendingPathComponent("outside", isDirectory: true)
            let measured = directory.appendingPathComponent("measured", isDirectory: true)
            let nested = measured.appendingPathComponent("a/b", isDirectory: true)
            try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
            try Data(count: 1_000).write(to: outside.appendingPathComponent("big.bin"))
            try Data(count: 10).write(to: measured.appendingPathComponent("top.bin"))
            try Data(count: 20).write(to: nested.appendingPathComponent("deep.bin"))
            try Data(count: 5).write(to: nested.appendingPathComponent(".hidden"))
            try FileManager.default.createSymbolicLink(
                at: measured.appendingPathComponent("link"), withDestinationURL: outside)

            let size = try await LocalFileSystem().directorySize(of: measured)

            #expect(size == 35)
        }
    }

    @Test func sizingStopsWhenCancelled() async throws {
        try await withScratchDirectory { directory in
            for index in 0..<600 {
                try Data().write(to: directory.appendingPathComponent("file-\(index)"))
            }
            let task = Task { try await LocalFileSystem().directorySize(of: directory) }
            task.cancel()

            await #expect(throws: CancellationError.self) { try await task.value }
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

    @Test func findsCloudFoldersUnderTheHomeFolder() async throws {
        try await withScratchDirectory { home in
            let storage = home.appendingPathComponent("Library/CloudStorage", isDirectory: true)
            for name in ["GoogleDrive-me@example.com", "Dropbox", "OneDrive-Personal"] {
                try FileManager.default.createDirectory(
                    at: storage.appendingPathComponent(name), withIntermediateDirectories: true)
            }
            try FileManager.default.createDirectory(
                at: home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs"),
                withIntermediateDirectories: true)
            // Neither a stray file nor a hidden entry is a cloud service.
            try Data().write(to: storage.appendingPathComponent("notes.txt"))
            try Data().write(to: storage.appendingPathComponent(".DS_Store"))

            let locations = LocalFileSystem.cloudLocations(home: home)

            #expect(locations.map(\.name) == ["iCloud Drive", "Dropbox", "Google Drive", "OneDrive"])
            #expect(locations[2].url.lastPathComponent == "GoogleDrive-me@example.com")
        }
    }

    @Test func twoAccountsOfOneCloudServiceKeepTheirFullName() async throws {
        try await withScratchDirectory { home in
            let storage = home.appendingPathComponent("Library/CloudStorage", isDirectory: true)
            for name in ["GoogleDrive-a@example.com", "GoogleDrive-b@example.com"] {
                try FileManager.default.createDirectory(
                    at: storage.appendingPathComponent(name), withIntermediateDirectories: true)
            }

            let locations = LocalFileSystem.cloudLocations(home: home)

            #expect(locations.map(\.name) == ["GoogleDrive-a@example.com", "GoogleDrive-b@example.com"])
        }
    }

    @Test func aHomeWithoutCloudServicesHasNoCloudFolders() async throws {
        try await withScratchDirectory { home in
            #expect(LocalFileSystem.cloudLocations(home: home).isEmpty)
        }
    }

    @Test func onlyFoldersAndLinksToFoldersAreBrowsable() async throws {
        try await withScratchDirectory { directory in
            let folder = directory.appendingPathComponent("Folder 📁")
            let file = directory.appendingPathComponent("notes.txt")
            let link = directory.appendingPathComponent("link")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
            try Data().write(to: file)
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: folder)
            let fileSystem = LocalFileSystem()

            #expect(await fileSystem.isBrowsableFolder(folder))
            #expect(await fileSystem.isBrowsableFolder(link))
            #expect(await fileSystem.isBrowsableFolder(file) == false)
            #expect(await fileSystem.isBrowsableFolder(directory.appendingPathComponent("missing")) == false)
        }
    }
}

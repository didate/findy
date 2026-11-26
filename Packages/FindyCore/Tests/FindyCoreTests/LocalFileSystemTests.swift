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

    private func search(_ query: String, in directory: URL, includingHidden: Bool = false) async -> [FileItem] {
        var found: [FileItem] = []
        for await batch in LocalFileSystem().search(in: directory, matching: query, includingHidden: includingHidden) {
            found += batch
        }
        return found.sorted { $0.url.path < $1.url.path }
    }

    @Test func findsEntriesAtAnyDepthIgnoringCaseAndAccents() async throws {
        try await withScratchDirectory { directory in
            let deep = directory.appendingPathComponent("a/b/c", isDirectory: true)
            try FileManager.default.createDirectory(at: deep, withIntermediateDirectories: true)
            try Data("x".utf8).write(to: directory.appendingPathComponent("Rapport.pdf"))
            try Data().write(to: deep.appendingPathComponent("rapport été 🌞.txt"))
            try Data().write(to: deep.appendingPathComponent("other.txt"))
            try FileManager.default.createDirectory(
                at: directory.appendingPathComponent("a/RAPPORTS"), withIntermediateDirectories: false)

            let found = await search("rapport", in: directory)
            let accent = await search("ete", in: directory)

            #expect(found.map(\.name) == ["Rapport.pdf", "RAPPORTS", "rapport été 🌞.txt"])
            #expect(found.first?.size == 1)
            #expect(found[1].isFolder)
            #expect(accent.map(\.name) == ["rapport été 🌞.txt"])
            // Results are spelled like the folder searched, whatever the system calls it.
            #expect(found.allSatisfy { $0.url.path.hasPrefix(directory.path + "/") })
            #expect(found[2].url.path == deep.appendingPathComponent("rapport été 🌞.txt").path)
        }
    }

    @Test func searchLeavesOutHiddenEntriesPackagesAndLinkTargets() async throws {
        try await withScratchDirectory { directory in
            let hidden = directory.appendingPathComponent(".git", isDirectory: true)
            let package = directory.appendingPathComponent("Tool.app/Contents", isDirectory: true)
            let outside = directory.appendingPathComponent("outside", isDirectory: true)
            let inside = directory.appendingPathComponent("inside", isDirectory: true)
            for folder in [hidden, package, outside, inside] {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            }
            try Data().write(to: hidden.appendingPathComponent("needle-config"))
            try Data().write(to: package.appendingPathComponent("needle-binary"))
            try Data().write(to: outside.appendingPathComponent("needle.txt"))
            try Data().write(to: directory.appendingPathComponent(".needle-hidden"))
            // A link back to a folder: following it would list `needle.txt` twice, or forever.
            try FileManager.default.createSymbolicLink(
                at: inside.appendingPathComponent("needle-link"), withDestinationURL: outside)

            let visible = await search("needle", in: directory)
            let all = await search("needle", in: directory, includingHidden: true)

            #expect(visible.map(\.name) == ["needle-link", "needle.txt"])
            #expect(
                all.map(\.name)
                    == [".git/needle-config", ".needle-hidden", "needle-link", "needle.txt"].map {
                        ($0 as NSString).lastPathComponent
                    })
        }
    }

    @Test func aSearchThatFindsNothingOrHasNowhereToLookJustEnds() async throws {
        try await withScratchDirectory { directory in
            #expect(await search("nothing", in: directory).isEmpty)
            #expect(await search("x", in: directory.appendingPathComponent("missing")).isEmpty)
        }
    }

    @Test func readsTheDetailsOfAFileAFolderAndALink() async throws {
        try await withScratchDirectory { directory in
            let file = directory.appendingPathComponent("été 🌞.txt")
            let folder = directory.appendingPathComponent("Folder", isDirectory: true)
            let link = directory.appendingPathComponent("link")
            try Data("hello".utf8).write(to: file)
            try FileManager.default.setAttributes([.posixPermissions: 0o640], ofItemAtPath: file.path)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
            try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: "été 🌞.txt")
            let fileSystem = LocalFileSystem()

            let fileDetails = try await fileSystem.details(of: file)
            let folderDetails = try await fileSystem.details(of: folder)
            let linkDetails = try await fileSystem.details(of: link)

            #expect(fileDetails.name == "été 🌞.txt")
            #expect(fileDetails.size == 5)
            #expect((fileDetails.sizeOnDisk ?? 0) >= 5)
            #expect(fileDetails.permissions == 0o640)
            #expect(fileDetails.permissionString == "rw-r-----")
            #expect(fileDetails.owner == NSUserName())
            #expect(fileDetails.kind?.isEmpty == false)
            #expect(fileDetails.creationDate != nil)
            #expect(fileDetails.linkDestination == nil)
            #expect(folderDetails.isFolder)
            #expect(folderDetails.size == nil)
            // The link is described, not what it points to.
            #expect(linkDetails.linkDestination == "été 🌞.txt")
            #expect(!linkDetails.isFolder)
        }
    }

    @Test func detailsOfAMissingEntryAreAnError() async throws {
        try await withScratchDirectory { directory in
            await #expect(throws: (any Error).self) {
                try await LocalFileSystem().details(of: directory.appendingPathComponent("missing"))
            }
        }
    }

    @Test func listsAtLeastTheBootVolume() async {
        let volumes = await LocalFileSystem().mountedVolumes()

        #expect(volumes.contains { $0.url.path == "/" })
        // Nobody should be offered to eject the disk macOS runs from.
        #expect(volumes.first { $0.url.path == "/" }?.isEjectable == false)
    }

    /// Runs `hdiutil` and waits for it. Returns whether it succeeded.
    private func hdiutil(_ arguments: [String]) throws -> Bool {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/hdiutil")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    @Test func aDiskImageIsListedAsEjectableAndCanBeEjected() async throws {
        try await withScratchDirectory { directory in
            // A disk image stands for a USB drive: both are volumes the user must eject.
            let image = directory.appendingPathComponent("disk.dmg")
            let mountPoint = directory.appendingPathComponent("mounted", isDirectory: true)
            try FileManager.default.createDirectory(at: mountPoint, withIntermediateDirectories: false)
            try #require(
                try hdiutil(["create", "-quiet", "-size", "5m", "-fs", "HFS+", "-volname", "FindyTest", image.path]))
            try #require(
                try hdiutil(["attach", "-quiet", "-nobrowse", "-mountpoint", mountPoint.path, image.path]))
            let fileSystem = LocalFileSystem()
            let mounted = mountPoint.resolvingSymlinksInPath().path

            // `-nobrowse` hides the volume from the listing, so its flags are read directly.
            let values = try mountPoint.resourceValues(forKeys: [.volumeIsEjectableKey, .volumeIsInternalKey])
            #expect(values.volumeIsEjectable == true || values.volumeIsInternal == false)

            try await fileSystem.eject(mountPoint)

            let stillMounted = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil) ?? []
            #expect(!stillMounted.contains { $0.resolvingSymlinksInPath().path == mounted })
            // Ejecting what is no longer there reports an error instead of pretending.
            await #expect(throws: (any Error).self) {
                try await fileSystem.eject(mountPoint)
            }
        }
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

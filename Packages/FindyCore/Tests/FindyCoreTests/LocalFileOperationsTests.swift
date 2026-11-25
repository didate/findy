import Foundation
import Testing

@testable import FindyCore

@Suite struct LocalFileOperationsTests {
    private let operations = LocalFileOperations()
    private let fileManager = FileManager.default

    private func withScratchDirectory(_ body: (URL) async throws -> Void) async throws {
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("FindyCoreTests-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: directory) }
        try await body(directory)
    }

    private func write(_ text: String, to url: URL) throws {
        try Data(text.utf8).write(to: url)
    }

    private func read(_ url: URL) throws -> String {
        String(decoding: try Data(contentsOf: url), as: UTF8.self)
    }

    private func exists(_ url: URL) -> Bool {
        fileManager.fileExists(atPath: url.path)
    }

    private func names(in directory: URL) throws -> [String] {
        try fileManager.contentsOfDirectory(atPath: directory.path).sorted()
    }

    // MARK: New folder

    @Test func createsAFolderAndNumbersItWhenTheNameIsTaken() async throws {
        try await withScratchDirectory { directory in
            let first = try await operations.createFolder(in: directory, named: "untitled folder")
            let second = try await operations.createFolder(in: directory, named: "untitled folder")
            let third = try await operations.createFolder(in: directory, named: "untitled folder")

            #expect(first.lastPathComponent == "untitled folder")
            #expect(second.lastPathComponent == "untitled folder 2")
            #expect(third.lastPathComponent == "untitled folder 3")
            #expect(try names(in: directory).count == 3)
        }
    }

    @Test func createsAnEmptyFileAndNeverTouchesAnExistingOne() async throws {
        try await withScratchDirectory { directory in
            try write("precious", to: directory.appendingPathComponent("untitled.txt"))

            let first = try await operations.createFile(in: directory, named: "untitled.txt")
            let second = try await operations.createFile(in: directory, named: "untitled.txt")
            let emoji = try await operations.createFile(in: directory, named: "été 🚀.md")

            #expect(first.lastPathComponent == "untitled 2.txt")
            #expect(second.lastPathComponent == "untitled 3.txt")
            #expect(emoji.lastPathComponent == "été 🚀.md")
            #expect(try read(first).isEmpty)
            #expect(try read(directory.appendingPathComponent("untitled.txt")) == "precious")
        }
    }

    @Test func refusesToCreateAFileWhereItMayNotOrWithABadName() async throws {
        let forbidden = URL(fileURLWithPath: "/System/findy-test-\(UUID().uuidString)")
        await #expect(throws: (any Error).self) {
            try await operations.createFile(in: forbidden, named: "x.txt")
        }
        try await withScratchDirectory { directory in
            await #expect(throws: (any Error).self) {
                try await operations.createFile(in: directory, named: "a/b.txt")
            }
            let left = try names(in: directory)
            #expect(left.isEmpty)
        }
    }

    @Test func refusesToCreateAFolderWhereItMayNot() async throws {
        let directory = URL(fileURLWithPath: "/System/findy-test-\(UUID().uuidString)")
        await #expect(throws: (any Error).self) {
            try await operations.createFolder(in: directory, named: "x")
        }
    }

    // MARK: Rename

    @Test func renamesAnItem() async throws {
        try await withScratchDirectory { directory in
            let file = directory.appendingPathComponent("old.txt")
            try write("content", to: file)

            let renamed = try await operations.rename(file, to: "été 🚀.txt")

            #expect(renamed.lastPathComponent == "été 🚀.txt")
            #expect(try read(renamed) == "content")
            #expect(!exists(file))
        }
    }

    @Test func renameNeverOverwrites() async throws {
        try await withScratchDirectory { directory in
            let file = directory.appendingPathComponent("a.txt")
            let other = directory.appendingPathComponent("b.txt")
            try write("a", to: file)
            try write("b", to: other)

            await #expect(throws: FileOperationError.nameAlreadyExists(other)) {
                try await operations.rename(file, to: "b.txt")
            }
            #expect(try read(file) == "a")
            #expect(try read(other) == "b")
        }
    }

    @Test func renameCanChangeOnlyTheCase() async throws {
        try await withScratchDirectory { directory in
            let file = directory.appendingPathComponent("readme.txt")
            try write("x", to: file)

            let renamed = try await operations.rename(file, to: "README.txt")

            #expect(renamed.lastPathComponent == "README.txt")
            #expect(try names(in: directory) == ["README.txt"])
        }
    }

    @Test(arguments: ["", ".", "..", "a/b"])
    func rejectsInvalidNames(_ name: String) async throws {
        try await withScratchDirectory { directory in
            let file = directory.appendingPathComponent("a.txt")
            try write("a", to: file)

            await #expect(throws: FileOperationError.invalidName(name)) {
                try await operations.rename(file, to: name)
            }
            await #expect(throws: FileOperationError.invalidName(name)) {
                try await operations.createFolder(in: directory, named: name)
            }
            #expect(try names(in: directory) == ["a.txt"])
        }
    }

    @Test func renamesASymbolicLinkWithoutTouchingItsTarget() async throws {
        try await withScratchDirectory { directory in
            let target = directory.appendingPathComponent("target.txt")
            let link = directory.appendingPathComponent("link")
            try write("t", to: target)
            try fileManager.createSymbolicLink(at: link, withDestinationURL: target)

            let renamed = try await operations.rename(link, to: "shortcut")

            #expect(try fileManager.destinationOfSymbolicLink(atPath: renamed.path) == target.path)
            #expect(try read(target) == "t")
        }
    }

    // MARK: Trash

    @Test func trashesAnItemAndCanPutItBack() async throws {
        try await withScratchDirectory { directory in
            let file = directory.appendingPathComponent("doomed-\(UUID().uuidString).txt")
            try write("keep me", to: file)

            let trashed = try await operations.trash(file)
            // Whatever happens next, the test must not leave anything in the user's Trash.
            defer { try? fileManager.removeItem(at: trashed) }

            #expect(!exists(file))
            #expect(try read(trashed) == "keep me")

            try await operations.move(trashed, to: file)

            #expect(try read(file) == "keep me")
            #expect(!exists(trashed))
        }
    }

    @Test func trashingAMissingItemFails() async throws {
        try await withScratchDirectory { directory in
            await #expect(throws: (any Error).self) {
                try await operations.trash(directory.appendingPathComponent("ghost"))
            }
        }
    }

    // MARK: Move

    @Test func movesAFolderWithItsContent() async throws {
        try await withScratchDirectory { directory in
            let folder = directory.appendingPathComponent("Folder", isDirectory: true)
            let destination = directory.appendingPathComponent("Elsewhere/Folder")
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: false)
            try fileManager.createDirectory(
                at: destination.deletingLastPathComponent(), withIntermediateDirectories: false)
            try write("inside", to: folder.appendingPathComponent("file.txt"))

            try await operations.move(folder, to: destination)

            #expect(!exists(folder))
            #expect(try read(destination.appendingPathComponent("file.txt")) == "inside")
        }
    }

    @Test func moveNeverOverwrites() async throws {
        try await withScratchDirectory { directory in
            let source = directory.appendingPathComponent("a.txt")
            let destination = directory.appendingPathComponent("b.txt")
            try write("a", to: source)
            try write("b", to: destination)

            await #expect(throws: FileOperationError.nameAlreadyExists(destination)) {
                try await operations.move(source, to: destination)
            }
            #expect(try read(source) == "a")
            #expect(try read(destination) == "b")
        }
    }

    @Test func refusesToMoveOrCopyAFolderIntoItself() async throws {
        try await withScratchDirectory { directory in
            let folder = directory.appendingPathComponent("Folder", isDirectory: true)
            let inside = folder.appendingPathComponent("Sub/Folder")
            try fileManager.createDirectory(
                at: inside.deletingLastPathComponent(), withIntermediateDirectories: true)
            let expected = FileOperationError.destinationInsideSource(source: folder, destination: inside)

            await #expect(throws: expected) { try await operations.move(folder, to: inside) }
            await #expect(throws: expected) { try await operations.copy(folder, to: inside) }
            #expect(try names(in: folder) == ["Sub"])
        }
    }

    // MARK: Copy

    @Test func copiesAFolderTreeAndLeavesTheSourceAlone() async throws {
        try await withScratchDirectory { directory in
            let folder = directory.appendingPathComponent("Folder", isDirectory: true)
            let copy = directory.appendingPathComponent("Copy")
            try fileManager.createDirectory(
                at: folder.appendingPathComponent("deep"), withIntermediateDirectories: true)
            try write("1", to: folder.appendingPathComponent("top.txt"))
            try write("2", to: folder.appendingPathComponent("deep/📄 fichier.txt"))

            try await operations.copy(folder, to: copy)

            #expect(try read(copy.appendingPathComponent("top.txt")) == "1")
            #expect(try read(copy.appendingPathComponent("deep/📄 fichier.txt")) == "2")
            #expect(try read(folder.appendingPathComponent("top.txt")) == "1")
            // No temporary copy is left next to the result.
            #expect(try names(in: directory) == ["Copy", "Folder"])
        }
    }

    @Test func copyNeverOverwrites() async throws {
        try await withScratchDirectory { directory in
            let source = directory.appendingPathComponent("a.txt")
            let destination = directory.appendingPathComponent("b.txt")
            try write("a", to: source)
            try write("b", to: destination)

            await #expect(throws: FileOperationError.nameAlreadyExists(destination)) {
                try await operations.copy(source, to: destination)
            }
            #expect(try read(destination) == "b")
        }
    }

    @Test func copiesASymbolicLinkAsALink() async throws {
        try await withScratchDirectory { directory in
            let target = directory.appendingPathComponent("Target", isDirectory: true)
            let link = directory.appendingPathComponent("link")
            let copy = directory.appendingPathComponent("link copy")
            try fileManager.createDirectory(at: target, withIntermediateDirectories: false)
            try write("big", to: target.appendingPathComponent("payload"))
            try fileManager.createSymbolicLink(at: link, withDestinationURL: target)

            try await operations.copy(link, to: copy)

            #expect(try fileManager.destinationOfSymbolicLink(atPath: copy.path) == target.path)
        }
    }

    @Test func aFailedCopyLeavesNothingBehind() async throws {
        try await withScratchDirectory { directory in
            let destinationFolder = directory.appendingPathComponent("Destination", isDirectory: true)
            try fileManager.createDirectory(at: destinationFolder, withIntermediateDirectories: false)

            await #expect(throws: (any Error).self) {
                try await operations.copy(
                    directory.appendingPathComponent("ghost.txt"),
                    to: destinationFolder.appendingPathComponent("ghost.txt"))
            }
            #expect(try names(in: destinationFolder).isEmpty)
        }
    }

    @Test func copyStopsWhenAlreadyCancelled() async throws {
        try await withScratchDirectory { directory in
            let source = directory.appendingPathComponent("a.txt")
            let destination = directory.appendingPathComponent("b.txt")
            try write("a", to: source)

            let task = Task { [operations] in
                try await Task.sleep(for: .seconds(60))
                try await operations.copy(source, to: destination)
            }
            task.cancel()

            await #expect(throws: CancellationError.self) { try await task.value }
            #expect(!exists(destination))
        }
    }

    // MARK: Progress and cancellation

    /// Collects the byte counts a copy reports.
    private final class ByteLog: @unchecked Sendable {
        // Safe: `copyfile` calls back on one thread, and the test reads after the copy returned.
        var deltas: [Int64] = []
    }

    @Test func reportsEveryByteItWrites() async throws {
        try await withScratchDirectory { directory in
            let folder = directory.appendingPathComponent("Folder", isDirectory: true)
            try fileManager.createDirectory(
                at: folder.appendingPathComponent("deep"), withIntermediateDirectories: true)
            try Data(count: 3_000_000).write(to: folder.appendingPathComponent("a.bin"))
            try Data(count: 1_500_000).write(to: folder.appendingPathComponent("deep/b.bin"))
            try Data().write(to: folder.appendingPathComponent("empty"))
            let log = ByteLog()

            // Without clones, so that data is really written.
            try await LocalFileOperations(clonesWhenPossible: false)
                .copy(folder, to: directory.appendingPathComponent("Copy")) { log.deltas.append($0) }

            #expect(log.deltas.reduce(0, +) == 4_500_000)
            #expect(log.deltas.allSatisfy { $0 > 0 })
            #expect(try names(in: directory.appendingPathComponent("Copy")) == ["a.bin", "deep", "empty"])
        }
    }

    @Test func aCopyCancelledMidFileLeavesNothingBehind() async throws {
        try await withScratchDirectory { directory in
            let source = directory.appendingPathComponent("big.bin")
            let destination = directory.appendingPathComponent("copy.bin")
            try Data(count: 64_000_000).write(to: source)
            let log = ByteLog()

            let task = Task {
                try await LocalFileOperations(clonesWhenPossible: false).copy(source, to: destination) { delta in
                    log.deltas.append(delta)
                    // Cancel from inside the copy, as soon as the first bytes are written.
                    withUnsafeCurrentTask { $0?.cancel() }
                }
            }

            await #expect(throws: CancellationError.self) { try await task.value }
            // It stopped early, and neither the copy nor a partial file is left.
            #expect(log.deltas.reduce(0, +) < 64_000_000)
            #expect(try names(in: directory) == ["big.bin"])
        }
    }

    @Test func measuresWhatACopyWouldWrite() async throws {
        try await withScratchDirectory { directory in
            let folder = directory.appendingPathComponent("Folder", isDirectory: true)
            try fileManager.createDirectory(
                at: folder.appendingPathComponent("deep"), withIntermediateDirectories: true)
            try Data(count: 100).write(to: folder.appendingPathComponent("deep/a.bin"))
            let file = directory.appendingPathComponent("b.bin")
            try Data(count: 40).write(to: file)

            let total = await operations.totalSize(of: [folder, file, directory.appendingPathComponent("ghost")])

            #expect(total == 140)
        }
    }

    // MARK: Free names

    @Test func findsAFreeNameKeepingTheExtension() async throws {
        try await withScratchDirectory { directory in
            try write("", to: directory.appendingPathComponent("photo.jpg"))
            try write("", to: directory.appendingPathComponent("photo 2.jpg"))
            try fileManager.createDirectory(
                at: directory.appendingPathComponent("v1.2"), withIntermediateDirectories: false)

            let file = await operations.availableURL(for: "photo.jpg", in: directory, keepingExtension: true)
            let folder = await operations.availableURL(for: "v1.2", in: directory, keepingExtension: false)
            let free = await operations.availableURL(for: "new.txt", in: directory, keepingExtension: true)

            #expect(file.lastPathComponent == "photo 3.jpg")
            #expect(folder.lastPathComponent == "v1.2 2")
            #expect(free.lastPathComponent == "new.txt")
        }
    }

    @Test func aBrokenLinkStillOccupiesItsName() async throws {
        try await withScratchDirectory { directory in
            let link = directory.appendingPathComponent("dangling")
            try fileManager.createSymbolicLink(
                at: link, withDestinationURL: directory.appendingPathComponent("nowhere"))

            #expect(await operations.itemExists(at: link))
            let free = await operations.availableURL(for: "dangling", in: directory, keepingExtension: true)
            #expect(free.lastPathComponent == "dangling 2")
        }
    }
}

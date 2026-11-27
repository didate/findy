import FindyCore
import Foundation
import Testing

@testable import FindyUI

/// A file system whose only answer is a prepared disk usage report.
private struct FakeUsage: FileSystemProviding {
    struct Denied: LocalizedError {
        var errorDescription: String? { "You don’t have permission." }
    }

    var events: [DiskUsageEvent] = []
    var fails = false

    func diskUsage(of directory: URL) -> AsyncThrowingStream<DiskUsageEvent, any Error> {
        AsyncThrowingStream { continuation in
            for event in events { continuation.yield(event) }
            continuation.finish(throwing: fails ? Denied() : nil)
        }
    }

    func contents(of directory: URL) async throws -> [FileItem] { [] }
    func details(of url: URL) async throws -> FileDetails { FileDetails(url: url, name: url.lastPathComponent) }
    func search(in directory: URL, matching query: String, includingHidden: Bool) -> AsyncStream<[FileItem]> {
        AsyncStream { $0.finish() }
    }
    func items(labeled label: FileLabel) -> AsyncStream<[FileItem]> { AsyncStream { $0.finish() } }
    func directorySize(of directory: URL) async throws -> Int64 { 0 }
    func changes(in directory: URL) -> AsyncStream<Void> { AsyncStream { $0.finish() } }
    func changes(under root: URL) -> AsyncStream<Void> { AsyncStream { $0.finish() } }
    func mountedVolumes() async -> [Volume] { [] }
    func eject(_ volume: URL) async throws {}
    func cloudLocations() async -> [Volume] { [] }
    func gitInfo(for directory: URL) async -> GitInfo? { nil }
    func gitChanges(inRepositoryAt root: URL) async -> GitChanges? { nil }
    func availableSpace(at directory: URL) async -> Int64? { nil }
    func isBrowsableFolder(_ url: URL) async -> Bool { true }
}

@MainActor
@Suite struct DiskUsageModelTests {
    private let root = URL(fileURLWithPath: "/fake/Projects", isDirectory: true)

    /// Projects: app (700: build 600 [cache.bin 600], main.swift 100), video.mov 250,
    /// and 9 smaller files counted together for 50.
    private var events: [DiskUsageEvent] {
        let build = DiskUsageNode.folder(
            named: "build", children: [DiskUsageNode(name: "cache.bin", kind: .file, size: 600)])
        let app = DiskUsageNode.folder(
            named: "app", children: [DiskUsageNode(name: "main.swift", kind: .file, size: 100), build],
            unreadableCount: 1)
        return [
            .entry(DiskUsageNode(name: "", kind: .smallerFiles, size: 50, fileCount: 9)),
            .entry(DiskUsageNode(name: "video.mov", kind: .file, size: 250)),
            .progress(files: 10, bytes: 300),
            .entry(app),
            .progress(files: 12, bytes: 1_000),
            .unreadable(2),
        ]
    }

    /// What was sent to the Trash, and whether the next attempt is refused.
    private final class TrashLog {
        var trashed: [String] = []
        var refusal: String?
    }

    private func makeModel(_ fileSystem: FakeUsage, log: TrashLog = TrashLog()) -> DiskUsageModel {
        DiskUsageModel(root: root, fileSystem: fileSystem) { url in
            if let refusal = log.refusal { return refusal }
            log.trashed.append(url.path)
            return nil
        }
    }

    @Test func listsWhatAFolderHoldsLargestFirstAndAddsItUp() async {
        let model = makeModel(FakeUsage(events: events))

        await model.scan()

        #expect(!model.isScanning)
        #expect(model.scannedFiles == 12)
        #expect(model.shown.children.map(\.name) == ["app", "video.mov", ""])
        #expect(model.shown.size == 1_000)
        #expect(model.shown.fileCount == 12)
        // Two folders unreadable at the top, one more inside "app".
        #expect(model.shown.unreadableCount == 3)
        #expect(model.share(of: model.shown.children[0]) == 0.7)
        #expect(model.breadcrumb == ["Projects"])
    }

    @Test func goesDownIntoAFolderAndBackWithoutScanningAgain() async throws {
        let model = makeModel(FakeUsage(events: events))
        await model.scan()

        model.open(try #require(model.shown.children.first))
        model.open(try #require(model.shown.children.first))

        #expect(model.breadcrumb == ["Projects", "app", "build"])
        #expect(model.shown.children.map(\.name) == ["cache.bin"])
        #expect(model.shownURL.path == "/fake/Projects/app/build")
        #expect(model.url(of: model.shown.children[0])?.path == "/fake/Projects/app/build/cache.bin")

        model.go(toLevel: 0)
        #expect(model.breadcrumb == ["Projects"])
        #expect(!model.canGoUp)

        model.open(try #require(model.shown.children.first))
        model.goUp()
        #expect(model.shown.size == 1_000)
    }

    @Test func aFileOrTheSmallerFilesCannotBeOpenedAndTheLatterHaveNoLocation() async throws {
        let model = makeModel(FakeUsage(events: events))
        await model.scan()
        let video = try #require(model.shown.children.first { $0.name == "video.mov" })
        let rest = try #require(model.shown.children.first { $0.kind == .smallerFiles })

        model.open(video)
        model.open(rest)

        #expect(!model.canGoUp)
        #expect(model.url(of: rest) == nil)
        #expect(model.url(of: video)?.path == "/fake/Projects/video.mov")
    }

    @Test func trashingAnEntryTakesItOutOfEveryTotalAboveIt() async throws {
        let log = TrashLog()
        let model = makeModel(FakeUsage(events: events), log: log)
        await model.scan()
        model.open(try #require(model.shown.children.first))

        await model.moveToTrash(try #require(model.shown.children.first { $0.name == "build" }))

        #expect(log.trashed == ["/fake/Projects/app/build"])
        #expect(model.hasTrashed)
        #expect(model.shown.children.map(\.name) == ["main.swift"])
        #expect(model.shown.size == 100)
        model.goUp()
        #expect(model.shown.size == 400)
        #expect(model.shown.unreadableCount == 3)
    }

    @Test func aRefusedTrashChangesNothingAndSaysWhy() async throws {
        let log = TrashLog()
        log.refusal = "The item is locked."
        let model = makeModel(FakeUsage(events: events), log: log)
        await model.scan()

        await model.moveToTrash(try #require(model.shown.children.first))
        await model.moveToTrash(try #require(model.shown.children.first { $0.kind == .smallerFiles }))

        #expect(model.alertMessage == "The item is locked.")
        #expect(!model.hasTrashed)
        #expect(model.shown.size == 1_000)
        #expect(log.trashed.isEmpty)
    }

    @Test func aFolderThatCannotBeReadSaysSo() async {
        let model = makeModel(FakeUsage(fails: true))

        await model.scan()

        #expect(model.errorMessage == "You don’t have permission.")
        #expect(model.shown.children.isEmpty)
        #expect(!model.isScanning)
    }

    @Test func measuringAgainStartsFromScratchAndLeavesAFolderThatIsGone() async throws {
        let model = makeModel(FakeUsage(events: events))
        await model.scan()
        model.open(try #require(model.shown.children.first))
        await model.moveToTrash(try #require(model.shown.children.first { $0.name == "build" }))

        await model.scan()

        // Same report again: "app" is still there, and so is what was taken out of the figures.
        #expect(model.breadcrumb == ["Projects", "app"])
        #expect(model.shown.size == 700)
    }
}

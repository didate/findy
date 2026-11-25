import FindyCore
import Foundation
import Testing

@testable import FindyUI

/// In-memory file system: a fixed listing per directory path.
private struct FakeFileSystem: FileSystemProviding {
    struct Unreadable: Error {}

    var listings: [String: [FileItem]] = [:]
    var sizes: [String: Int64] = [:]

    func contents(of directory: URL) async throws -> [FileItem] {
        guard let items = listings[directory.path] else { throw Unreadable() }
        return items
    }

    func directorySize(of directory: URL) async throws -> Int64 {
        guard let size = sizes[directory.path] else { throw Unreadable() }
        return size
    }

    func changes(in directory: URL) -> AsyncStream<Void> {
        AsyncStream { $0.finish() }
    }

    func mountedVolumes() async -> [Volume] { [] }
}

@MainActor
@Suite struct BrowserModelTests {
    private let root = URL(fileURLWithPath: "/fake")
    private let sub = URL(fileURLWithPath: "/fake/Sub")

    private func makeModel() -> BrowserModel {
        let fileSystem = FakeFileSystem(listings: [
            "/fake": [
                FileItem(url: URL(fileURLWithPath: "/fake/b.txt"), size: 2),
                FileItem(url: URL(fileURLWithPath: "/fake/.secret"), isHidden: true, size: 1),
                FileItem(url: sub, isDirectory: true),
                FileItem(url: URL(fileURLWithPath: "/fake/a.txt"), size: 9),
            ],
            "/fake/Sub": [],
        ])
        return BrowserModel(location: root, fileSystem: fileSystem)
    }

    @Test func listsSortedItemsWithoutHiddenFiles() async {
        let model = makeModel()

        model.reload()
        await model.loadTask?.value

        #expect(model.items.map(\.name) == ["Sub", "a.txt", "b.txt"])
        #expect(model.errorMessage == nil)
        #expect(!model.isLoading)
    }

    @Test func showsHiddenFilesOnDemand() async {
        let model = makeModel()
        model.reload()
        await model.loadTask?.value

        model.showsHiddenFiles = true

        #expect(model.items.map(\.name) == ["Sub", ".secret", "a.txt", "b.txt"])
    }

    @Test func resortsWhenTheSortChanges() async {
        let model = makeModel()
        model.reload()
        await model.loadTask?.value

        model.sort = FileSort(key: .size, ascending: false)

        #expect(model.items.map(\.name) == ["Sub", "a.txt", "b.txt"])
        model.sort.ascending = true
        #expect(model.items.map(\.name) == ["Sub", "b.txt", "a.txt"])
    }

    @Test func tracksBackAndForwardHistory() async {
        let model = makeModel()
        #expect(!model.canGoBack)

        model.navigate(to: sub)
        await model.loadTask?.value
        #expect(model.location == sub)
        #expect(model.items.isEmpty)
        #expect(model.canGoBack)
        #expect(!model.canGoForward)

        model.goBack()
        await model.loadTask?.value
        #expect(model.location == root)
        #expect(model.items.count == 3)
        #expect(model.canGoForward)

        model.goForward()
        #expect(model.location == sub)
        #expect(!model.canGoForward)
    }

    @Test func navigatingSomewhereNewClearsForwardHistory() async {
        let model = makeModel()
        model.navigate(to: sub)
        model.goBack()
        #expect(model.canGoForward)

        model.navigate(to: sub)

        #expect(!model.canGoForward)
    }

    @Test func goesUpToTheEnclosingFolder() async {
        let model = makeModel()
        model.navigate(to: sub)

        model.goUp()
        await model.loadTask?.value

        #expect(model.location == root)
        #expect(model.items.count == 3)
    }

    @Test func navigatesToATypedPath() async {
        let model = makeModel()

        model.navigate(toPath: "  /fake/Sub/  ")
        #expect(model.location == sub)

        model.navigate(toPath: "relative/path")
        #expect(model.location == sub)

        model.navigate(toPath: "~")
        #expect(model.location == FileManager.default.homeDirectoryForCurrentUser.canonicalLocation)
    }

    @Test func splitsTheLocationIntoCrumbs() {
        let model = makeModel()
        model.navigate(to: sub)

        #expect(model.crumbs.map(\.name) == ["/", "fake", "Sub"])
        #expect(model.crumbs.map(\.url.path) == ["/", "/fake", "/fake/Sub"])
    }

    @Test func entersFoldersAndHandsFilesToTheSystem() async {
        var opened: [URL] = []
        let fileSystem = FakeFileSystem(listings: ["/fake": [], "/fake/Sub": []])
        let model = BrowserModel(location: root, fileSystem: fileSystem) { opened += $0 }
        let file = URL(fileURLWithPath: "/fake/a.txt")

        model.open(FileItem(url: file))
        #expect(opened == [file])
        #expect(model.location == root)

        model.open(FileItem(url: sub, isDirectory: true))
        #expect(model.location == sub)
        #expect(opened == [file])
    }

    @Test func filtersByNameIgnoringCaseAndAccents() async {
        let fileSystem = FakeFileSystem(listings: [
            "/fake": ["Résumé.pdf", "resume-old.txt", "photo.jpg"].map {
                FileItem(url: URL(fileURLWithPath: "/fake/\($0)"))
            }
        ])
        let model = BrowserModel(location: root, fileSystem: fileSystem)
        model.reload()
        await model.loadTask?.value

        model.appendToFilter("RESU")
        #expect(model.items.map(\.name) == ["resume-old.txt", "Résumé.pdf"])

        model.appendToFilter("x")
        #expect(model.items.isEmpty)

        #expect(model.deleteFilterBackward())
        #expect(model.items.count == 2)

        #expect(model.clearFilter())
        #expect(model.items.count == 3)
        #expect(!model.clearFilter())
        #expect(!model.deleteFilterBackward())
    }

    @Test func filterAndSelectionResetWhenNavigating() async {
        let model = makeModel()
        model.reload()
        await model.loadTask?.value
        model.filterText = "a"
        model.selection = [URL(fileURLWithPath: "/fake/a.txt")]

        model.navigate(to: sub)

        #expect(model.filterText.isEmpty)
        #expect(model.selection.isEmpty)
    }

    @Test func selectionDropsEntriesTheFilterHides() async {
        let model = makeModel()
        model.reload()
        await model.loadTask?.value
        let a = URL(fileURLWithPath: "/fake/a.txt")
        let b = URL(fileURLWithPath: "/fake/b.txt")
        model.selection = [a, b]

        model.filterText = "a."

        #expect(model.selection == [a])
        #expect(model.selectedItems.map(\.name) == ["a.txt"])
    }

    @Test func followsChangesOnDisk() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FindyUITests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = BrowserModel(location: directory)
        model.reload()
        await model.loadTask?.value
        #expect(model.items.isEmpty)

        let following = Task { await model.followChanges() }
        defer { following.cancel() }
        try await Task.sleep(for: .milliseconds(300))
        try Data().write(to: directory.appendingPathComponent("appeared.txt"))

        let deadline = ContinuousClock.now + .seconds(5)
        while model.items.isEmpty, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(model.items.map(\.name) == ["appeared.txt"])
    }

    private func makeSizedModel(calculatesFolderSizes: Bool) -> BrowserModel {
        let fileSystem = FakeFileSystem(
            listings: [
                "/fake": [
                    FileItem(url: URL(fileURLWithPath: "/fake/Small"), isDirectory: true),
                    FileItem(url: URL(fileURLWithPath: "/fake/Big"), isDirectory: true),
                    FileItem(url: URL(fileURLWithPath: "/fake/Locked"), isDirectory: true),
                    FileItem(
                        url: URL(fileURLWithPath: "/fake/Link"), isSymbolicLink: true, linksToFolder: true),
                ]
            ],
            sizes: ["/fake/Small": 10, "/fake/Big": 5_000, "/fake/Link": 99])
        return BrowserModel(location: root, fileSystem: fileSystem, calculatesFolderSizes: calculatesFolderSizes)
    }

    @Test func computesFolderSizesInTheBackground() async {
        let model = makeSizedModel(calculatesFolderSizes: true)

        model.reload()
        await model.loadTask?.value
        await model.sizeTask?.value

        let sizes = Dictionary(uniqueKeysWithValues: model.items.map { ($0.name, $0.size) })
        #expect(sizes["Small"] == 10)
        #expect(sizes["Big"] == 5_000)
        // A folder that cannot be measured and a link keep an unknown size.
        #expect(sizes["Locked"] == .some(nil))
        #expect(sizes["Link"] == .some(nil))

        model.sort = FileSort(key: .size, ascending: false)
        #expect(model.items.map(\.name) == ["Big", "Small", "Link", "Locked"])
    }

    @Test func leavesFolderSizesUnknownWhenTurnedOff() async {
        let model = makeSizedModel(calculatesFolderSizes: false)

        model.reload()
        await model.loadTask?.value

        #expect(model.sizeTask == nil)
        #expect(model.items.allSatisfy { $0.size == nil })

        model.calculatesFolderSizes = true
        await model.sizeTask?.value
        #expect(model.items.first { $0.name == "Big" }?.size == 5_000)

        model.calculatesFolderSizes = false
        #expect(model.items.allSatisfy { $0.size == nil })
    }

    @Test func remembersSortAndHiddenFilesPerFolder() async throws {
        let store = try SQLiteFolderSettingsStore()
        let fileSystem = FakeFileSystem(listings: ["/fake": [], "/fake/Sub": []])
        let model = BrowserModel(location: root, fileSystem: fileSystem, settingsStore: store)
        model.reload()
        await model.loadTask?.value

        model.sort = FileSort(key: .size, ascending: false)
        model.showsHiddenFiles = true
        await model.settingsTask?.value

        // A folder the user never customized starts from the defaults.
        model.navigate(to: sub)
        await model.loadTask?.value
        #expect(model.sort == FileSort())
        #expect(!model.showsHiddenFiles)
        #expect(try await store.settings(for: sub) == nil)

        model.goBack()
        await model.loadTask?.value
        #expect(model.sort == FileSort(key: .size, ascending: false))
        #expect(model.showsHiddenFiles)

        // Another pane, or the next launch, finds the same settings.
        let other = BrowserModel(location: root, fileSystem: fileSystem, settingsStore: store)
        other.reload()
        await other.loadTask?.value
        #expect(other.sort == FileSort(key: .size, ascending: false))
        #expect(other.showsHiddenFiles)
    }

    @Test func withoutAStoreSettingsFollowTheUserAround() async {
        let model = makeModel()
        model.sort = FileSort(key: .size)

        model.navigate(to: sub)
        await model.loadTask?.value

        #expect(model.sort == FileSort(key: .size))
    }

    @Test func opensTheTerminalInTheSelectedFolderOrTheOneShown() async {
        var opened: [URL] = []
        let fileSystem = FakeFileSystem(listings: [
            "/fake": [
                FileItem(url: sub, isDirectory: true),
                FileItem(url: URL(fileURLWithPath: "/fake/a.txt")),
                FileItem(url: URL(fileURLWithPath: "/fake/Other"), isDirectory: true),
            ]
        ])
        let model = BrowserModel(
            location: root, fileSystem: fileSystem, openFiles: { _ in }, openInTerminal: { opened.append($0) })
        model.reload()
        await model.loadTask?.value

        // Nothing selected: the folder shown.
        model.openTerminal()
        await model.terminalTask?.value
        // One folder selected: that folder.
        model.selection = [sub]
        model.openTerminal()
        await model.terminalTask?.value
        // A file, or several entries: the folder shown again.
        model.selection = [URL(fileURLWithPath: "/fake/a.txt")]
        #expect(model.terminalFolder == root)
        model.selection = [sub, URL(fileURLWithPath: "/fake/Other")]
        #expect(model.terminalFolder == root)

        #expect(opened == [root, sub])
        #expect(model.alertMessage == nil)
    }

    @Test func tellsTheUserWhenTheTerminalCannotBeOpened() async {
        struct NoTerminal: LocalizedError {
            var errorDescription: String? { "No terminal here." }
        }
        let fileSystem = FakeFileSystem(listings: ["/fake": []])
        let model = BrowserModel(
            location: root, fileSystem: fileSystem, openFiles: { _ in },
            openInTerminal: { _ in throw NoTerminal() })

        model.openTerminal()
        await model.terminalTask?.value

        #expect(model.alertMessage == "No terminal here.")
    }

    @Test func reportsUnreadableFolders() async {
        let model = makeModel()

        model.navigate(to: URL(fileURLWithPath: "/nowhere"))
        await model.loadTask?.value

        #expect(model.items.isEmpty)
        #expect(model.errorMessage != nil)
        #expect(!model.isLoading)
    }
}

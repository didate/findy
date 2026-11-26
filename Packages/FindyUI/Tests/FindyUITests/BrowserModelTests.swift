import FindyCore
import Foundation
import Testing

@testable import FindyUI

/// In-memory file system: a fixed listing per directory path.
private struct FakeFileSystem: FileSystemProviding {
    struct Unreadable: Error {}

    var listings: [String: [FileItem]] = [:]
    var sizes: [String: Int64] = [:]
    var git: [String: GitInfo] = [:]
    /// What a search finds, by query, delivered in two batches.
    var found: [String: [FileItem]] = [:]

    func search(in directory: URL, matching query: String, includingHidden: Bool) -> AsyncStream<[FileItem]> {
        let results = (found[query] ?? []).filter { includingHidden || !$0.isHidden }
        return AsyncStream { continuation in
            let half = results.count / 2
            if half > 0 { continuation.yield(Array(results[..<half])) }
            if results.count > half { continuation.yield(Array(results[half...])) }
            continuation.finish()
        }
    }

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

    func changes(under root: URL) -> AsyncStream<Void> { AsyncStream { $0.finish() } }

    func mountedVolumes() async -> [Volume] { [] }

    func cloudLocations() async -> [Volume] { [] }

    func eject(_ volume: URL) async throws {}

    func gitInfo(for directory: URL) async -> GitInfo? { git[directory.path] }

    func gitChanges(inRepositoryAt root: URL) async -> GitChanges? {
        git[root.path] == nil
            ? nil
            : GitChanges(changedFiles: 3, ahead: 1, behind: 0, states: ["Sub/deep.txt": .modified, "a.txt": .added])
    }

    func availableSpace(at directory: URL) async -> Int64? { 1_000 }

    func isBrowsableFolder(_ url: URL) async -> Bool { listings[url.path] != nil }
}

@MainActor
@Suite struct BrowserModelTests {
    private let root = URL(fileURLWithPath: "/fake")
    private let sub = URL(fileURLWithPath: "/fake/Sub")

    private func makeModel() -> BrowserModel {
        BrowserModel(location: root, fileSystem: makeFileSystem())
    }

    private func makeFileSystem() -> FakeFileSystem {
        FakeFileSystem(listings: [
            "/fake": [
                FileItem(url: URL(fileURLWithPath: "/fake/b.txt"), size: 2),
                FileItem(url: URL(fileURLWithPath: "/fake/.secret"), isHidden: true, size: 1),
                FileItem(url: sub, isDirectory: true),
                FileItem(url: URL(fileURLWithPath: "/fake/a.txt"), size: 9),
            ],
            "/fake/Sub": [],
        ])
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
        model.groupsByDate = true
        await model.settingsTask?.value

        // A folder the user never customized starts from the defaults.
        model.navigate(to: sub)
        await model.loadTask?.value
        #expect(model.sort == FileSort())
        #expect(!model.showsHiddenFiles)
        #expect(!model.groupsByDate)
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
        #expect(other.groupsByDate)
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

    @Test func reportsTheGitBranchAndFreeSpaceOfTheFolderShown() async {
        let info = GitInfo(
            head: "main", isDetached: false, root: root, gitDirectory: root.appendingPathComponent(".git"))
        let fileSystem = FakeFileSystem(listings: ["/fake": [], "/fake/Sub": []], git: ["/fake": info])
        let model = BrowserModel(location: root, fileSystem: fileSystem)

        model.reload()
        await model.statusTask?.value
        #expect(model.gitInfo == info)
        #expect(model.availableSpace == 1_000)
        #expect(model.gitChanges?.changedFiles == 3)
        #expect(model.gitChanges?.ahead == 1)
        #expect(model.gitState(of: FileItem(url: URL(fileURLWithPath: "/fake/a.txt"))) == .added)
        // The same entry, spelled the way the system sometimes returns it.
        #expect(model.gitState(of: FileItem(url: URL(fileURLWithPath: "/private/fake/a.txt"))) == .added)
        #expect(model.gitState(of: FileItem(url: sub, isDirectory: true)) == .containsChanges)
        #expect(model.gitState(of: FileItem(url: URL(fileURLWithPath: "/fake/b.txt"))) == nil)

        // Leaving the repository drops the branch.
        model.navigate(to: sub)
        await model.statusTask?.value
        #expect(model.gitInfo == nil)
        #expect(model.gitChanges == nil)
        #expect(model.gitState(of: FileItem(url: URL(fileURLWithPath: "/fake/a.txt"))) == nil)
    }

    @Test func addsUpTheSizeOfTheSelection() async {
        let model = makeModel()
        model.reload()
        await model.loadTask?.value
        #expect(model.selectedSize == nil)

        model.selection = [URL(fileURLWithPath: "/fake/a.txt"), URL(fileURLWithPath: "/fake/b.txt")]

        #expect(model.selectedSize == 11)
    }

    @Test func copiesThePathOfTheSelectionOrOfTheFolder() async {
        let model = makeModel()
        model.reload()
        await model.loadTask?.value
        #expect(model.pathsForClipboard == "/fake")

        model.selection = [URL(fileURLWithPath: "/fake/b.txt"), URL(fileURLWithPath: "/fake/a.txt")]

        // In the order shown, whatever the order of selection.
        #expect(model.pathsForClipboard == "/fake/a.txt\n/fake/b.txt")
    }

    @Test func opensTheSelectionOrTheFolderInTheEditor() async {
        var opened: [[URL]] = []
        let fileSystem = FakeFileSystem(listings: [
            "/fake": [
                FileItem(url: URL(fileURLWithPath: "/fake/a.txt"), size: 9),
                FileItem(url: sub, isDirectory: true),
            ]
        ])
        let model = BrowserModel(location: root, fileSystem: fileSystem, openInEditor: { opened.append($0) })
        model.reload()
        await model.loadTask?.value

        model.openEditor()
        await model.terminalTask?.value
        model.selection = [URL(fileURLWithPath: "/fake/a.txt")]
        model.openEditor()
        await model.terminalTask?.value

        #expect(opened.map { $0.map(\.path) } == [["/fake"], ["/fake/a.txt"]])
    }

    @Test func tellsTheUserWhenNoEditorCanBeOpened() async {
        struct NoEditor: LocalizedError {
            var errorDescription: String? { "no editor" }
        }
        let fileSystem = FakeFileSystem(listings: ["/fake": []])
        let model = BrowserModel(location: root, fileSystem: fileSystem, openInEditor: { _ in throw NoEditor() })

        model.openEditor()
        await model.terminalTask?.value

        #expect(model.alertMessage?.contains("no editor") == true)
    }

    @Test func prefersTheChosenEditorWhenItIsInstalled() {
        let code = EditorApp(name: "Code", bundleIdentifier: "code")
        let zed = EditorApp(name: "Zed", bundleIdentifier: "zed")

        #expect(EditorLauncher.preferred(among: [code, zed], chosen: "zed") == zed)
        #expect(EditorLauncher.preferred(among: [code, zed], chosen: "gone") == code)
        #expect(EditorLauncher.preferred(among: [code, zed], chosen: nil) == code)
        #expect(EditorLauncher.preferred(among: [], chosen: "zed") == nil)
    }

    @Test func mixesFoldersWithFilesWhenFoldersFirstIsOff() async {
        let model = makeModel()
        model.reload()
        await model.loadTask?.value
        #expect(model.items.map(\.name) == ["Sub", "a.txt", "b.txt"])

        model.sort.foldersFirst = false

        #expect(model.items.map(\.name) == ["a.txt", "b.txt", "Sub"])
    }

    @Test func resortsABigFolderWithoutHoldingTheMainThread() async {
        let count = 10_000
        let listing = (0..<count).map { FileItem(url: URL(fileURLWithPath: "/big/file \($0).txt"), size: Int64($0)) }
        let model = BrowserModel(
            location: URL(fileURLWithPath: "/big"), fileSystem: FakeFileSystem(listings: ["/big": listing]))
        model.reload()
        await model.loadTask?.value
        #expect(model.items.first?.name == "file 0.txt")

        let clock = ContinuousClock()
        let blocked = clock.measure { model.sort.ascending = false }

        // The old order stays on screen while the new one is computed elsewhere.
        #expect(model.items.first?.name == "file 0.txt")
        #expect(blocked < .milliseconds(16))
        await model.arrangeTask?.value
        #expect(model.items.first?.name == "file 9999.txt")
        #expect(model.items.count == count)
    }

    @Test func aNavigationCancelsTheSortOfTheFolderLeft() async {
        let listing = (0..<5_000).map { FileItem(url: URL(fileURLWithPath: "/big/file \($0).txt")) }
        let model = BrowserModel(
            location: URL(fileURLWithPath: "/big"),
            fileSystem: FakeFileSystem(listings: ["/big": listing, "/fake": []]))
        model.reload()
        await model.loadTask?.value

        model.sort.ascending = false
        model.navigate(to: root)
        await model.loadTask?.value
        await model.arrangeTask?.value

        #expect(model.items.isEmpty)
        #expect(model.location == root)
    }

    @Test func groupsByDateWithTheSortAppliedInsideEachSection() async {
        let now = Date()
        func item(_ name: String, daysAgo: Double, isDirectory: Bool = false) -> FileItem {
            FileItem(
                url: URL(fileURLWithPath: "/dated/\(name)"), isDirectory: isDirectory,
                modificationDate: now.addingTimeInterval(-daysAgo * 86_400))
        }
        let listing = [
            item("old b.txt", daysAgo: 400), item("new b.txt", daysAgo: 0), item("old a.txt", daysAgo: 400),
            item("new folder", daysAgo: 0, isDirectory: true), item("new a.txt", daysAgo: 0),
        ]
        let model = BrowserModel(
            location: URL(fileURLWithPath: "/dated"), fileSystem: FakeFileSystem(listings: ["/dated": listing]))
        model.reload()
        await model.loadTask?.value

        model.groupsByDate = true

        #expect(model.items.map(\.name) == ["new folder", "new a.txt", "new b.txt", "old a.txt", "old b.txt"])
        #expect(model.dateGroup(of: listing[1]) == .today)

        model.sort.ascending = false
        #expect(model.items.map(\.name) == ["new folder", "new b.txt", "new a.txt", "old b.txt", "old a.txt"])

        model.groupsByDate = false
        #expect(model.items.map(\.name) == ["new folder", "old b.txt", "old a.txt", "new b.txt", "new a.txt"])
    }

    @Test func opensTheSelectedFilesWithTheChosenApplication() async {
        var opened: [([String], String)] = []
        let model = BrowserModel(
            location: root, fileSystem: makeFileSystem(),
            openWithApplication: { urls, application in opened.append((urls.map(\.path), application.path)) })
        model.reload()
        await model.loadTask?.value
        let application = URL(fileURLWithPath: "/Applications/TextEdit.app")

        // Nothing selected: nothing to open.
        model.openSelection(withApplicationAt: application)
        model.selection = [URL(fileURLWithPath: "/fake/b.txt"), URL(fileURLWithPath: "/fake/a.txt")]
        model.openSelection(withApplicationAt: application)
        await model.terminalTask?.value

        #expect(opened.count == 1)
        #expect(opened.first?.0 == ["/fake/a.txt", "/fake/b.txt"])
        #expect(opened.first?.1 == "/Applications/TextEdit.app")
    }

    @Test func showsTheSelectionOrTheFolderInFinder() async {
        var revealed: [[String]] = []
        let model = BrowserModel(
            location: root, fileSystem: makeFileSystem(), revealInFinder: { revealed.append($0.map(\.path)) })
        model.reload()
        await model.loadTask?.value

        model.showInFinder()
        model.selection = [URL(fileURLWithPath: "/fake/a.txt")]
        model.showInFinder()

        #expect(revealed == [["/fake"], ["/fake/a.txt"]])
    }

    private func searchableFileSystem() -> FakeFileSystem {
        var fileSystem = makeFileSystem()
        fileSystem.found["report"] = [
            FileItem(url: URL(fileURLWithPath: "/fake/Sub/deep/report b.txt"), size: 1),
            FileItem(url: URL(fileURLWithPath: "/fake/report a.txt"), size: 2),
            FileItem(url: URL(fileURLWithPath: "/fake/Sub/.report hidden"), isHidden: true),
            FileItem(url: URL(fileURLWithPath: "/fake/Sub/reports"), isDirectory: true),
        ]
        return fileSystem
    }

    @Test func searchShowsSortedResultsFromEveryDepthThenTheFolderAgain() async {
        let model = BrowserModel(location: root, fileSystem: searchableFileSystem())
        model.reload()
        await model.loadTask?.value

        model.beginSearch()
        model.searchText = "report"
        await model.searchTask?.value

        #expect(model.isSearching)
        #expect(model.showsSearchResults)
        #expect(!model.isSearchRunning)
        #expect(model.items.map(\.name) == ["reports", "report a.txt", "report b.txt"])

        // The status bar says where a result found deeper is.
        model.selection = [URL(fileURLWithPath: "/fake/Sub/deep/report b.txt")]
        #expect(model.selectedResultFolder == "Sub/deep")
        model.selection = [URL(fileURLWithPath: "/fake/report a.txt")]
        #expect(model.selectedResultFolder == nil)

        model.endSearch()
        #expect(!model.showsSearchResults)
        #expect(model.items.map(\.name) == ["Sub", "a.txt", "b.txt"])
    }

    @Test func searchFollowsTheHiddenFilesSettingAndReportsNothingFound() async {
        let model = BrowserModel(location: root, fileSystem: searchableFileSystem())
        model.reload()
        await model.loadTask?.value
        model.searchText = "report"
        await model.searchTask?.value

        model.showsHiddenFiles = true
        await model.searchTask?.value
        #expect(model.items.map(\.name).contains(".report hidden"))

        model.searchText = "nothing like it"
        await model.searchTask?.value
        #expect(model.items.isEmpty)
        #expect(model.showsSearchResults)
        #expect(!model.isSearchRunning)
    }

    @Test func navigatingAwayEndsTheSearch() async {
        let model = BrowserModel(location: root, fileSystem: searchableFileSystem())
        model.reload()
        await model.loadTask?.value
        model.beginSearch()
        model.searchText = "report"
        await model.searchTask?.value

        model.navigate(to: sub)
        await model.loadTask?.value

        #expect(!model.isSearching)
        #expect(model.searchText.isEmpty)
        #expect(!model.showsSearchResults)
        #expect(model.items.isEmpty)
    }

    @Test func aChangeOnDiskRepeatsTheSearchWithoutBlankingTheList() async {
        let model = BrowserModel(location: root, fileSystem: searchableFileSystem())
        model.reload()
        await model.loadTask?.value
        model.searchText = "report"
        await model.searchTask?.value

        model.refresh()
        await model.loadTask?.value
        // The results stay on screen while the disk is searched again.
        #expect(model.items.count == 3)
        await model.searchTask?.value

        #expect(model.items.map(\.name) == ["reports", "report a.txt", "report b.txt"])
    }

    @Test func gitStatesReachResultsFoundDeeper() async {
        let info = GitInfo(
            head: "main", isDetached: false, root: root, gitDirectory: root.appendingPathComponent(".git"))
        var fileSystem = FakeFileSystem(listings: ["/fake": []], git: ["/fake": info])
        fileSystem.found["deep"] = [FileItem(url: URL(fileURLWithPath: "/fake/Sub/deep.txt"))]
        let model = BrowserModel(location: root, fileSystem: fileSystem)
        model.reload()
        await model.loadTask?.value
        await model.statusTask?.value
        model.searchText = "deep"
        await model.searchTask?.value

        #expect(model.gitState(of: model.items[0]) == .modified)
    }
}

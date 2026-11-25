import FindyCore
import Foundation
import Testing

@testable import FindyUI

/// In-memory file system: a fixed listing per directory path.
private struct FakeFileSystem: FileSystemProviding {
    struct Unreadable: Error {}

    var listings: [String: [FileItem]] = [:]

    func contents(of directory: URL) async throws -> [FileItem] {
        guard let items = listings[directory.path] else { throw Unreadable() }
        return items
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

    @Test func reportsUnreadableFolders() async {
        let model = makeModel()

        model.navigate(to: URL(fileURLWithPath: "/nowhere"))
        await model.loadTask?.value

        #expect(model.items.isEmpty)
        #expect(model.errorMessage != nil)
        #expect(!model.isLoading)
    }
}

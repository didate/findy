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

    @Test func reportsUnreadableFolders() async {
        let model = makeModel()

        model.navigate(to: URL(fileURLWithPath: "/nowhere"))
        await model.loadTask?.value

        #expect(model.items.isEmpty)
        #expect(model.errorMessage != nil)
        #expect(!model.isLoading)
    }
}

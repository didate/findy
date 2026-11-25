import FindyCore
import Foundation
import Testing

@testable import FindyUI

@MainActor
@Suite struct WorkspaceModelTests {
    private let fileManager = FileManager.default

    /// A defaults domain of its own, so tests never read or write the user's settings.
    private func makeDefaults() -> UserDefaults {
        let name = "FindyUITests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func withScratchDirectory(_ body: (URL) async throws -> Void) async throws {
        let directory = fileManager.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("FindyUITests-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: directory) }
        try await body(directory)
    }

    private func names(in directory: URL) -> [String] {
        ((try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? ["<unreadable>"]).sorted()
    }

    @Test func startsWithOnePane() {
        let workspace = WorkspaceModel(location: URL(fileURLWithPath: "/tmp"), defaults: makeDefaults())

        #expect(workspace.panes.count == 1)
        #expect(!workspace.isDualPane)
        #expect(workspace.otherPane == nil)
        #expect(workspace.activePane.location.path == "/tmp")
    }

    @Test func theSecondPaneOpensOnTheSameFolderAndSharesTheHistory() {
        let workspace = WorkspaceModel(location: URL(fileURLWithPath: "/tmp"), defaults: makeDefaults())

        workspace.toggleDualPane()

        #expect(workspace.isDualPane)
        #expect(workspace.panes[1].location == workspace.panes[0].location)
        #expect(workspace.panes[1].history === workspace.history)
        #expect(workspace.activePane === workspace.panes[0])
        #expect(workspace.otherPane === workspace.panes[1])
    }

    @Test func closingTheSecondPaneKeepsTheActiveOne() {
        let workspace = WorkspaceModel(location: URL(fileURLWithPath: "/tmp"), defaults: makeDefaults())
        workspace.toggleDualPane()
        let second = workspace.panes[1]
        workspace.switchPane()
        #expect(workspace.activePane === second)

        workspace.toggleDualPane()

        #expect(workspace.panes.count == 1)
        #expect(workspace.activePane === second)
    }

    @Test func switchingPanesDoesNothingWithASinglePane() {
        let workspace = WorkspaceModel(location: URL(fileURLWithPath: "/tmp"), defaults: makeDefaults())

        workspace.switchPane()

        #expect(workspace.activePaneIndex == 0)
    }

    @Test func remembersTheFolderSizeSetting() {
        let defaults = makeDefaults()
        let first = WorkspaceModel(location: URL(fileURLWithPath: "/tmp"), defaults: defaults)
        #expect(first.calculatesFolderSizes)
        first.toggleDualPane()

        first.calculatesFolderSizes = false

        #expect(first.panes.allSatisfy { !$0.calculatesFolderSizes })
        let second = WorkspaceModel(location: URL(fileURLWithPath: "/tmp"), defaults: defaults)
        #expect(!second.calculatesFolderSizes)
        #expect(!second.activePane.calculatesFolderSizes)
    }

    @Test func copiesAndMovesTheSelectionToTheOtherPane() async throws {
        try await withScratchDirectory { directory in
            let left = directory.appendingPathComponent("Left", isDirectory: true)
            let right = directory.appendingPathComponent("Right", isDirectory: true)
            try fileManager.createDirectory(at: left, withIntermediateDirectories: false)
            try fileManager.createDirectory(at: right, withIntermediateDirectories: false)
            try Data("a".utf8).write(to: left.appendingPathComponent("a.txt"))
            try Data("b".utf8).write(to: left.appendingPathComponent("b.txt"))

            let workspace = WorkspaceModel(location: left, defaults: makeDefaults())
            workspace.calculatesFolderSizes = false
            workspace.toggleDualPane()
            let source = workspace.panes[0]
            let target = workspace.panes[1]
            target.navigate(to: right)
            source.reload()
            await source.loadTask?.value
            await target.loadTask?.value

            source.selection = [try #require(source.items.first { $0.name == "a.txt" }).url]
            workspace.copySelectionToOtherPane()
            await target.operationTask?.value
            #expect(names(in: right) == ["a.txt"])
            #expect(names(in: left) == ["a.txt", "b.txt"])

            source.selection = [try #require(source.items.first { $0.name == "b.txt" }).url]
            workspace.moveSelectionToOtherPane()
            await target.operationTask?.value
            #expect(names(in: right) == ["a.txt", "b.txt"])
            #expect(names(in: left) == ["a.txt"])

            // One history for the window: undo from the source pane reverts the move made in the other.
            source.undo()
            await source.operationTask?.value
            #expect(names(in: left) == ["a.txt", "b.txt"])
        }
    }
}

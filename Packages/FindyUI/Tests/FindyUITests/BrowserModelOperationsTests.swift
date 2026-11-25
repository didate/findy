import FindyCore
import Foundation
import Testing

@testable import FindyUI

/// Operations of a pane, run against real files in a scratch directory.
@MainActor
@Suite struct BrowserModelOperationsTests {
    private let fileManager = FileManager.default

    private func withModel(_ body: (BrowserModel, URL) async throws -> Void) async throws {
        // Resolved, so the paths the model lists are the paths the test builds.
        let directory = fileManager.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("FindyUITests-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: directory) }
        let model = BrowserModel(location: directory, calculatesFolderSizes: false) { _ in }
        try await body(model, directory)
    }

    /// Waits for the operation in flight and for the listing it triggers.
    private func settle(_ model: BrowserModel) async {
        await model.operationTask?.value
        await model.loadTask?.value
    }

    private func names(in directory: URL) -> [String] {
        ((try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? ["<unreadable>"]).sorted()
    }

    private func content(of url: URL) -> String? {
        (try? Data(contentsOf: url)).map { String(decoding: $0, as: UTF8.self) }
    }

    private func select(_ name: String, in model: BrowserModel) async throws {
        model.reload()
        await model.loadTask?.value
        let item = try #require(model.items.first { $0.name == name })
        model.selection = [item.url]
    }

    @Test func createsAFolderSelectsItAndStartsRenaming() async throws {
        try await withModel { model, directory in
            model.newFolder()
            await settle(model)

            #expect(names(in: directory) == ["untitled folder"])
            #expect(model.selectedItems.map(\.name) == ["untitled folder"])
            #expect(model.renamingURL?.lastPathComponent == "untitled folder")
            #expect(model.history.undoName != nil)

            // Undo sends the new folder to the Trash; redo brings it back.
            model.undo()
            await settle(model)
            #expect(names(in: directory).isEmpty)

            model.redo()
            await settle(model)
            #expect(names(in: directory) == ["untitled folder"])
        }
    }

    @Test func renamesAndUndoesTheRename() async throws {
        try await withModel { model, directory in
            try Data("x".utf8).write(to: directory.appendingPathComponent("draft.txt"))
            try await select("draft.txt", in: model)
            model.beginRenamingSelection()
            let url = try #require(model.renamingURL)

            model.commitRename(of: url, to: "  final.txt ")
            await settle(model)

            #expect(names(in: directory) == ["final.txt"])
            #expect(model.renamingURL == nil)
            #expect(model.selectedItems.map(\.name) == ["final.txt"])

            model.undo()
            await settle(model)
            #expect(names(in: directory) == ["draft.txt"])

            model.redo()
            await settle(model)
            #expect(names(in: directory) == ["final.txt"])
        }
    }

    @Test func aRenameThatConflictsChangesNothingAndTellsTheUser() async throws {
        try await withModel { model, directory in
            try Data("a".utf8).write(to: directory.appendingPathComponent("a.txt"))
            try Data("b".utf8).write(to: directory.appendingPathComponent("b.txt"))
            try await select("a.txt", in: model)
            let url = try #require(model.selection.first)

            model.commitRename(of: url, to: "b.txt")
            await settle(model)

            #expect(names(in: directory) == ["a.txt", "b.txt"])
            #expect(content(of: directory.appendingPathComponent("b.txt")) == "b")
            #expect(model.alertMessage?.contains("b.txt") == true)
            #expect(model.history.undoName == nil)
        }
    }

    @Test func anUnchangedOrEmptyNameIsNotARename() async throws {
        try await withModel { model, directory in
            try Data().write(to: directory.appendingPathComponent("a.txt"))
            try await select("a.txt", in: model)
            let url = try #require(model.selection.first)

            model.commitRename(of: url, to: "a.txt")
            model.commitRename(of: url, to: "   ")
            await settle(model)

            #expect(names(in: directory) == ["a.txt"])
            #expect(model.alertMessage == nil)
            #expect(model.history.undoName == nil)
        }
    }

    @Test func trashesTheSelectionAndPutsItBackOnUndo() async throws {
        try await withModel { model, directory in
            try Data("keep".utf8).write(to: directory.appendingPathComponent("a.txt"))
            try Data().write(to: directory.appendingPathComponent("b.txt"))
            try await select("a.txt", in: model)

            model.trashSelection()
            await settle(model)
            #expect(names(in: directory) == ["b.txt"])

            // Undo, so the test leaves nothing in the user's Trash.
            model.undo()
            await settle(model)
            #expect(names(in: directory) == ["a.txt", "b.txt"])
            #expect(content(of: directory.appendingPathComponent("a.txt")) == "keep")
            #expect(model.alertMessage == nil)
        }
    }

    @Test func renamingNeedsExactlyOneSelectedEntry() async throws {
        try await withModel { model, directory in
            try Data().write(to: directory.appendingPathComponent("a.txt"))
            try Data().write(to: directory.appendingPathComponent("b.txt"))
            model.reload()
            await model.loadTask?.value

            model.beginRenamingSelection()
            #expect(model.renamingURL == nil)

            model.selection = Set(model.items.map(\.url))
            model.beginRenamingSelection()
            #expect(model.renamingURL == nil)
        }
    }
}

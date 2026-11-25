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

    // MARK: Copy and move

    /// Creates `Source/` with two files and an empty `Destination/`, and shows `Destination`.
    private func withTransferSetup(
        _ body: (BrowserModel, _ source: URL, _ destination: URL) async throws -> Void
    ) async throws {
        try await withModel { model, directory in
            let source = directory.appendingPathComponent("Source", isDirectory: true)
            let destination = directory.appendingPathComponent("Destination", isDirectory: true)
            try fileManager.createDirectory(at: source, withIntermediateDirectories: false)
            try fileManager.createDirectory(at: destination, withIntermediateDirectories: false)
            try Data("one".utf8).write(to: source.appendingPathComponent("one.txt"))
            try Data("two".utf8).write(to: source.appendingPathComponent("two.txt"))
            model.navigate(to: destination)
            await model.loadTask?.value
            try await body(model, source, destination)
        }
    }

    @Test func copiesFilesHereAndSelectsThem() async throws {
        try await withTransferSetup { model, source, destination in
            model.transfer([source.appendingPathComponent("one.txt")], move: false)
            await settle(model)

            #expect(names(in: destination) == ["one.txt"])
            #expect(names(in: source) == ["one.txt", "two.txt"])
            #expect(model.selectedItems.map(\.name) == ["one.txt"])
            #expect(model.pendingTransfer == nil)

            // Undo sends the copy to the Trash; the original is untouched.
            model.undo()
            await settle(model)
            #expect(names(in: destination).isEmpty)
            #expect(names(in: source) == ["one.txt", "two.txt"])
        }
    }

    @Test func movesFilesHereAndBackOnUndo() async throws {
        try await withTransferSetup { model, source, destination in
            let urls = ["one.txt", "two.txt"].map { source.appendingPathComponent($0) }

            model.transfer(urls, move: true)
            await settle(model)
            #expect(names(in: destination) == ["one.txt", "two.txt"])
            #expect(names(in: source).isEmpty)

            model.undo()
            await settle(model)
            #expect(names(in: destination).isEmpty)
            #expect(names(in: source) == ["one.txt", "two.txt"])

            model.redo()
            await settle(model)
            #expect(names(in: destination) == ["one.txt", "two.txt"])
        }
    }

    @Test func aNameConflictWaitsForTheUser() async throws {
        try await withTransferSetup { model, source, destination in
            try Data("existing".utf8).write(to: destination.appendingPathComponent("one.txt"))
            let urls = ["one.txt", "two.txt"].map { source.appendingPathComponent($0) }

            model.transfer(urls, move: false)
            await settle(model)

            // Nothing was copied yet, not even the file without a conflict.
            #expect(model.pendingTransfer?.conflictNames == ["one.txt"])
            #expect(names(in: destination) == ["one.txt"])
            #expect(content(of: destination.appendingPathComponent("one.txt")) == "existing")

            model.resolveTransfer(nil)
            await settle(model)
            #expect(model.pendingTransfer == nil)
            #expect(names(in: destination) == ["one.txt"])
        }
    }

    @Test func keepBothBringsTheConflictInUnderAFreeName() async throws {
        try await withTransferSetup { model, source, destination in
            try Data("existing".utf8).write(to: destination.appendingPathComponent("one.txt"))
            model.transfer([source.appendingPathComponent("one.txt")], move: false)
            await settle(model)

            model.resolveTransfer(.keepBoth)
            await settle(model)

            #expect(names(in: destination) == ["one 2.txt", "one.txt"])
            #expect(content(of: destination.appendingPathComponent("one.txt")) == "existing")
            #expect(content(of: destination.appendingPathComponent("one 2.txt")) == "one")
        }
    }

    @Test func skipLeavesTheConflictAndBringsTheRest() async throws {
        try await withTransferSetup { model, source, destination in
            try Data("existing".utf8).write(to: destination.appendingPathComponent("one.txt"))
            let urls = ["one.txt", "two.txt"].map { source.appendingPathComponent($0) }
            model.transfer(urls, move: true)
            await settle(model)

            model.resolveTransfer(.skip)
            await settle(model)

            #expect(names(in: destination) == ["one.txt", "two.txt"])
            #expect(content(of: destination.appendingPathComponent("one.txt")) == "existing")
            #expect(names(in: source) == ["one.txt"])
        }
    }

    @Test func replaceIsUndoneByBringingTheOldFileBack() async throws {
        try await withTransferSetup { model, source, destination in
            try Data("existing".utf8).write(to: destination.appendingPathComponent("one.txt"))
            model.transfer([source.appendingPathComponent("one.txt")], move: false)
            await settle(model)

            model.resolveTransfer(.replace)
            await settle(model)
            #expect(names(in: destination) == ["one.txt"])
            #expect(content(of: destination.appendingPathComponent("one.txt")) == "one")

            // Undo, which also empties what the test put in the user's Trash.
            model.undo()
            await settle(model)
            #expect(names(in: destination) == ["one.txt"])
            #expect(content(of: destination.appendingPathComponent("one.txt")) == "existing")
            #expect(model.alertMessage == nil)
        }
    }

    @Test func copyingAFileWhereItAlreadyIsDuplicatesIt() async throws {
        try await withTransferSetup { model, source, destination in
            model.navigate(to: source)
            await model.loadTask?.value

            model.transfer([source.appendingPathComponent("one.txt")], move: false)
            await settle(model)

            #expect(names(in: source) == ["one 2.txt", "one.txt", "two.txt"])
            #expect(model.pendingTransfer == nil)

            // Moving it where it already is does nothing at all.
            model.transfer([source.appendingPathComponent("two.txt")], move: true)
            await settle(model)
            #expect(names(in: source) == ["one 2.txt", "one.txt", "two.txt"])
        }
    }

    @Test func aFolderCannotBeCopiedIntoItself() async throws {
        try await withTransferSetup { model, source, destination in
            model.navigate(to: source)
            await model.loadTask?.value

            model.transfer([source], move: false)
            await settle(model)

            #expect(names(in: source) == ["one.txt", "two.txt"])
            #expect(model.alertMessage?.contains("Source") == true)
        }
    }

    // MARK: Drops

    @Test func aDropCanTargetAFolderOtherThanTheOneShown() async throws {
        try await withTransferSetup { model, source, destination in
            let inner = destination.appendingPathComponent("Inner", isDirectory: true)
            try fileManager.createDirectory(at: inner, withIntermediateDirectories: false)

            model.transfer([source.appendingPathComponent("one.txt")], move: true, into: inner)
            await settle(model)

            #expect(names(in: inner) == ["one.txt"])
            #expect(names(in: destination) == ["Inner"])
            #expect(names(in: source) == ["two.txt"])
            // The moved file is not in the folder shown, so nothing gets selected.
            #expect(model.selection.isEmpty)

            model.undo()
            await settle(model)
            #expect(names(in: inner).isEmpty)
            #expect(names(in: source) == ["one.txt", "two.txt"])
        }
    }

    @Test func refusesDropsThatWouldDoNothingOrLoop() async throws {
        try await withTransferSetup { model, source, destination in
            let file = source.appendingPathComponent("one.txt")
            let inner = source.appendingPathComponent("Inner", isDirectory: true)

            #expect(model.canAccept([file], in: destination, move: true))
            #expect(model.canAccept([file], in: destination, move: false))
            // Moving a file to the folder it is already in does nothing; copying duplicates it.
            #expect(!model.canAccept([file], in: source, move: true))
            #expect(model.canAccept([file], in: source, move: false))
            // A folder cannot go into itself or below itself.
            #expect(!model.canAccept([source], in: source, move: false))
            #expect(!model.canAccept([source], in: inner, move: true))
            // A folder whose name merely starts the same is a different folder.
            #expect(model.canAccept([source], in: URL(fileURLWithPath: source.path + "-2"), move: true))
            #expect(!model.canAccept([], in: destination, move: true))
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

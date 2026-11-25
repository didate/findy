import FindyCore
import Foundation

/// The actions of a pane that change the disk. Each one is undoable and reports its failures.
extension BrowserModel {
    var actions: FileActions { FileActions(operations: operations) }

    /// Creates a folder here, selects it and starts renaming it, as Finder does.
    public func newFolder() {
        let directory = location
        start {
            do {
                let name = String(localized: "untitled folder", bundle: .module)
                let folder = try await self.operations.createFolder(in: directory, named: name)
                self.history.record(self.actions.trash([folder], name: ActionName.newFolder))
                self.renameAfterLoad = folder.lastPathComponent
                self.finish(selecting: [folder])
            } catch {
                self.report(error)
            }
        }
    }

    /// Creates an empty file here, selects it and starts renaming it.
    public func newFile() {
        let directory = location
        start {
            do {
                let name = String(localized: "untitled.txt", bundle: .module)
                let file = try await self.operations.createFile(in: directory, named: name)
                self.history.record(self.actions.trash([file], name: ActionName.newFile))
                self.renameAfterLoad = file.lastPathComponent
                self.finish(selecting: [file])
            } catch {
                self.report(error)
            }
        }
    }

    /// Starts renaming the selected entry in the list. Does nothing unless exactly one is selected.
    public func beginRenamingSelection() {
        guard selection.count == 1, let url = selection.first else { return }
        renamingURL = url
    }

    public func cancelRename() {
        renamingURL = nil
    }

    public func commitRename(of url: URL, to newName: String) {
        renamingURL = nil
        let newName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        // An emptied field or an unchanged name means the user changed their mind.
        guard !newName.isEmpty, newName != url.lastPathComponent else { return }
        let renamed = url.deletingLastPathComponent().appendingPathComponent(newName)
        perform(actions.rename(url, to: newName, name: ActionName.rename), selecting: [renamed])
    }

    public func trashSelection() {
        let urls = selectedItems.map(\.url)
        guard !urls.isEmpty else { return }
        perform(actions.trash(urls, name: ActionName.moveToTrash))
    }

    public func undo() {
        start {
            if let error = await self.history.undo() { self.report(error) }
            self.finish()
        }
    }

    public func redo() {
        start {
            if let error = await self.history.redo() { self.report(error) }
            self.finish()
        }
    }

    // MARK: Plumbing

    func perform(_ step: UndoStep, selecting urls: [URL] = []) {
        start {
            if let error = await self.history.perform(step) { self.report(error) }
            self.finish(selecting: urls)
        }
    }

    func start(_ work: @escaping @MainActor () async -> Void) {
        operationTask = Task {
            isBusy = true
            await work()
            isBusy = false
        }
    }

    /// Shows the result at once instead of waiting for the file system to report the change.
    /// `urls` are entries of this folder to select once listed.
    func finish(selecting urls: [URL] = []) {
        if !urls.isEmpty { selectAfterLoad = Set(urls.map(\.lastPathComponent)) }
        refresh()
    }

    /// Stops the operation in flight. What it already completed stays, and stays undoable; the
    /// item it was working on is left as it was.
    public func cancelOperation() {
        operationTask?.cancel()
    }

    func report(_ error: any Error) {
        // The user asked for the stop: nothing to announce.
        if error is CancellationError { return }
        alertMessage = ErrorMessage.text(for: error)
    }
}

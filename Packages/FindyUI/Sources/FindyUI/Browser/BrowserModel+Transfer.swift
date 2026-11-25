import FindyCore
import Foundation

/// Bringing files into a pane: paste, and copy or move from another pane.
extension BrowserModel {
    public func copySelection() {
        FilePasteboard.write(selectedItems.map(\.url), cut: false)
    }

    public func cutSelection() {
        FilePasteboard.write(selectedItems.map(\.url), cut: true)
    }

    /// Makes a copy of each selected entry next to it, under a free name.
    public func duplicateSelection() {
        transfer(selectedItems.map(\.url), move: false)
    }

    /// Pastes the files of the clipboard here: a move if they were cut in Findy, a copy otherwise.
    public func paste() {
        guard let (urls, isCut) = FilePasteboard.read() else { return }
        if isCut { FilePasteboard.didPasteCut() }
        transfer(urls, move: isCut)
    }

    /// Whether dropping `urls` into `directory` would do something. A folder cannot go into itself
    /// or one of its subfolders, and moving files to the folder they are already in is a no-op.
    public func canAccept(_ urls: [URL], in directory: URL, move: Bool) -> Bool {
        guard !urls.isEmpty else { return false }
        let target = directory.standardizedFileURL.path
        for url in urls {
            let path = url.standardizedFileURL.path
            if target == path || target.hasPrefix(path + "/") { return false }
        }
        return !move || urls.contains { !Self.isInside($0, directory: directory) }
    }

    /// Handles files dropped on something that stands for `directory`. Drops that would do nothing
    /// or put a folder inside itself are ignored.
    public func drop(_ urls: [URL], into directory: URL, move: Bool) {
        guard canAccept(urls, in: directory, move: move) else { return }
        transfer(urls, move: move, into: directory)
    }

    /// Copies or moves `urls` into `directory`, this pane's folder by default. If some names are
    /// already taken, nothing happens yet: `pendingTransfer` is set and the user decides with
    /// `resolveTransfer`.
    public func transfer(_ urls: [URL], move: Bool, into directory: URL? = nil) {
        guard !urls.isEmpty else { return }
        let directory = directory ?? location
        start {
            var conflicts: [URL] = []
            for url in urls where !Self.isInside(url, directory: directory) {
                let destination = directory.appendingPathComponent(url.lastPathComponent)
                if await self.operations.itemExists(at: destination) { conflicts.append(url) }
            }
            if conflicts.isEmpty {
                await self.run(
                    PendingTransfer(sources: urls, isMove: move, directory: directory, conflicts: []),
                    choice: .keepBoth)
            } else {
                self.pendingTransfer = PendingTransfer(
                    sources: urls, isMove: move, directory: directory, conflicts: conflicts)
            }
        }
    }

    /// Carries out the transfer that was waiting, or drops it when `choice` is `nil`.
    public func resolveTransfer(_ choice: ConflictChoice?) {
        guard let pending = pendingTransfer else { return }
        pendingTransfer = nil
        guard let choice else { return }
        start { await self.run(pending, choice: choice) }
    }

    private func run(_ transfer: PendingTransfer, choice: ConflictChoice) async {
        let directory = transfer.directory
        let conflicts = Set(transfer.conflicts)
        var relocations: [Relocation] = []
        var replaced: [URL] = []

        for source in transfer.sources {
            let name = source.lastPathComponent
            let sameName = directory.appendingPathComponent(name)
            if Self.isInside(source, directory: directory) {
                // Moving a file to where it already is does nothing. Copying it there duplicates it.
                guard !transfer.isMove else { continue }
                relocations.append(Relocation(source: source, destination: await freeURL(for: source, in: directory)))
            } else if conflicts.contains(source) {
                switch choice {
                case .keepBoth:
                    relocations.append(
                        Relocation(source: source, destination: await freeURL(for: source, in: directory)))
                case .replace:
                    replaced.append(sameName)
                    relocations.append(Relocation(source: source, destination: sameName))
                case .skip:
                    continue
                }
            } else {
                relocations.append(Relocation(source: source, destination: sameName))
            }
        }
        guard !relocations.isEmpty else { return }

        // Progress: the copy adds up its bytes on its own thread and the bar samples the count.
        // The total is measured alongside, so the copy does not wait for it.
        progress = OperationProgress(isMove: transfer.isMove)
        let counter = ByteCounter()
        let sampling = Task {
            while !Task.isCancelled {
                progress?.completedBytes = counter.value
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
        let measuring = Task { [operations] in
            let total = await operations.totalSize(of: relocations.map(\.source))
            if !Task.isCancelled { progress?.totalBytes = total }
        }
        let onBytesCopied: @Sendable (Int64) -> Void = { counter.add($0) }

        let name = transfer.isMove ? ActionName.move : ActionName.copy
        var steps: [UndoStep] = []
        // Replaced items go to the Trash first, so undo can bring them back.
        if !replaced.isEmpty { steps.append(actions.trash(replaced, name: name)) }
        steps.append(
            transfer.isMove
                ? actions.move(relocations, name: name, onBytesCopied: onBytesCopied)
                : actions.copy(relocations, name: name, onBytesCopied: onBytesCopied))
        let step = steps.count == 1 ? steps[0] : actions.sequence(steps, name: name)

        let failure = await history.perform(step)
        sampling.cancel()
        measuring.cancel()
        progress = nil
        if let failure { report(failure) }
        // Only select the results if the user is still looking at the folder they arrived in.
        finish(selecting: location == directory ? relocations.map(\.destination) : [])
    }

    private func freeURL(for source: URL, in directory: URL) async -> URL {
        await operations.availableURL(
            for: source.lastPathComponent, in: directory, keepingExtension: !source.hasDirectoryPath)
    }

    /// Whether `url` is a direct child of `directory`.
    private static func isInside(_ url: URL, directory: URL) -> Bool {
        url.deletingLastPathComponent().standardizedFileURL.path == directory.standardizedFileURL.path
    }
}

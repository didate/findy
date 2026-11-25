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

    /// Pastes the files of the clipboard here: a move if they were cut in Findy, a copy otherwise.
    public func paste() {
        guard let (urls, isCut) = FilePasteboard.read() else { return }
        if isCut { FilePasteboard.didPasteCut() }
        transfer(urls, move: isCut)
    }

    /// Copies or moves `urls` into this pane's folder. If some names are already taken, nothing
    /// happens yet: `pendingTransfer` is set and the user decides with `resolveTransfer`.
    public func transfer(_ urls: [URL], move: Bool) {
        guard !urls.isEmpty else { return }
        let directory = location
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

        let name = transfer.isMove ? ActionName.move : ActionName.copy
        var steps: [UndoStep] = []
        // Replaced items go to the Trash first, so undo can bring them back.
        if !replaced.isEmpty { steps.append(actions.trash(replaced, name: name)) }
        steps.append(transfer.isMove ? actions.move(relocations, name: name) : actions.copy(relocations, name: name))
        let step = steps.count == 1 ? steps[0] : actions.sequence(steps, name: name)

        if let error = await history.perform(step) { report(error) }
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

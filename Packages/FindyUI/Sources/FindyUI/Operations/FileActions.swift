import FindyCore
import Foundation

/// Builds reversible steps out of the one-item primitives of `FileOperating`.
///
/// Every step stops at the first failure and its inverse covers exactly the items that were done,
/// so an action interrupted halfway can still be undone.
struct FileActions: Sendable {
    let operations: any FileOperating

    /// Gives each item the color paired with it. Undone by giving back the colors they had.
    func setLabels(_ changes: [LabelChange], name: String) -> UndoStep {
        UndoStep(name: name) {
            var done: [LabelChange] = []
            var failure: (any Error)?
            for change in changes {
                do {
                    try await operations.setLabel(change.new, on: change.url)
                    done.append(change)
                } catch {
                    failure = error
                    break
                }
            }
            let back = done.reversed().map(\.reversed)
            return .init(inverse: back.isEmpty ? nil : setLabels(back, name: name), error: failure)
        }
    }

    /// Moves items to the Trash. Undone by putting them back.
    func trash(_ urls: [URL], name: String) -> UndoStep {
        UndoStep(name: name) {
            var trashed: [Relocation] = []
            var failure: (any Error)?
            for url in urls {
                do {
                    trashed.append(Relocation(source: url, destination: try await operations.trash(url)))
                } catch {
                    failure = error
                    break
                }
            }
            return .init(inverse: trashed.isEmpty ? nil : putBack(trashed, name: name), error: failure)
        }
    }

    /// Moves trashed items back where they were. Undone by trashing them again.
    func putBack(_ trashed: [Relocation], name: String) -> UndoStep {
        UndoStep(name: name) {
            var restored: [URL] = []
            var failure: (any Error)?
            for item in trashed.reversed() {
                do {
                    try await operations.move(item.destination, to: item.source)
                    restored.append(item.source)
                } catch {
                    failure = error
                    break
                }
            }
            return .init(inverse: restored.isEmpty ? nil : trash(restored.reversed(), name: name), error: failure)
        }
    }

    /// Moves each item to an exact destination. Undone by moving them back.
    /// `onBytesCopied` follows the data written by moves across volumes.
    func move(
        _ moves: [Relocation], name: String, onBytesCopied: (@Sendable (Int64) -> Void)? = nil
    ) -> UndoStep {
        UndoStep(name: name) {
            var moved: [Relocation] = []
            var failure: (any Error)?
            for item in moves {
                do {
                    try await operations.move(item.source, to: item.destination, onBytesCopied: onBytesCopied)
                    moved.append(item)
                } catch {
                    failure = error
                    break
                }
            }
            let back = moved.reversed().map(\.reversed)
            return .init(inverse: back.isEmpty ? nil : move(back, name: name), error: failure)
        }
    }

    /// Copies each item to an exact destination. Undone by trashing the copies, never by deleting.
    func copy(
        _ copies: [Relocation], name: String, onBytesCopied: (@Sendable (Int64) -> Void)? = nil
    ) -> UndoStep {
        UndoStep(name: name) {
            var copied: [URL] = []
            var failure: (any Error)?
            for item in copies {
                do {
                    try await operations.copy(item.source, to: item.destination, onBytesCopied: onBytesCopied)
                    copied.append(item.destination)
                } catch {
                    failure = error
                    break
                }
            }
            return .init(inverse: copied.isEmpty ? nil : trash(copied.reversed(), name: name), error: failure)
        }
    }

    func rename(_ url: URL, to newName: String, name: String) -> UndoStep {
        UndoStep(name: name) {
            do {
                let renamed = try await operations.rename(url, to: newName)
                return .init(inverse: rename(renamed, to: url.lastPathComponent, name: name))
            } catch {
                return .init(error: error)
            }
        }
    }

    /// Runs steps in order. Undone by running their inverses in the opposite order.
    func sequence(_ steps: [UndoStep], name: String) -> UndoStep {
        UndoStep(name: name) {
            var inverses: [UndoStep] = []
            var failure: (any Error)?
            for step in steps {
                let outcome = await step.run()
                if let inverse = outcome.inverse { inverses.append(inverse) }
                if let error = outcome.error {
                    failure = error
                    break
                }
            }
            return .init(
                inverse: inverses.isEmpty ? nil : sequence(inverses.reversed(), name: name), error: failure)
        }
    }
}

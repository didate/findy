import Foundation
import Observation

/// The undo and redo stacks of a window.
///
/// Not `UndoManager`: file operations are asynchronous, and `UndoManager` needs the inverse of an
/// undo registered before the undo returns, which is before an asynchronous one has even run.
@MainActor
@Observable
public final class UndoHistory {
    private var undoStack: [UndoStep] = []
    private var redoStack: [UndoStep] = []
    private var isRunning = false

    /// The name of the action Undo would revert, or `nil` when there is nothing to undo.
    public var undoName: String? { undoStack.last?.name }
    public var redoName: String? { redoStack.last?.name }

    public init() {}

    /// Runs a new action and remembers how to undo it. Returns what stopped it, if anything.
    /// A partly done action is still undoable for the part that was done.
    @discardableResult
    public func perform(_ step: UndoStep) async -> (any Error)? {
        guard !isRunning else { return nil }
        isRunning = true
        defer { isRunning = false }
        let outcome = await step.run()
        if let inverse = outcome.inverse {
            undoStack.append(inverse)
            redoStack.removeAll()
        }
        return outcome.error
    }

    /// Remembers how to undo an action that was already carried out.
    public func record(_ inverse: UndoStep) {
        undoStack.append(inverse)
        redoStack.removeAll()
    }

    @discardableResult
    public func undo() async -> (any Error)? {
        guard !isRunning, let step = undoStack.popLast() else { return nil }
        isRunning = true
        defer { isRunning = false }
        let outcome = await step.run()
        if let inverse = outcome.inverse { redoStack.append(inverse) }
        return outcome.error
    }

    @discardableResult
    public func redo() async -> (any Error)? {
        guard !isRunning, let step = redoStack.popLast() else { return nil }
        isRunning = true
        defer { isRunning = false }
        let outcome = await step.run()
        if let inverse = outcome.inverse { undoStack.append(inverse) }
        return outcome.error
    }
}

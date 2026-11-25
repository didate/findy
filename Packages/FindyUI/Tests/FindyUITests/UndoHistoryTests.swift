import Foundation
import Testing

@testable import FindyUI

@MainActor
@Suite struct UndoHistoryTests {
    private struct Boom: Error {}

    /// Collects what ran, in order.
    @MainActor private final class Log {
        var entries: [String] = []
    }

    /// A step that logs `text`, and whose inverse logs the opposite, back and forth.
    private func step(_ text: String, undoText: String, log: Log) -> UndoStep {
        UndoStep(name: "Test") {
            log.entries.append(text)
            return .init(inverse: step(undoText, undoText: text, log: log))
        }
    }

    @Test func undoesAndRedoesInOrder() async {
        let log = Log()
        let history = UndoHistory()
        #expect(history.undoName == nil)

        await history.perform(step("do A", undoText: "undo A", log: log))
        await history.perform(step("do B", undoText: "undo B", log: log))
        #expect(history.undoName == "Test")

        await history.undo()
        await history.undo()
        await history.undo()
        #expect(log.entries == ["do A", "do B", "undo B", "undo A"])
        #expect(history.undoName == nil)

        await history.redo()
        #expect(log.entries.last == "do A")
        #expect(history.redoName == "Test")
        #expect(history.undoName == "Test")
    }

    @Test func aNewActionClearsRedo() async {
        let log = Log()
        let history = UndoHistory()
        await history.perform(step("do A", undoText: "undo A", log: log))
        await history.undo()
        #expect(history.redoName != nil)

        await history.perform(step("do B", undoText: "undo B", log: log))

        #expect(history.redoName == nil)
    }

    @Test func aFailedStepReportsItsErrorAndIsNotRecorded() async {
        let history = UndoHistory()

        let error = await history.perform(UndoStep(name: "Fails") { .init(error: Boom()) })

        #expect(error is Boom)
        #expect(history.undoName == nil)
    }

    @Test func aPartlyDoneStepIsStillUndoable() async {
        let log = Log()
        let history = UndoHistory()
        let partial = UndoStep(name: "Partial") {
            .init(inverse: step("undo half", undoText: "redo half", log: log), error: Boom())
        }

        let error = await history.perform(partial)
        await history.undo()

        #expect(error is Boom)
        #expect(log.entries == ["undo half"])
    }
}

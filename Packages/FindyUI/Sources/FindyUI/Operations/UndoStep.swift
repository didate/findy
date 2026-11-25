import Foundation

/// One reversible action, ready to run. Running it does the work and hands back its inverse.
public struct UndoStep: Sendable {
    public struct Outcome: Sendable {
        /// Undoes whatever part of the step was actually done. `nil` when nothing was done.
        public var inverse: UndoStep?
        /// What stopped the step, if it did not complete.
        public var error: (any Error)?

        public init(inverse: UndoStep? = nil, error: (any Error)? = nil) {
            self.inverse = inverse
            self.error = error
        }
    }

    /// The user-facing name of the action (“Move to Trash”). An inverse keeps the name of the
    /// action it undoes, so the menu reads “Undo Move to Trash”, then “Redo Move to Trash”.
    public let name: String
    public let run: @MainActor @Sendable () async -> Outcome

    public init(name: String, run: @escaping @MainActor @Sendable () async -> Outcome) {
        self.name = name
        self.run = run
    }
}

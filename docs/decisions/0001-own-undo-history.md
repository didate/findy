# 1. An undo history of our own instead of UndoManager

## Context

Every file operation must be undoable. AppKit offers `UndoManager`, which the Edit menu drives for free.

`UndoManager` expects the inverse of an undo to be registered while the undo is running, synchronously. Our operations are asynchronous: a trash, a copy or a move runs off the main thread and only knows its result (for example where the item landed in the Trash) once it has finished. By then `UndoManager` no longer considers itself undoing, so the inverse lands on the undo stack instead of the redo stack and wipes the redo history.

## Decision

`UndoHistory` keeps two stacks of `UndoStep`. Running a step does the work and returns its inverse. A step that fails halfway returns the inverse of the part that was done, so it stays undoable.

The Edit menu items are replaced by our own, which call `UndoHistory` and show the name of the action. While a text field is being edited they forward to that field's `UndoManager`, so text undo still works.

## Alternatives set aside

- **`UndoManager` with synchronous operations**: would block the main thread during a copy.
- **`UndoManager` with a placeholder inverse filled in later**: works, but the bookkeeping is fragile and hard to test.

## Consequences

- One history per window, shared by its panes.
- Undo of a copy sends the copies to the Trash; it never deletes.
- The history is not persisted across launches.

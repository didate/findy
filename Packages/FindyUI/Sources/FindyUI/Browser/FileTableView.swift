import AppKit

/// What the table asks of its owner when the user acts with the keyboard.
@MainActor
protocol FileTableViewActions: AnyObject {
    func tableViewDidBecomeActive()
    func tableViewAppendToFilter(_ text: String)
    /// Returns `false` when there was nothing to delete, so the key keeps its usual meaning.
    func tableViewDeleteFilterBackward() -> Bool
    /// Returns `false` when there was no filter, so the key keeps its usual meaning.
    func tableViewClearFilter() -> Bool
}

/// `NSTableView` that turns plain typing into an instant filter.
final class FileTableView: NSTableView {
    weak var actions: (any FileTableViewActions)?

    private enum KeyCode {
        static let delete: UInt16 = 51
        static let escape: UInt16 = 53
    }

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became { actions?.tableViewDidBecomeActive() }
        return became
    }

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.command, .control, .option])
        guard modifiers.isEmpty, let actions else {
            super.keyDown(with: event)
            return
        }
        switch event.keyCode {
        case KeyCode.escape:
            if actions.tableViewClearFilter() { return }
        case KeyCode.delete:
            if actions.tableViewDeleteFilterBackward() { return }
        default:
            if let text = event.characters, Self.isFilterText(text) {
                actions.tableViewAppendToFilter(text)
                return
            }
        }
        super.keyDown(with: event)
    }

    /// Printable text only: no control characters, no arrow or function keys (private-use scalars),
    /// and no leading space, which is reserved for Quick Look.
    private static func isFilterText(_ text: String) -> Bool {
        guard !text.isEmpty, text != " " else { return false }
        return text.unicodeScalars.allSatisfy { scalar in
            !CharacterSet.controlCharacters.contains(scalar) && !(0xF700...0xF8FF).contains(scalar.value)
        }
    }
}

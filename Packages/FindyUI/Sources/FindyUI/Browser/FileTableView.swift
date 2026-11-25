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
    func tableViewBeginRename()
    func tableViewContextMenu() -> NSMenu?
    var tableViewCanCopy: Bool { get }
    var tableViewCanPaste: Bool { get }
    func tableViewCopy()
    func tableViewCut()
    func tableViewPaste()
}

/// `NSTableView` that turns plain typing into an instant filter.
final class FileTableView: NSTableView {
    weak var actions: (any FileTableViewActions)?

    private enum KeyCode {
        static let delete: UInt16 = 51
        static let escape: UInt16 = 53
        static let `return`: UInt16 = 36
        static let enter: UInt16 = 76
    }

    // MARK: Clipboard

    // The Edit menu sends these down the responder chain. A text field being edited comes first
    // in the chain, so its own Cut, Copy and Paste keep working on text.

    @objc func copy(_ sender: Any?) {
        actions?.tableViewCopy()
    }

    @objc func cut(_ sender: Any?) {
        actions?.tableViewCut()
    }

    @objc func paste(_ sender: Any?) {
        actions?.tableViewPaste()
    }

    override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        switch item.action {
        case #selector(copy(_:)), #selector(cut(_:)):
            actions?.tableViewCanCopy ?? false
        case #selector(paste(_:)):
            actions?.tableViewCanPaste ?? false
        default:
            super.validateUserInterfaceItem(item)
        }
    }

    // MARK: Context menu

    override func menu(for event: NSEvent) -> NSMenu? {
        let row = row(at: convert(event.locationInWindow, from: nil))
        // A right-click acts on the row under the pointer, as in Finder: it joins an existing
        // selection it is part of, and replaces any other.
        if row < 0 {
            deselectAll(nil)
        } else if !selectedRowIndexes.contains(row) {
            selectRowIndexes([row], byExtendingSelection: false)
        }
        return actions?.tableViewContextMenu()
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
        case KeyCode.return, KeyCode.enter:
            actions.tableViewBeginRename()
            return
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

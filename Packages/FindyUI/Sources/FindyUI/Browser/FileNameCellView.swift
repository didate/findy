import AppKit

/// The cell of the Name column: icon, name, and a Git badge at the trailing edge.
final class FileNameCellView: NSTableCellView {
    let badgeField = NSTextField(labelWithString: "")

    func show(_ badge: GitBadge?) {
        badgeField.stringValue = badge?.text ?? ""
        badgeField.textColor = badge?.color
        badgeField.toolTip = badge?.label
        badgeField.setAccessibilityLabel(badge?.label)
        badgeField.isHidden = badge == nil
    }
}

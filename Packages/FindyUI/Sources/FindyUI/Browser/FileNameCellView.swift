import AppKit

/// The cell of the Name column: icon, name, and a Git badge at the trailing edge.
final class FileNameCellView: NSTableCellView {
    let badgeField = NSTextField(labelWithString: "")
    private var badgeColor: NSColor?

    func show(_ badge: GitBadge?) {
        badgeField.stringValue = badge?.text ?? ""
        badgeColor = badge?.color
        badgeField.toolTip = badge?.label
        badgeField.setAccessibilityLabel(badge?.label)
        badgeField.isHidden = badge == nil
        applyBadgeColor()
    }

    // On a selected row the background is the accent color: an orange or green letter would be
    // hard to read there, so it takes the color of selected text.
    override var backgroundStyle: NSView.BackgroundStyle {
        didSet { applyBadgeColor() }
    }

    private func applyBadgeColor() {
        badgeField.textColor = backgroundStyle == .emphasized ? .alternateSelectedControlTextColor : badgeColor
    }
}

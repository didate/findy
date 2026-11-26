import AppKit
import FindyCore

/// The cell of the Name column: icon, name, the dot of the color label right after the name,
/// and a Git badge at the trailing edge.
final class FileNameCellView: NSTableCellView {
    let badgeField = NSTextField(labelWithString: "")
    /// The dot of the color label, right after the name.
    let labelDot = NSImageView()
    /// Stretches the name up to the Git badge. Active only while the name is being edited.
    var editingWidth: NSLayoutConstraint?
    private var badgeColor: NSColor?

    func show(_ label: FileLabel?) {
        labelDot.isHidden = label == nil
        labelDot.contentTintColor = label?.color
        labelDot.toolTip = label?.name
        labelDot.setAccessibilityLabel(label.map { String(localized: "\($0.name) label", bundle: .module) })
    }

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

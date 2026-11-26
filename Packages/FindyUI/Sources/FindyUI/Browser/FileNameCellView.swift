import AppKit
import FindyCore

/// The cell of the Name column: icon, name, the color label and a Git badge at the trailing edge.
///
/// A folder wears its color label on its icon, as in Finder. A file shows it as a dot right after
/// its name: its icon is a preview or the mark of its type, which a tint would spoil.
final class FileNameCellView: NSTableCellView {
    let badgeField = NSTextField(labelWithString: "")
    /// The dot of the color label, right after the name.
    let labelDot = NSImageView()
    /// Stretches the name up to the Git badge. Active only while the name is being edited.
    var editingWidth: NSLayoutConstraint?
    private var badgeColor: NSColor?

    /// The color the icon is tinted with. `nil` for a file and for a folder with no label.
    private var iconTint: NSColor?

    /// Shows `label` on the icon when `onIcon` is set, as a dot after the name otherwise. Call it
    /// before `setIcon`.
    func show(_ label: FileLabel?, onIcon: Bool) {
        let spoken = label.map { String(localized: "\($0.name) label", bundle: .module) }
        iconTint = onIcon ? label?.color : nil
        imageView?.toolTip = onIcon ? label?.name : nil
        imageView?.setAccessibilityLabel(onIcon ? spoken : nil)
        labelDot.isHidden = onIcon || label == nil
        labelDot.contentTintColor = label?.color
        labelDot.toolTip = label?.name
        labelDot.setAccessibilityLabel(spoken)
    }

    /// Sets the icon of the row, tinted when the row is a folder with a color label.
    func setIcon(_ icon: NSImage) {
        imageView?.image = iconTint.map { Self.tinted(icon, with: $0) } ?? icon
    }

    /// `icon` with the hue of `color` and its own light and shade, so a folder keeps its relief.
    private static func tinted(_ icon: NSImage, with color: NSColor) -> NSImage {
        // Drawn on demand, so the system color follows light and dark mode.
        NSImage(size: icon.size, flipped: false) { rect in
            icon.draw(in: rect)
            color.setFill()
            rect.fill(using: .color)
            // The fill also painted the transparent corners: cut the result back to the icon's shape.
            icon.draw(in: rect, from: .zero, operation: .destinationIn, fraction: 1)
            return true
        }
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

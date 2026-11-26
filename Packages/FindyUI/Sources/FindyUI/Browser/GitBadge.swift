import AppKit
import FindyCore

/// How a Git state is shown at the end of a row: a letter, a system color and a spoken name.
struct GitBadge {
    let text: String
    let color: NSColor
    let label: String

    /// `nil` for the states that show no badge: an ignored entry is dimmed instead, and a
    /// deleted one is not in the list at all.
    @MainActor
    init?(_ state: GitFileState) {
        switch state {
        case .modified:
            self.init(text: "M", color: .systemOrange, label: String(localized: "Modified", bundle: .module))
        case .added:
            self.init(text: "A", color: .systemGreen, label: String(localized: "Added", bundle: .module))
        case .renamed:
            self.init(text: "R", color: .systemBlue, label: String(localized: "Renamed", bundle: .module))
        case .conflicted:
            self.init(text: "!", color: .systemRed, label: String(localized: "Conflict", bundle: .module))
        case .untracked:
            self.init(text: "U", color: .systemGreen, label: String(localized: "Untracked", bundle: .module))
        case .containsChanges:
            // Not a dot: a round mark is a color label.
            self.init(text: "±", color: .systemOrange, label: String(localized: "Contains changes", bundle: .module))
        case .ignored, .deleted:
            return nil
        }
    }

    private init(text: String, color: NSColor, label: String) {
        self.text = text
        self.color = color
        self.label = label
    }
}

import Foundation
import Observation

/// The files waiting to be moved by a paste, so every list can show them dimmed.
///
/// One instance for the app: the clipboard is shared, and two panes may show the same folder.
@MainActor
@Observable
final class CutFiles {
    static let shared = CutFiles()

    private var urls: Set<URL> = []
    /// `changeCount` of the clipboard right after the cut. Any later copy, in Findy or elsewhere,
    /// changes the count: the files are then no longer "cut".
    private var changeCount: Int?

    func set(_ cut: [URL], changeCount: Int) {
        urls = Set(cut)
        self.changeCount = changeCount
    }

    func clear() {
        urls = []
        changeCount = nil
    }

    /// The cut files, as long as the clipboard still holds them.
    func current(clipboardChangeCount: Int) -> Set<URL> {
        clipboardChangeCount == changeCount ? urls : []
    }
}

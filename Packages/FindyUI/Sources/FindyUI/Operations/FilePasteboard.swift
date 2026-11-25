import AppKit

/// Files on the system clipboard, shared with Finder and every other app.
@MainActor
enum FilePasteboard {
    /// `changeCount` of the pasteboard right after a Cut. The system has no notion of "cut files":
    /// a paste is a move only while the clipboard still holds what Findy cut.
    private static var cutChangeCount: Int?

    static func write(_ urls: [URL], cut: Bool) {
        guard !urls.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects(urls.map { $0 as NSURL })
        cutChangeCount = cut ? pasteboard.changeCount : nil
    }

    static func write(text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        cutChangeCount = nil
    }

    static var hasFiles: Bool {
        NSPasteboard.general.canReadObject(
            forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
    }

    static func read() -> (urls: [URL], isCut: Bool)? {
        let pasteboard = NSPasteboard.general
        let objects = pasteboard.readObjects(
            forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
        guard let urls = objects as? [URL], !urls.isEmpty else { return nil }
        return (urls, pasteboard.changeCount == cutChangeCount)
    }

    /// Cut files can be pasted once: after the move they are no longer where the clipboard says.
    static func didPasteCut() {
        cutChangeCount = nil
        NSPasteboard.general.clearContents()
    }
}

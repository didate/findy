import AppKit
import SwiftUI

/// Identity of the browser window scene, and the hand-off that turns a new window into a tab.
@MainActor
public enum BrowserWindow {
    /// The `id` of the `WindowGroup` that hosts `BrowserView`.
    public static let sceneID = "browser"

    /// Every open browser window.
    private static let windows = NSHashTable<NSWindow>.weakObjects()
    /// The window the next new window must join as a tab, set by the New Tab command.
    private static weak var tabHost: NSWindow?
    /// The folder the next new window must show first, set by the New Tab command.
    private(set) static var pendingLocation: URL?

    /// Opens a new browser window as a tab of the frontmost one, showing `location`.
    static func openTab(at location: URL?, with openWindow: OpenWindowAction) {
        // `keyWindow` is nil while another app is active, hence the fallback on window order.
        tabHost = [NSApp.keyWindow].compactMap { $0 }.first(where: windows.contains)
            ?? NSApp.orderedWindows.first(where: windows.contains)
        pendingLocation = location
        openWindow(id: sceneID)
    }

    /// Called by each browser window when it gets its `NSWindow`.
    static func windowDidAppear(_ window: NSWindow) {
        windows.add(window)
        pendingLocation = nil
        guard let host = tabHost, host !== window else { return }
        tabHost = nil
        host.addTabbedWindow(window, ordered: .above)
        window.makeKeyAndOrderFront(nil)
    }
}

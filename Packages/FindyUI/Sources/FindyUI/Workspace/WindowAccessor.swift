import AppKit
import SwiftUI

/// Reports the `NSWindow` a SwiftUI view ends up in. SwiftUI has no API for window tabs.
struct WindowAccessor: NSViewRepresentable {
    let onWindow: @MainActor (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = TrackingView()
        view.onWindow = onWindow
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {}

    private final class TrackingView: NSView {
        var onWindow: (@MainActor (NSWindow) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { onWindow?(window) }
        }
    }
}

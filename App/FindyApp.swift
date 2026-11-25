import FindyUI
import SwiftUI

@main
struct FindyApp: App {
    var body: some Scene {
        WindowGroup {
            BrowserView()
                .frame(minWidth: 640, minHeight: 360)
        }
        .defaultSize(width: 980, height: 620)
        .commands { BrowserCommands() }
    }
}

import FindyUI
import SwiftUI

@main
struct FindyApp: App {
    var body: some Scene {
        WindowGroup(id: BrowserWindow.sceneID) {
            BrowserView(location: Self.launchLocation)
                .frame(minWidth: 640, minHeight: 360)
        }
        .defaultSize(width: 980, height: 620)
        .commands { BrowserCommands() }

        Settings {
            SettingsView()
        }
    }

    /// A folder given on the command line (`open -a Findy --args /some/folder`), if any.
    private static var launchLocation: URL? {
        CommandLine.arguments.dropFirst()
            .first { $0.hasPrefix("/") }
            .map { URL(filePath: $0, directoryHint: .isDirectory) }
    }
}

import SwiftUI

/// The app's Settings window.
public struct SettingsView: View {
    @AppStorage(TerminalLauncher.preferenceKey) private var terminalIdentifier = TerminalApp.terminal.bundleIdentifier

    public init() {}

    public var body: some View {
        Form {
            Picker(selection: $terminalIdentifier) {
                ForEach(TerminalLauncher.installed) { terminal in
                    Text(verbatim: terminal.name).tag(terminal.bundleIdentifier)
                }
            } label: {
                Text("Terminal app:", bundle: .module)
            }
            Text("Used by Open in Terminal.", bundle: .module)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 380)
    }
}

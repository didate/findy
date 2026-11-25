import SwiftUI

/// The app's Settings window.
public struct SettingsView: View {
    @AppStorage(TerminalLauncher.preferenceKey) private var terminalIdentifier = TerminalApp.terminal.bundleIdentifier

    @AppStorage(EditorLauncher.preferenceKey) private var editorIdentifier = ""

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

            let editors = EditorLauncher.installed
            Picker(selection: editorSelection(among: editors)) {
                ForEach(editors) { editor in
                    Text(verbatim: editor.name).tag(editor.bundleIdentifier)
                }
            } label: {
                Text("Code editor:", bundle: .module)
            }
            .disabled(editors.isEmpty)
            Text("Used by Open in Editor.", bundle: .module)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 380)
    }

    /// Shows the editor that would really be used when the user chose none yet.
    private func editorSelection(among editors: [EditorApp]) -> Binding<String> {
        Binding(
            get: { EditorLauncher.preferred(among: editors, chosen: editorIdentifier)?.bundleIdentifier ?? "" },
            set: { editorIdentifier = $0 }
        )
    }
}

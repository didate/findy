import SwiftUI

/// The menu bar commands of a browser window. They act on the active pane of the key window.
public struct BrowserCommands: Commands {
    @FocusedValue(\.workspace) private var workspace

    public init() {}

    public var body: some Commands {
        CommandGroup(after: .toolbar) {
            Button {
                workspace?.activePane.showsHiddenFiles.toggle()
            } label: {
                Text("Show or Hide Hidden Files", bundle: .module)
            }
            .keyboardShortcut(".", modifiers: [.command, .shift])
            .disabled(workspace == nil)

            Button {
                workspace?.activePane.reload()
            } label: {
                Text("Reload", bundle: .module)
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(workspace == nil)

            Divider()
        }

        CommandMenu(Text("Go", bundle: .module)) {
            Button {
                workspace?.activePane.goBack()
            } label: {
                Text("Back", bundle: .module)
            }
            .keyboardShortcut("[", modifiers: .command)

            Button {
                workspace?.activePane.goForward()
            } label: {
                Text("Forward", bundle: .module)
            }
            .keyboardShortcut("]", modifiers: .command)

            Button {
                workspace?.activePane.goUp()
            } label: {
                Text("Enclosing Folder", bundle: .module)
            }
            .keyboardShortcut(.upArrow, modifiers: .command)

            Divider()

            Button {
                workspace?.activePane.isEditingPath = true
            } label: {
                Text("Go to Folder…", bundle: .module)
            }
            .keyboardShortcut("l", modifiers: .command)
        }
    }
}

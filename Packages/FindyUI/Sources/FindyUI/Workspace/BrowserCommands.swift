import AppKit
import SwiftUI

/// The menu bar commands of a browser window. They act on the active pane of the key window.
public struct BrowserCommands: Commands {
    @FocusedValue(\.workspace) private var workspace

    public init() {}

    /// The text view the user is typing in (a rename field, the path field), if any.
    @MainActor private static var textBeingEdited: NSTextView? {
        NSApp.keyWindow?.firstResponder as? NSTextView
    }

    public var body: some Commands {
        CommandGroup(after: .newItem) {
            Button {
                workspace?.activePane.newFolder()
            } label: {
                Text("New Folder", bundle: .module)
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
            .disabled(workspace == nil)

            Divider()

            Button {
                workspace?.activePane.openSelection()
            } label: {
                Text("Open", bundle: .module)
            }
            .keyboardShortcut("o", modifiers: .command)
            .disabled(workspace == nil)

            Button {
                workspace?.activePane.beginRenamingSelection()
            } label: {
                Text("Rename", bundle: .module)
            }
            .disabled(workspace == nil)

            Button {
                workspace?.activePane.trashSelection()
            } label: {
                Text("Move to Trash", bundle: .module)
            }
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(workspace == nil)
        }

        // Replaces the standard items, which only know about `UndoManager`. File operations are
        // asynchronous and keep their own history; text being edited keeps its own undo.
        CommandGroup(replacing: .undoRedo) {
            Button {
                if let editor = Self.textBeingEdited {
                    editor.undoManager?.undo()
                } else {
                    workspace?.activePane.undo()
                }
            } label: {
                if let name = workspace?.history.undoName {
                    Text("Undo \(name)", bundle: .module)
                } else {
                    Text("Undo", bundle: .module)
                }
            }
            .keyboardShortcut("z", modifiers: .command)
            .disabled(workspace == nil)

            Button {
                if let editor = Self.textBeingEdited {
                    editor.undoManager?.redo()
                } else {
                    workspace?.activePane.redo()
                }
            } label: {
                if let name = workspace?.history.redoName {
                    Text("Redo \(name)", bundle: .module)
                } else {
                    Text("Redo", bundle: .module)
                }
            }
            .keyboardShortcut("z", modifiers: [.command, .shift])
            .disabled(workspace == nil)
        }

        CommandGroup(after: .toolbar) {
            Button {
                workspace?.activePane.showsHiddenFiles.toggle()
            } label: {
                Text("Show or Hide Hidden Files", bundle: .module)
            }
            .keyboardShortcut(".", modifiers: [.command, .shift])
            .disabled(workspace == nil)

            Toggle(
                isOn: Binding(
                    get: { workspace?.calculatesFolderSizes ?? false },
                    set: { workspace?.calculatesFolderSizes = $0 }
                )
            ) {
                Text("Calculate Folder Sizes", bundle: .module)
            }
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

            Button {
                workspace?.activePane.openSelection()
            } label: {
                Text("Open Selection", bundle: .module)
            }
            .keyboardShortcut(.downArrow, modifiers: .command)

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

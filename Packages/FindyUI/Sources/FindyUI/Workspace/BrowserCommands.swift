import AppKit
import SwiftUI

/// The menu bar commands of a browser window. They act on the active pane of the key window.
public struct BrowserCommands: Commands {
    @FocusedValue(\.workspace) private var workspace
    @Environment(\.openWindow) private var openWindow

    public init() {}

    private static func functionKey(_ code: Int) -> KeyEquivalent {
        // The AppKit function key codes are valid Unicode scalars in the private use area.
        KeyEquivalent(Character(UnicodeScalar(UInt16(code)).map(String.init) ?? " "))
    }

    /// The text view the user is typing in (a rename field, the path field), if any.
    @MainActor private static var textBeingEdited: NSTextView? {
        NSApp.keyWindow?.firstResponder as? NSTextView
    }

    public var body: some Commands {
        CommandGroup(after: .newItem) {
            Button {
                // A new tab starts in the folder the user is looking at.
                BrowserWindow.openTab(at: workspace?.activePane.location, with: openWindow)
            } label: {
                Text("New Tab", bundle: .module)
            }
            .keyboardShortcut("t", modifiers: .command)

            Button {
                workspace?.activePane.newFolder()
            } label: {
                Text("New Folder", bundle: .module)
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
            .disabled(workspace == nil)

            Button {
                workspace?.activePane.newFile()
            } label: {
                Text("New File", bundle: .module)
            }
            .keyboardShortcut("n", modifiers: [.command, .option])
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
                // The list that has the focus answers: the preview panel belongs to the view.
                NSApp.sendAction(#selector(FileTableView.toggleQuickLook(_:)), to: nil, from: nil)
            } label: {
                Text("Quick Look", bundle: .module)
            }
            .keyboardShortcut("y", modifiers: .command)
            .disabled(workspace == nil)

            Button {
                workspace?.activePane.openTerminal()
            } label: {
                Text("Open in Terminal", bundle: .module)
            }
            .keyboardShortcut("t", modifiers: [.command, .option])
            .disabled(workspace == nil)

            Button {
                workspace?.activePane.openEditor()
            } label: {
                Text("Open in Editor", bundle: .module)
            }
            .keyboardShortcut("e", modifiers: [.command, .option])
            .disabled(workspace == nil)

            Button {
                if let pane = workspace?.activePane { FavoritesStore.shared.add(pane.foldersForSidebar) }
            } label: {
                Text("Add to Sidebar", bundle: .module)
            }
            // Same shortcut as in Finder.
            .keyboardShortcut("t", modifiers: [.command, .control])
            .disabled(workspace?.activePane.foldersForSidebar.isEmpty != false)

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

            Divider()

            Button {
                workspace?.copySelectionToOtherPane()
            } label: {
                Text("Copy to Other Pane", bundle: .module)
            }
            .keyboardShortcut(Self.functionKey(NSF5FunctionKey), modifiers: [])
            .disabled(workspace?.isDualPane != true)

            Button {
                workspace?.moveSelectionToOtherPane()
            } label: {
                Text("Move to Other Pane", bundle: .module)
            }
            .keyboardShortcut(Self.functionKey(NSF6FunctionKey), modifiers: [])
            .disabled(workspace?.isDualPane != true)
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

        CommandGroup(after: .pasteboard) {
            Button {
                workspace?.activePane.copyPath()
            } label: {
                Text("Copy Path", bundle: .module)
            }
            // Same shortcut as Finder's Copy as Pathname.
            .keyboardShortcut("c", modifiers: [.command, .option])
            .disabled(workspace == nil)
        }

        CommandGroup(after: .toolbar) {
            Button {
                workspace?.toggleDualPane()
            } label: {
                if workspace?.isDualPane == true {
                    Text("Hide Second Pane", bundle: .module)
                } else {
                    Text("Show Second Pane", bundle: .module)
                }
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])
            .disabled(workspace == nil)

            Button {
                workspace?.activePane.showsHiddenFiles.toggle()
            } label: {
                Text("Show or Hide Hidden Files", bundle: .module)
            }
            .keyboardShortcut(".", modifiers: [.command, .shift])
            .disabled(workspace == nil)

            Toggle(
                isOn: Binding(
                    get: { workspace?.activePane.sort.foldersFirst ?? true },
                    set: { workspace?.activePane.sort.foldersFirst = $0 }
                )
            ) {
                Text("Folders First", bundle: .module)
            }
            .disabled(workspace == nil)

            Toggle(
                isOn: Binding(
                    get: { workspace?.activePane.groupsByDate ?? false },
                    set: { workspace?.activePane.groupsByDate = $0 }
                )
            ) {
                Text("Group by Date", bundle: .module)
            }
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

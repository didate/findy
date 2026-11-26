import Foundation

/// Names of the undoable actions, as shown after “Undo” and “Redo” in the Edit menu.
enum ActionName {
    static var newFolder: String { String(localized: "New Folder", bundle: .module) }
    static var newFile: String { String(localized: "New File", bundle: .module) }
    static var colorLabel: String { String(localized: "Color Label", bundle: .module) }
    static var rename: String { String(localized: "Rename", bundle: .module) }
    static var moveToTrash: String { String(localized: "Move to Trash", bundle: .module) }
    static var copy: String { String(localized: "Copy", bundle: .module) }
    static var move: String { String(localized: "Move", bundle: .module) }
}

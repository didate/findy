import Foundation

/// A code editor Findy knows how to open files and folders in.
public struct EditorApp: Identifiable, Hashable, Sendable {
    public let name: String
    public let bundleIdentifier: String

    public var id: String { bundleIdentifier }

    /// The editors Findy looks for, most common first. Each of them opens a folder handed to it
    /// as a project.
    public static let known: [EditorApp] = [
        EditorApp(name: "Visual Studio Code", bundleIdentifier: "com.microsoft.VSCode"),
        EditorApp(name: "Cursor", bundleIdentifier: "com.todesktop.230313mzl4w4u92"),
        EditorApp(name: "Zed", bundleIdentifier: "dev.zed.Zed"),
        EditorApp(name: "Windsurf", bundleIdentifier: "com.exafunction.windsurf"),
        EditorApp(name: "VSCodium", bundleIdentifier: "com.vscodium"),
        EditorApp(name: "Sublime Text", bundleIdentifier: "com.sublimetext.4"),
        EditorApp(name: "Nova", bundleIdentifier: "com.panic.Nova"),
        EditorApp(name: "BBEdit", bundleIdentifier: "com.barebones.bbedit"),
        EditorApp(name: "TextMate", bundleIdentifier: "com.macromates.TextMate"),
        EditorApp(name: "Xcode", bundleIdentifier: "com.apple.dt.Xcode"),
    ]
}

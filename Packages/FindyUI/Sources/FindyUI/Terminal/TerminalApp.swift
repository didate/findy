import Foundation

/// A terminal emulator Findy knows how to open a folder in.
public struct TerminalApp: Identifiable, Hashable, Sendable {
    public let name: String
    public let bundleIdentifier: String

    public var id: String { bundleIdentifier }

    /// Apple's Terminal, present on every Mac. The choice when the user made none.
    public static let terminal = TerminalApp(name: "Terminal", bundleIdentifier: "com.apple.Terminal")

    /// The terminals Findy looks for. Each of them opens a window in a folder it is asked to open.
    public static let known: [TerminalApp] = [
        terminal,
        TerminalApp(name: "iTerm", bundleIdentifier: "com.googlecode.iterm2"),
        TerminalApp(name: "Ghostty", bundleIdentifier: "com.mitchellh.ghostty"),
        TerminalApp(name: "Warp", bundleIdentifier: "dev.warp.Warp-Stable"),
        TerminalApp(name: "kitty", bundleIdentifier: "net.kovidgoyal.kitty"),
        TerminalApp(name: "WezTerm", bundleIdentifier: "com.github.wez.wezterm"),
        TerminalApp(name: "Alacritty", bundleIdentifier: "org.alacritty"),
    ]
}

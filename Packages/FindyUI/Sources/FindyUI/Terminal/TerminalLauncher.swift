import AppKit

/// Opens folders in the user's terminal.
@MainActor
public enum TerminalLauncher {
    /// `UserDefaults` key of the chosen terminal's bundle identifier.
    public static let preferenceKey = "terminalBundleIdentifier"

    enum LaunchError: LocalizedError {
        case notInstalled(String)

        var errorDescription: String? {
            switch self {
            case .notInstalled(let name):
                String(localized: "\(name) is not installed on this Mac.", bundle: .module)
            }
        }
    }

    /// The known terminals that are installed, Apple's Terminal first.
    public static var installed: [TerminalApp] {
        TerminalApp.known.filter {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.bundleIdentifier) != nil
        }
    }

    /// The terminal the user chose, or Apple's Terminal when they chose none.
    public static var preferred: TerminalApp {
        let identifier = UserDefaults.standard.string(forKey: preferenceKey)
        return TerminalApp.known.first { $0.bundleIdentifier == identifier } ?? .terminal
    }

    /// Opens a terminal window whose working directory is `folder`.
    public static func open(_ folder: URL) async throws {
        let terminal = preferred
        guard let application = NSWorkspace.shared.urlForApplication(withBundleIdentifier: terminal.bundleIdentifier)
        else {
            throw LaunchError.notInstalled(terminal.name)
        }
        // Handing a folder to a terminal makes it open a new window there. No script and no
        // Automation permission are involved.
        _ = try await NSWorkspace.shared.open(
            [folder], withApplicationAt: application, configuration: NSWorkspace.OpenConfiguration())
    }
}

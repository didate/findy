import AppKit

/// Opens files and folders in the user's code editor.
@MainActor
public enum EditorLauncher {
    /// `UserDefaults` key of the chosen editor's bundle identifier.
    public static let preferenceKey = "editorBundleIdentifier"

    enum LaunchError: LocalizedError {
        case noEditor

        var errorDescription: String? {
            switch self {
            case .noEditor:
                String(localized: "No code editor Findy knows is installed on this Mac.", bundle: .module)
            }
        }
    }

    /// The known editors that are installed.
    public static var installed: [EditorApp] {
        EditorApp.known.filter {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.bundleIdentifier) != nil
        }
    }

    /// The editor the user chose when it is still installed, the first installed one otherwise.
    public static var preferred: EditorApp? {
        preferred(among: installed, chosen: UserDefaults.standard.string(forKey: preferenceKey))
    }

    static func preferred(among installed: [EditorApp], chosen identifier: String?) -> EditorApp? {
        installed.first { $0.bundleIdentifier == identifier } ?? installed.first
    }

    /// Opens `urls` in the editor: a folder becomes a project window, a file a document.
    public static func open(_ urls: [URL]) async throws {
        guard let editor = preferred,
            let application = NSWorkspace.shared.urlForApplication(withBundleIdentifier: editor.bundleIdentifier)
        else {
            throw LaunchError.noEditor
        }
        _ = try await NSWorkspace.shared.open(
            urls, withApplicationAt: application, configuration: NSWorkspace.OpenConfiguration())
    }
}

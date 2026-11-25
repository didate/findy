import FindyCore
import Foundation
import os

/// The app's one settings database, shared by every window.
enum FolderSettingsDatabase {
    /// `nil` when the database cannot be opened. The app then works without remembering settings,
    /// which is better than not opening folders at all.
    static let shared: (any FolderSettingsStoring)? = {
        do {
            return try SQLiteFolderSettingsStore(url: SQLiteFolderSettingsStore.defaultURL)
        } catch {
            Logger(subsystem: "app.findy.Findy", category: "settings")
                .error("Cannot open the settings database: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }()
}

import Foundation
import Observation

/// The folders the user keeps under Favorites, in their order. A global setting, kept in `UserDefaults`.
///
/// Every window reads the same instance, so a favorite added in one shows up in all of them.
@MainActor
@Observable
public final class FavoritesStore {
    public static let shared = FavoritesStore()

    static let key = "sidebarFavorites"

    public private(set) var urls: [URL]

    private let defaults: UserDefaults

    /// - Parameter home: the folder the first-launch favorites are built from.
    public init(
        defaults: UserDefaults = .standard,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.defaults = defaults
        if let paths = defaults.stringArray(forKey: Self.key) {
            urls = paths.map { URL(filePath: $0, directoryHint: .isDirectory).canonicalLocation }
        } else {
            urls = Self.initialFavorites(home: home)
        }
    }

    /// What the sidebar shows until the user changes it.
    static func initialFavorites(home: URL) -> [URL] {
        [
            home,
            home.appendingPathComponent("Desktop", isDirectory: true),
            home.appendingPathComponent("Documents", isDirectory: true),
            home.appendingPathComponent("Downloads", isDirectory: true),
            URL(filePath: "/Applications", directoryHint: .isDirectory),
        ].map(\.canonicalLocation)
    }

    public func contains(_ url: URL) -> Bool {
        urls.contains(url.canonicalLocation)
    }

    /// Adds the folders that are not favorites yet, at `index` or at the end.
    public func add(_ folders: [URL], at index: Int? = nil) {
        var added: [URL] = []
        for folder in folders.map(\.canonicalLocation) where !urls.contains(folder) && !added.contains(folder) {
            added.append(folder)
        }
        guard !added.isEmpty else { return }
        urls.insert(contentsOf: added, at: min(max(index ?? urls.count, 0), urls.count))
        save()
    }

    /// Removes the entry from the sidebar. The folder itself is not touched.
    public func remove(_ url: URL) {
        let count = urls.count
        urls.removeAll { $0 == url.canonicalLocation }
        if urls.count != count { save() }
    }

    /// Reorders the list; same meaning as the arguments of SwiftUI's `onMove`.
    public func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        let moved = source.map { urls[$0] }
        let insertion = destination - source.filter { $0 < destination }.count
        for index in source.reversed() { urls.remove(at: index) }
        urls.insert(contentsOf: moved, at: insertion)
        save()
    }

    private func save() {
        defaults.set(urls.map(\.path), forKey: Self.key)
    }
}

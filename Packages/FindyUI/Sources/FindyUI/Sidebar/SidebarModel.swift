import FindyCore
import Foundation
import Observation

/// Content of the sidebar: the user's favorites, the cloud storage folders and the mounted volumes.
@MainActor
@Observable
public final class SidebarModel {
    public struct Favorite: Identifiable, Hashable, Sendable {
        public let url: URL
        public let name: String
        public let systemImage: String

        public var id: URL { url }
    }

    public var favorites: [Favorite] { store.urls.map(favorite(for:)) }
    public private(set) var cloudLocations: [Volume] = []
    public private(set) var volumes: [Volume] = []

    private let fileSystem: any FileSystemProviding
    private let store: FavoritesStore
    /// The standard folders, which get a translated name and their own symbol.
    private let wellKnown: [URL: Favorite]

    public init(
        fileSystem: any FileSystemProviding = LocalFileSystem(),
        store: FavoritesStore = .shared,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.fileSystem = fileSystem
        self.store = store

        func folder(_ name: String) -> URL {
            home.appendingPathComponent(name, isDirectory: true).canonicalLocation
        }
        let standard = [
            Favorite(
                url: home.canonicalLocation,
                name: String(localized: "Home", bundle: .module),
                systemImage: "house"),
            Favorite(
                url: folder("Desktop"),
                name: String(localized: "Desktop", bundle: .module),
                systemImage: "menubar.dock.rectangle"),
            Favorite(
                url: folder("Documents"),
                name: String(localized: "Documents", bundle: .module),
                systemImage: "doc"),
            Favorite(
                url: folder("Downloads"),
                name: String(localized: "Downloads", bundle: .module),
                systemImage: "arrow.down.circle"),
            Favorite(
                url: URL(filePath: "/Applications", directoryHint: .isDirectory).canonicalLocation,
                name: String(localized: "Applications", bundle: .module),
                systemImage: "square.grid.2x2"),
        ]
        wellKnown = Dictionary(uniqueKeysWithValues: standard.map { ($0.url, $0) })
    }

    public func loadLocations() async {
        cloudLocations = await fileSystem.cloudLocations()
        volumes = await fileSystem.mountedVolumes()
    }

    /// The symbol of a cloud storage folder: iCloud Drive has its own.
    public func systemImage(forCloudLocation location: Volume) -> String {
        location.url.lastPathComponent == "com~apple~CloudDocs" ? "icloud" : "cloud"
    }

    // MARK: Favorites

    public func isFavorite(_ url: URL) -> Bool {
        store.contains(url)
    }

    /// Adds what was dropped on the list. Only folders can be favorites: files are left out.
    public func addFavorites(_ urls: [URL], at index: Int? = nil) async {
        var folders: [URL] = []
        for url in urls where await fileSystem.isBrowsableFolder(url) {
            folders.append(url)
        }
        store.add(folders, at: index)
    }

    public func removeFavorite(_ url: URL) {
        store.remove(url)
    }

    public func moveFavorites(fromOffsets source: IndexSet, toOffset destination: Int) {
        store.move(fromOffsets: source, toOffset: destination)
    }

    private func favorite(for url: URL) -> Favorite {
        wellKnown[url] ?? Favorite(url: url, name: url.lastPathComponent, systemImage: "folder")
    }
}

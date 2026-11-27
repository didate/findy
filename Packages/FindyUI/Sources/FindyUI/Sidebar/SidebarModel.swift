import AppKit
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
    /// The user's home folder, listed under Locations by its own name, as Finder does. It stays
    /// there even when the Home favorite was removed.
    public let home: Favorite
    public private(set) var cloudLocations: [Volume] = []
    public private(set) var volumes: [Volume] = []
    /// A failure to tell the user about. Cleared when they dismiss it.
    public var alertMessage: String?
    /// The ejection in flight. Internal so tests can await it.
    private(set) var ejectTask: Task<Void, Never>?

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
        self.home = Favorite(url: home.canonicalLocation, name: home.lastPathComponent, systemImage: "house")

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

    /// Reloads the locations each time a volume is plugged in or goes away, for as long as the
    /// caller awaits it.
    public func followVolumes() async {
        await withTaskGroup(of: Void.self) { group in
            for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification] {
                group.addTask { [weak self] in
                    // Only the fact that something changed crosses over: the notification itself
                    // is not sendable.
                    let changes = NSWorkspace.shared.notificationCenter.notifications(named: name).map { _ in () }
                    for await _ in changes {
                        await self?.loadLocations()
                    }
                }
            }
        }
    }

    /// Ejects `volume`. `beforeEjecting` runs first, so the panes can leave the volume: a folder
    /// still shown would keep it busy.
    public func eject(_ volume: Volume, beforeEjecting: @MainActor () -> Void = {}) {
        beforeEjecting()
        ejectTask = Task {
            do {
                try await fileSystem.eject(volume.url)
                await loadLocations()
            } catch {
                alertMessage = error.localizedDescription
            }
        }
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

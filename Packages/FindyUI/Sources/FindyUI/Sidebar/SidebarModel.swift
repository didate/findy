import FindyCore
import Foundation
import Observation

/// Content of the sidebar: fixed favorites and the mounted volumes.
@MainActor
@Observable
public final class SidebarModel {
    public struct Favorite: Identifiable, Hashable, Sendable {
        public let url: URL
        public let name: String
        public let systemImage: String

        public var id: URL { url }
    }

    public let favorites: [Favorite]
    public private(set) var volumes: [Volume] = []

    private let fileSystem: any FileSystemProviding

    public init(fileSystem: any FileSystemProviding = LocalFileSystem()) {
        self.fileSystem = fileSystem

        let home = FileManager.default.homeDirectoryForCurrentUser
        func folder(_ name: String) -> URL {
            home.appendingPathComponent(name, isDirectory: true).canonicalLocation
        }
        favorites = [
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
    }

    public func loadVolumes() async {
        volumes = await fileSystem.mountedVolumes()
    }
}

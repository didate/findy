import FindyCore
import Foundation
import Testing

@testable import FindyUI

private struct FakeLocations: FileSystemProviding {
    var folders: Set<String> = []
    var cloud: [Volume] = []

    func contents(of directory: URL) async throws -> [FileItem] { [] }
    func directorySize(of directory: URL) async throws -> Int64 { 0 }
    func changes(in directory: URL) -> AsyncStream<Void> { AsyncStream { $0.finish() } }
    func mountedVolumes() async -> [Volume] { [Volume(url: URL(fileURLWithPath: "/"), name: "Macintosh HD")] }
    func cloudLocations() async -> [Volume] { cloud }
    func isBrowsableFolder(_ url: URL) async -> Bool { folders.contains(url.path) }
}

@MainActor
@Suite struct SidebarModelTests {
    private let home = URL(fileURLWithPath: "/Users/someone")

    private func withModel(
        _ fileSystem: FakeLocations = FakeLocations(), _ body: (SidebarModel) async -> Void
    ) async throws {
        let name = "FindyUITests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let store = FavoritesStore(defaults: defaults, home: home)
        await body(SidebarModel(fileSystem: fileSystem, store: store, home: home))
    }

    @Test func standardFoldersKeepTheirSymbol() async throws {
        try await withModel { model in
            #expect(model.favorites.map(\.systemImage).first == "house")
            #expect(model.favorites.count == 5)
        }
    }

    @Test func addsOnlyFoldersAndNamesThemAfterTheFolder() async throws {
        let fileSystem = FakeLocations(folders: ["/Work/DHIS2"])
        try await withModel(fileSystem) { model in
            await model.addFavorites(
                [URL(fileURLWithPath: "/Work/DHIS2"), URL(fileURLWithPath: "/Work/report.pdf")], at: 0)

            #expect(model.favorites.count == 6)
            #expect(model.favorites.first?.name == "DHIS2")
            #expect(model.favorites.first?.systemImage == "folder")
            #expect(model.isFavorite(URL(fileURLWithPath: "/Work/DHIS2/")))
        }
    }

    @Test func removingAFavoriteLeavesTheOthers() async throws {
        try await withModel { model in
            model.removeFavorite(home)

            #expect(model.favorites.count == 4)
            #expect(!model.isFavorite(home))
        }
    }

    @Test func listsCloudFoldersAndVolumes() async throws {
        let iCloud = Volume(
            url: URL(fileURLWithPath: "/Users/someone/Library/Mobile Documents/com~apple~CloudDocs"),
            name: "iCloud Drive")
        let drive = Volume(
            url: URL(fileURLWithPath: "/Users/someone/Library/CloudStorage/GoogleDrive-me@example.com"),
            name: "Google Drive")
        try await withModel(FakeLocations(cloud: [iCloud, drive])) { model in
            await model.loadLocations()

            #expect(model.cloudLocations.map(\.name) == ["iCloud Drive", "Google Drive"])
            #expect(model.systemImage(forCloudLocation: iCloud) == "icloud")
            #expect(model.systemImage(forCloudLocation: drive) == "cloud")
            #expect(model.volumes.count == 1)
        }
    }
}

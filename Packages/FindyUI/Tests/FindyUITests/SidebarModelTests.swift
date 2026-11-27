import FindyCore
import Foundation
import Testing

@testable import FindyUI

/// Remembers what was ejected, and can be told to refuse.
private actor EjectLog {
    var ejected: [String] = []
    func record(_ path: String) { ejected.append(path) }
}

private struct FakeLocations: FileSystemProviding {
    struct Busy: LocalizedError {
        var errorDescription: String? { "The volume is in use." }
    }

    var folders: Set<String> = []
    var cloud: [Volume] = []
    var refusesToEject = false
    let log = EjectLog()

    func eject(_ volume: URL) async throws {
        if refusesToEject { throw Busy() }
        await log.record(volume.path)
    }

    func contents(of directory: URL) async throws -> [FileItem] { [] }
    func details(of url: URL) async throws -> FileDetails { FileDetails(url: url, name: url.lastPathComponent) }
    func search(in directory: URL, matching query: String, includingHidden: Bool) -> AsyncStream<[FileItem]> {
        AsyncStream { $0.finish() }
    }
    func items(labeled label: FileLabel) -> AsyncStream<[FileItem]> { AsyncStream { $0.finish() } }
    func directorySize(of directory: URL) async throws -> Int64 { 0 }
    func diskUsage(of directory: URL) -> AsyncThrowingStream<DiskUsageEvent, any Error> {
        AsyncThrowingStream { $0.finish() }
    }
    func changes(in directory: URL) -> AsyncStream<Void> { AsyncStream { $0.finish() } }
    func changes(under root: URL) -> AsyncStream<Void> { AsyncStream { $0.finish() } }

    func mountedVolumes() async -> [Volume] { [Volume(url: URL(fileURLWithPath: "/"), name: "Macintosh HD")] }
    func cloudLocations() async -> [Volume] { cloud }
    func gitInfo(for directory: URL) async -> GitInfo? { nil }
    func gitChanges(inRepositoryAt root: URL) async -> GitChanges? { nil }
    func availableSpace(at directory: URL) async -> Int64? { nil }
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

    @Test func theHomeFolderIsALocationNamedAfterTheUserEvenWithoutItsFavorite() async throws {
        try await withModel { model in
            model.removeFavorite(home)

            #expect(model.favorites.count == 4)
            #expect(model.home.name == "someone")
            #expect(model.home.url == home.canonicalLocation)
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

    @Test func ejectsAVolumeAfterLettingThePanesLeave() async throws {
        let fileSystem = FakeLocations()
        let usb = Volume(url: URL(fileURLWithPath: "/Volumes/USB"), name: "USB", isEjectable: true)
        try await withModel(fileSystem) { model in
            var left = false

            model.eject(usb) { left = true }
            await model.ejectTask?.value

            #expect(left)
            #expect(await fileSystem.log.ejected == ["/Volumes/USB"])
            #expect(model.alertMessage == nil)
        }
    }

    @Test func tellsTheUserWhenAVolumeCannotBeEjected() async throws {
        let usb = Volume(url: URL(fileURLWithPath: "/Volumes/USB"), name: "USB", isEjectable: true)
        try await withModel(FakeLocations(refusesToEject: true)) { model in
            model.eject(usb)
            await model.ejectTask?.value

            #expect(model.alertMessage == "The volume is in use.")
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

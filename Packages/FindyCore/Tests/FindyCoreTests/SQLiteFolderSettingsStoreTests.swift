import Foundation
import Testing

@testable import FindyCore

@Suite struct SQLiteFolderSettingsStoreTests {
    private let documents = URL(fileURLWithPath: "/Users/someone/Documents")
    private let downloads = URL(fileURLWithPath: "/Users/someone/Downloads")

    @Test func returnsNothingForAFolderNeverCustomized() async throws {
        let store = try SQLiteFolderSettingsStore()

        #expect(try await store.settings(for: documents) == nil)
    }

    @Test func savesAndUpdatesSettingsPerFolder() async throws {
        let store = try SQLiteFolderSettingsStore()
        let bySize = FolderSettings(
            sort: FileSort(key: .size, ascending: false, foldersFirst: false), showsHiddenFiles: true)
        let byDate = FolderSettings(sort: FileSort(key: .dateModified), showsHiddenFiles: false)

        try await store.save(bySize, for: documents)
        try await store.save(byDate, for: downloads)
        #expect(try await store.settings(for: documents) == bySize)
        #expect(try await store.settings(for: downloads) == byDate)

        try await store.save(byDate, for: documents)
        #expect(try await store.settings(for: documents) == byDate)
    }

    @Test func aTrailingSlashIsTheSameFolder() async throws {
        let store = try SQLiteFolderSettingsStore()
        let settings = FolderSettings(showsHiddenFiles: true)

        try await store.save(settings, for: URL(filePath: "/Users/someone/Documents/", directoryHint: .isDirectory))

        #expect(try await store.settings(for: documents) == settings)
    }

    @Test func keepsSettingsAcrossLaunches() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FindyCoreTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("nested/findy.sqlite")
        let settings = FolderSettings(sort: FileSort(key: .size, ascending: false), showsHiddenFiles: true)

        try await SQLiteFolderSettingsStore(url: url).save(settings, for: documents)

        let reopened = try SQLiteFolderSettingsStore(url: url)
        #expect(try await reopened.settings(for: documents) == settings)
    }
}

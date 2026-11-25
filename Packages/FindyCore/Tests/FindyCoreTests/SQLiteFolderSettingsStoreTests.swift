import Foundation
import SQLite3
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

    @Test func remembersTheGroupingPerFolder() async throws {
        let store = try SQLiteFolderSettingsStore()
        let grouped = FolderSettings(groupsByDate: true)

        try await store.save(grouped, for: downloads)
        try await store.save(FolderSettings(), for: documents)

        #expect(try await store.settings(for: downloads) == grouped)
        #expect(try await store.settings(for: documents)?.groupsByDate == false)
    }

    @Test func aDatabaseWrittenByVersion01KeepsItsSettings() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FindyCoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("findy.sqlite")
        // The schema and the migration record exactly as 0.1 left them.
        var handle: OpaquePointer?
        #expect(sqlite3_open(url.path, &handle) == SQLITE_OK)
        let script = """
            CREATE TABLE grdb_migrations (identifier TEXT NOT NULL PRIMARY KEY);
            INSERT INTO grdb_migrations VALUES ('v1-folder-settings');
            CREATE TABLE folder_settings (
                path TEXT PRIMARY KEY, sort_key TEXT NOT NULL, ascending BOOLEAN NOT NULL,
                folders_first BOOLEAN NOT NULL, shows_hidden_files BOOLEAN NOT NULL);
            INSERT INTO folder_settings VALUES ('/Users/someone/Documents', 'size', 0, 1, 1);
            """
        #expect(sqlite3_exec(handle, script, nil, nil, nil) == SQLITE_OK)
        sqlite3_close(handle)

        let store = try SQLiteFolderSettingsStore(url: url)

        #expect(
            try await store.settings(for: documents)
                == FolderSettings(sort: FileSort(key: .size, ascending: false), showsHiddenFiles: true))
        try await store.save(FolderSettings(groupsByDate: true), for: documents)
        #expect(try await store.settings(for: documents)?.groupsByDate == true)
    }
}

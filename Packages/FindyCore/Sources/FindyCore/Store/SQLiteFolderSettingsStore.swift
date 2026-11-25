import Foundation
import GRDB

/// Per-folder settings in a SQLite database of Findy's own.
///
/// Nothing is ever written into the folders themselves: no `.DS_Store`, so settings survive on
/// read-only and network volumes and never litter the user's files.
public final class SQLiteFolderSettingsStore: FolderSettingsStoring {
    private let database: DatabaseQueue

    /// Opens, creating it if needed, the database at `url`.
    public init(url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        database = try DatabaseQueue(path: url.path)
        try Self.migrator.migrate(database)
    }

    /// A store that lives in memory and is forgotten with the process.
    public init() throws {
        database = try DatabaseQueue()
        try Self.migrator.migrate(database)
    }

    /// Where the app keeps its database: `~/Library/Application Support/Findy/findy.sqlite`.
    public static var defaultURL: URL {
        URL.applicationSupportDirectory.appendingPathComponent("Findy/findy.sqlite")
    }

    public func settings(for folder: URL) async throws -> FolderSettings? {
        let path = Self.key(for: folder)
        return try await database.read { db in
            let row = try Row.fetchOne(
                db,
                sql: """
                    SELECT sort_key, ascending, folders_first, shows_hidden_files
                    FROM folder_settings WHERE path = ?
                    """,
                arguments: [path])
            guard let row else { return nil }
            let sortKey: String = row["sort_key"]
            return FolderSettings(
                sort: FileSort(
                    // A key written by a newer version falls back to sorting by name.
                    key: FileSort.Key(rawValue: sortKey) ?? .name,
                    ascending: row["ascending"],
                    foldersFirst: row["folders_first"]),
                showsHiddenFiles: row["shows_hidden_files"])
        }
    }

    public func save(_ settings: FolderSettings, for folder: URL) async throws {
        let path = Self.key(for: folder)
        try await database.write { db in
            try db.execute(
                sql: """
                    INSERT INTO folder_settings (path, sort_key, ascending, folders_first, shows_hidden_files)
                    VALUES (?, ?, ?, ?, ?)
                    ON CONFLICT(path) DO UPDATE SET
                        sort_key = excluded.sort_key,
                        ascending = excluded.ascending,
                        folders_first = excluded.folders_first,
                        shows_hidden_files = excluded.shows_hidden_files
                    """,
                arguments: [
                    path, settings.sort.key.rawValue, settings.sort.ascending, settings.sort.foldersFirst,
                    settings.showsHiddenFiles,
                ])
        }
    }

    private static func key(for folder: URL) -> String {
        folder.canonicalLocation.path
    }

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1-folder-settings") { db in
            try db.create(table: "folder_settings") { table in
                table.primaryKey("path", .text)
                table.column("sort_key", .text).notNull()
                table.column("ascending", .boolean).notNull()
                table.column("folders_first", .boolean).notNull()
                table.column("shows_hidden_files", .boolean).notNull()
            }
        }
        return migrator
    }
}

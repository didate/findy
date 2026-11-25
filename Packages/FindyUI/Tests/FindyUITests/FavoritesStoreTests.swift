import Foundation
import Testing

@testable import FindyUI

@MainActor
@Suite struct FavoritesStoreTests {
    private let home = URL(fileURLWithPath: "/Users/someone")

    /// A private defaults domain per test, removed afterwards.
    private func withDefaults(_ body: (UserDefaults) -> Void) throws {
        let name = "FindyUITests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        body(defaults)
    }

    @Test func startsWithTheStandardFolders() throws {
        try withDefaults { defaults in
            let store = FavoritesStore(defaults: defaults, home: home)

            #expect(
                store.urls.map(\.path) == [
                    "/Users/someone", "/Users/someone/Desktop", "/Users/someone/Documents",
                    "/Users/someone/Downloads", "/Applications",
                ])
        }
    }

    @Test func remembersAddedFoldersAcrossLaunches() throws {
        try withDefaults { defaults in
            let store = FavoritesStore(defaults: defaults, home: home)
            store.add([URL(fileURLWithPath: "/Work/DHIS2/"), URL(fileURLWithPath: "/Work/été 🌞")])

            let relaunched = FavoritesStore(defaults: defaults, home: home)

            #expect(relaunched.urls.suffix(2).map(\.path) == ["/Work/DHIS2", "/Work/été 🌞"])
            #expect(relaunched.urls.count == 7)
        }
    }

    @Test func doesNotAddTheSameFolderTwice() throws {
        try withDefaults { defaults in
            let store = FavoritesStore(defaults: defaults, home: home)

            store.add([URL(fileURLWithPath: "/Work"), URL(fileURLWithPath: "/Work/")])
            store.add([URL(fileURLWithPath: "/Applications")])

            #expect(store.urls.count == 6)
            #expect(store.contains(URL(fileURLWithPath: "/Work/")))
        }
    }

    @Test func insertsAtTheRequestedPlace() throws {
        try withDefaults { defaults in
            let store = FavoritesStore(defaults: defaults, home: home)

            store.add([URL(fileURLWithPath: "/Work")], at: 1)
            store.add([URL(fileURLWithPath: "/Far")], at: 99)

            #expect(store.urls[1].path == "/Work")
            #expect(store.urls.last?.path == "/Far")
        }
    }

    @Test func removesAStandardFolderForGood() throws {
        try withDefaults { defaults in
            let store = FavoritesStore(defaults: defaults, home: home)
            store.remove(URL(fileURLWithPath: "/Applications"))

            let relaunched = FavoritesStore(defaults: defaults, home: home)

            #expect(!relaunched.contains(URL(fileURLWithPath: "/Applications")))
            #expect(relaunched.urls.count == 4)
        }
    }

    @Test func keepsAnEmptyListEmpty() throws {
        try withDefaults { defaults in
            let store = FavoritesStore(defaults: defaults, home: home)
            for url in store.urls { store.remove(url) }

            #expect(FavoritesStore(defaults: defaults, home: home).urls.isEmpty)
        }
    }

    @Test func movesEntriesLikeAListDoes() throws {
        try withDefaults { defaults in
            let store = FavoritesStore(defaults: defaults, home: home)

            // Downloads (3) goes to the top, then Home (now 1) goes to the end.
            store.move(fromOffsets: [3], toOffset: 0)
            store.move(fromOffsets: [1], toOffset: 5)

            #expect(
                store.urls.map(\.lastPathComponent) == ["Downloads", "Desktop", "Documents", "Applications", "someone"])
            #expect(FavoritesStore(defaults: defaults, home: home).urls == store.urls)
        }
    }
}

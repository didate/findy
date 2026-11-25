import Foundation
import Testing

@testable import FindyCore

@Suite struct FileSortTests {
    private func file(_ name: String, size: Int64? = 0, date: TimeInterval = 0) -> FileItem {
        FileItem(
            url: URL(fileURLWithPath: "/tmp/\(name)"),
            size: size,
            modificationDate: Date(timeIntervalSince1970: date)
        )
    }

    private func folder(_ name: String, date: TimeInterval = 0) -> FileItem {
        FileItem(
            url: URL(fileURLWithPath: "/tmp/\(name)"),
            isDirectory: true,
            modificationDate: Date(timeIntervalSince1970: date)
        )
    }

    @Test func sortsNamesTheWayFinderDoes() {
        let items = [file("file10.txt"), file("File2.txt"), file("file1.txt")]

        let sorted = FileSort().sorted(items)

        #expect(sorted.map(\.name) == ["file1.txt", "File2.txt", "file10.txt"])
    }

    @Test func keepsFoldersOnTopInBothDirections() {
        let items = [file("a.txt"), folder("Zed"), file("b.txt"), folder("Alpha")]

        let ascending = FileSort(ascending: true).sorted(items)
        let descending = FileSort(ascending: false).sorted(items)

        #expect(ascending.map(\.name) == ["Alpha", "Zed", "a.txt", "b.txt"])
        #expect(descending.map(\.name) == ["Zed", "Alpha", "b.txt", "a.txt"])
    }

    @Test func mixesFoldersAndFilesWhenFoldersFirstIsOff() {
        let items = [file("b.txt"), folder("Alpha"), folder("Zed"), file("a.txt")]

        let sorted = FileSort(foldersFirst: false).sorted(items)

        #expect(sorted.map(\.name) == ["a.txt", "Alpha", "b.txt", "Zed"])
    }

    @Test func sortsBySizeAndBreaksTiesByName() {
        let items = [file("big", size: 300), file("b-small", size: 10), file("a-small", size: 10)]

        let ascending = FileSort(key: .size).sorted(items)
        let descending = FileSort(key: .size, ascending: false).sorted(items)

        #expect(ascending.map(\.name) == ["a-small", "b-small", "big"])
        #expect(descending.map(\.name) == ["big", "a-small", "b-small"])
    }

    @Test func sortsByModificationDate() {
        let items = [file("new", date: 300), file("old", date: 100), file("mid", date: 200)]

        let sorted = FileSort(key: .dateModified, ascending: false).sorted(items)

        #expect(sorted.map(\.name) == ["new", "mid", "old"])
    }
}

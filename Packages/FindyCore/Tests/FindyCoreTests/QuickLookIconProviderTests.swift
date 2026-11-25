import Foundation
import Testing

@testable import FindyCore

@Suite struct QuickLookIconProviderTests {
    @Test func producesAnIconAtTheRequestedPixelSize() async throws {
        // An app that ships with every Mac, so the test needs no fixture.
        let app = URL(fileURLWithPath: "/System/Applications/Calculator.app")

        let icon = try #require(await QuickLookIconProvider().icon(for: app, pointSize: 18, scale: 2))

        #expect(max(icon.width, icon.height) == 36)
    }

    @Test func producesAnIconForAPlainFileAndAFolder() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FindyCoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("notes.txt")
        try Data("hello".utf8).write(to: file)

        #expect(await QuickLookIconProvider().icon(for: file, pointSize: 18, scale: 1) != nil)
        #expect(await QuickLookIconProvider().icon(for: directory, pointSize: 18, scale: 1) != nil)
    }
}

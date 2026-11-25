import Foundation
import Testing

@testable import FindyCore

@Suite struct URLLocationTests {
    @Test func ignoresTrailingSlash() {
        let withSlash = URL(filePath: "/Users/me/Documents/", directoryHint: .isDirectory)
        let withoutSlash = URL(filePath: "/Users/me/Documents", directoryHint: .notDirectory)

        #expect(withSlash != withoutSlash)
        #expect(withSlash.canonicalLocation == withoutSlash.canonicalLocation)
        #expect(withSlash.canonicalLocation.path == "/Users/me/Documents")
    }

    @Test func resolvesDotSegments() {
        let url = URL(filePath: "/Users/me/Documents/../Desktop/./a", directoryHint: .notDirectory)

        #expect(url.canonicalLocation.path == "/Users/me/Desktop/a")
    }

    @Test func keepsTheRoot() {
        #expect(URL(filePath: "/", directoryHint: .isDirectory).canonicalLocation.path == "/")
    }
}

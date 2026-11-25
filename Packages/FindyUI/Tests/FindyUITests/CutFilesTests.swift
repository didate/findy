import Foundation
import Testing

@testable import FindyUI

@MainActor
@Suite struct CutFilesTests {
    private let file = URL(fileURLWithPath: "/fake/a.txt")

    @Test func filesStayCutWhileTheClipboardHoldsThem() {
        let cut = CutFiles()

        cut.set([file], changeCount: 7)

        #expect(cut.current(clipboardChangeCount: 7) == [file])
    }

    @Test func aLaterCopyAnywhereEndsTheCut() {
        let cut = CutFiles()
        cut.set([file], changeCount: 7)

        #expect(cut.current(clipboardChangeCount: 8).isEmpty)
    }

    @Test func clearingForgetsTheFiles() {
        let cut = CutFiles()
        cut.set([file], changeCount: 7)

        cut.clear()

        #expect(cut.current(clipboardChangeCount: 7).isEmpty)
    }
}

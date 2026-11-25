import Foundation
import Testing

@testable import FindyCore

@Suite struct GitRepositoryTests {
    /// Creates a scratch directory, runs `body`, then removes it.
    private func withScratchDirectory(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FindyCoreTests-\(UUID().uuidString)", isDirectory: true)
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory)
    }

    private func makeRepository(at root: URL, head: String) throws {
        let git = root.appendingPathComponent(".git")
        try FileManager.default.createDirectory(at: git, withIntermediateDirectories: true)
        try Data(head.utf8).write(to: git.appendingPathComponent("HEAD"))
    }

    @Test func readsTheBranchAtTheRootAndInSubfolders() throws {
        try withScratchDirectory { root in
            try makeRepository(at: root, head: "ref: refs/heads/feat/été-🌞\n")
            let deep = root.appendingPathComponent("Sources/App", isDirectory: true)
            try FileManager.default.createDirectory(at: deep, withIntermediateDirectories: true)

            let atRoot = GitRepository.info(for: root)
            let below = GitRepository.info(for: deep)

            #expect(atRoot?.head == "feat/été-🌞")
            #expect(atRoot?.isDetached == false)
            #expect(below?.head == "feat/été-🌞")
            #expect(below?.root.path == root.path)
            #expect(below?.gitDirectory.lastPathComponent == ".git")
        }
    }

    @Test func aDetachedHeadShowsTheShortHash() throws {
        try withScratchDirectory { root in
            try makeRepository(at: root, head: "0bce7cb1f2a3b4c5d6e7f8091a2b3c4d5e6f7081\n")

            let info = GitRepository.info(for: root)

            #expect(info?.head == "0bce7cb")
            #expect(info?.isDetached == true)
        }
    }

    @Test func aLinkedWorktreeFollowsItsGitFile() throws {
        try withScratchDirectory { root in
            let main = root.appendingPathComponent("main", isDirectory: true)
            try makeRepository(at: main, head: "ref: refs/heads/main\n")
            let linkedGit = main.appendingPathComponent(".git/worktrees/fix", isDirectory: true)
            try FileManager.default.createDirectory(at: linkedGit, withIntermediateDirectories: true)
            try Data("ref: refs/heads/fix/crash\n".utf8).write(to: linkedGit.appendingPathComponent("HEAD"))
            let worktree = root.appendingPathComponent("fix", isDirectory: true)
            try FileManager.default.createDirectory(at: worktree, withIntermediateDirectories: true)
            // Relative, as Git writes it with `worktree.useRelativePaths`.
            try Data("gitdir: ../main/.git/worktrees/fix\n".utf8).write(to: worktree.appendingPathComponent(".git"))

            let info = GitRepository.info(for: worktree)

            #expect(info?.head == "fix/crash")
            #expect(info?.root.path == worktree.path)
            #expect(info?.gitDirectory.path == linkedGit.path)
        }
    }

    @Test func aFolderOutsideAnyRepositoryHasNoInfo() throws {
        try withScratchDirectory { root in
            #expect(GitRepository.info(for: root) == nil)
        }
    }

    @Test func aBrokenRepositoryIsIgnored() throws {
        try withScratchDirectory { root in
            try makeRepository(at: root, head: "")
            let odd = root.appendingPathComponent("odd", isDirectory: true)
            try FileManager.default.createDirectory(at: odd, withIntermediateDirectories: true)
            try Data("not a git file".utf8).write(to: odd.appendingPathComponent(".git"))

            #expect(GitRepository.info(for: root) == nil)
            #expect(GitRepository.info(for: odd) == nil)
        }
    }

    @Test func reportsTheSpaceLeftOnTheVolume() async throws {
        let space = await LocalFileSystem().availableSpace(at: FileManager.default.temporaryDirectory)

        #expect((space ?? 0) > 0)
    }

    @Test func readsChangesStatesAndCommitsAheadAndBehind() {
        let status =
            [
                "# branch.oid 0bce7cb1f2a3b4c5d6e7f8091a2b3c4d5e6f7081",
                "# branch.head main",
                "# branch.upstream origin/main",
                "# branch.ab +2 -1",
                "1 .M N... 100644 100644 100644 aaa bbb README.md",
                "1 A. N... 000000 100644 100644 aaa bbb src/deep/new file.swift",
                "1 .D N... 100644 100644 000000 aaa bbb gone.txt",
                "2 R. N... 100644 100644 100644 aaa bbb R100 new name.txt",
                "1 old name.txt",
                "u UU N... 100644 100644 100644 100644 aaa bbb ccc conflict.txt",
                "? été 🌞/",
                "! build/",
            ].joined(separator: "\0") + "\0"

        let changes = GitStatusReader.parse(status)

        #expect(changes.changedFiles == 6)
        #expect(changes.ahead == 2)
        #expect(changes.behind == 1)
        #expect(changes.state(forRelativePath: "README.md") == .modified)
        #expect(changes.state(forRelativePath: "src/deep/new file.swift") == .added)
        #expect(changes.state(forRelativePath: "gone.txt") == .deleted)
        #expect(changes.state(forRelativePath: "new name.txt") == .renamed)
        // The old path of a rename is not an entry of its own, even when it looks like one.
        #expect(changes.state(forRelativePath: "old name.txt") == nil)
        #expect(changes.state(forRelativePath: "conflict.txt") == .conflicted)
        #expect(changes.state(forRelativePath: "LICENSE") == nil)
    }

    @Test func foldersTellWhatIsBelowThem() {
        let changes = GitChanges(
            changedFiles: 2,
            states: ["src/deep/a.swift": .modified, "new/": .untracked, "build/": .ignored, "docs/out/": .ignored])

        #expect(changes.state(forRelativePath: "src") == .containsChanges)
        #expect(changes.state(forRelativePath: "src/deep") == .containsChanges)
        #expect(changes.state(forRelativePath: "src/other.swift") == nil)
        // What is inside an untracked or ignored folder shares its state.
        #expect(changes.state(forRelativePath: "new") == .untracked)
        #expect(changes.state(forRelativePath: "new/sub/file.txt") == .untracked)
        #expect(changes.state(forRelativePath: "build/Debug/app") == .ignored)
        // An ignored folder does not make its parent look changed.
        #expect(changes.state(forRelativePath: "docs") == nil)
    }

    @Test func matchesNamesWhateverTheirUnicodeForm() {
        let composed = "caf\u{E9}.txt"
        let decomposed = "cafe\u{301}.txt"
        let changes = GitChanges(changedFiles: 1, states: [composed: .modified])

        #expect(changes.state(forRelativePath: decomposed) == .modified)
    }

    @Test func aBranchWithoutUpstreamHasNoAheadOrBehind() {
        let changes = GitStatusReader.parse("# branch.oid (initial)\0# branch.head main\0")

        #expect(changes == GitChanges(changedFiles: 0))
    }

    @Test func asksGitAboutARealRepository() async throws {
        // Skipped on a Mac without Git: there is nothing to ask.
        guard let git = GitStatusReader.candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) })
        else { return }
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FindyCoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let initialize = Process()
        initialize.executableURL = URL(filePath: git)
        initialize.arguments = ["-C", root.path, "init", "--quiet"]
        try initialize.run()
        initialize.waitUntilExit()
        try Data().write(to: root.appendingPathComponent("new file.txt"))
        try Data().write(to: root.appendingPathComponent("other.txt"))

        let changes = await LocalFileSystem().gitChanges(inRepositoryAt: root)
        let outside = await LocalFileSystem().gitChanges(inRepositoryAt: URL(filePath: "/"))

        #expect(changes?.changedFiles == 2)
        #expect(changes?.state(forRelativePath: "new file.txt") == .untracked)
        #expect(outside == nil)
    }
}

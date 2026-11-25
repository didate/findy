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
}

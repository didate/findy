import Foundation

/// Asks `git status` what changed in a working tree.
///
/// Unlike the branch, this cannot be read from a file: Git has to compare the tree with its index.
enum GitStatusReader {
    /// Where a real `git` can be. `/usr/bin/git` is left out on purpose: on a Mac without the
    /// developer tools it is a stub that pops up an installation dialog (seen on macOS 26.3).
    static let candidates = [
        "/Applications/Xcode.app/Contents/Developer/usr/bin/git",
        "/Library/Developer/CommandLineTools/usr/bin/git",
        "/opt/homebrew/bin/git",
        "/usr/local/bin/git",
    ]

    /// Holds the process so the cancellation handler, which runs on another thread, can stop it.
    /// Safe: `terminate()` is the only call made from there, and `Process` allows it from any thread.
    private final class Running: @unchecked Sendable {
        let process = Process()
    }

    static func changes(inRepositoryAt root: URL) async -> GitChanges? {
        guard let git = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            return nil
        }
        let running = Running()
        let output = Pipe()
        running.process.executableURL = URL(filePath: git)
        // `--no-optional-locks`: a plain `git status` rewrites the index, which would get in the
        // way of the user's own Git commands and wake up whoever watches the repository, Findy included.
        running.process.arguments = [
            "--no-optional-locks", "-C", root.path, "status", "--porcelain=v2", "--branch",
        ]
        running.process.standardOutput = output
        running.process.standardError = FileHandle.nullDevice
        running.process.standardInput = FileHandle.nullDevice

        return await withTaskCancellationHandler {
            do {
                try running.process.run()
            } catch {
                return nil
            }
            // Read before waiting: a full pipe would block Git forever.
            let data = output.fileHandleForReading.readDataToEndOfFile()
            running.process.waitUntilExit()
            guard !Task.isCancelled, running.process.terminationStatus == 0 else { return nil }
            return parse(String(decoding: data, as: UTF8.self))
        } onCancel: {
            if running.process.isRunning { running.process.terminate() }
        }
    }

    /// Porcelain v2: `# branch.ab +<ahead> -<behind>` when there is an upstream, then one line
    /// per changed path, starting with `1`, `2` (renamed), `u` (conflict) or `?` (untracked).
    static func parse(_ status: String) -> GitChanges {
        var changed = 0
        var ahead: Int?
        var behind: Int?
        for line in status.split(whereSeparator: \.isNewline) {
            if line.hasPrefix("# branch.ab ") {
                let counts = line.dropFirst("# branch.ab ".count).split(separator: " ")
                if counts.count == 2 {
                    ahead = Int(counts[0].dropFirst())
                    behind = Int(counts[1].dropFirst())
                }
            } else if line.hasPrefix("1 ") || line.hasPrefix("2 ") || line.hasPrefix("u ") || line.hasPrefix("? ") {
                changed += 1
            }
        }
        return GitChanges(changedFiles: changed, ahead: ahead, behind: behind)
    }
}

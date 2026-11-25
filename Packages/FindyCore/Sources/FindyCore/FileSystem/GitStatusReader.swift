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
            "--no-optional-locks", "-C", root.path, "status", "--porcelain=v2", "--branch", "--ignored", "-z",
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

    /// Porcelain v2 with `-z`: records end with NUL and paths are given as they are, unquoted.
    /// `# branch.ab +<ahead> -<behind>` appears when there is an upstream. Then one record per
    /// path: `1` (changed), `2` (renamed, followed by one more record holding the old path),
    /// `u` (conflict), `?` (untracked) or `!` (ignored).
    static func parse(_ status: String) -> GitChanges {
        var changed = 0
        var ahead: Int?
        var behind: Int?
        var states: [String: GitFileState] = [:]
        var records = status.split(separator: "\0", omittingEmptySubsequences: true).makeIterator()
        while let record = records.next() {
            if record.hasPrefix("# branch.ab ") {
                let counts = record.dropFirst("# branch.ab ".count).split(separator: " ")
                if counts.count == 2 {
                    ahead = Int(counts[0].dropFirst())
                    behind = Int(counts[1].dropFirst())
                }
            } else if record.hasPrefix("1 ") || record.hasPrefix("2 ") {
                let isRename = record.hasPrefix("2 ")
                // The path comes last and may contain spaces: only the fields before it are split.
                let fields = record.split(separator: " ", maxSplits: isRename ? 9 : 8)
                if isRename { _ = records.next() }
                guard fields.count == (isRename ? 10 : 9), let path = fields.last else { continue }
                let codes = fields[1]
                let state: GitFileState =
                    if isRename {
                        .renamed
                    } else if codes.contains("D") {
                        .deleted
                    } else if codes.hasPrefix("A") {
                        .added
                    } else {
                        .modified
                    }
                states[String(path)] = state
                changed += 1
            } else if record.hasPrefix("u ") {
                let fields = record.split(separator: " ", maxSplits: 10)
                guard fields.count == 11, let path = fields.last else { continue }
                states[String(path)] = .conflicted
                changed += 1
            } else if record.hasPrefix("? ") {
                states[String(record.dropFirst(2))] = .untracked
                changed += 1
            } else if record.hasPrefix("! ") {
                states[String(record.dropFirst(2))] = .ignored
            }
        }
        return GitChanges(changedFiles: changed, ahead: ahead, behind: behind, states: states)
    }
}

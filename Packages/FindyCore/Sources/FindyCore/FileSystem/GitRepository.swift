import Foundation

/// Reads the state of a Git repository straight from its files.
///
/// No `git` process is started: reading `HEAD` takes microseconds, works when the command line
/// tools are not installed, and never runs a hook or a configured helper.
enum GitRepository {
    /// Finds the repository `directory` is in, looking at the folder itself, then at each parent.
    static func info(for directory: URL) -> GitInfo? {
        var folder = directory.standardizedFileURL
        while true {
            let marker = folder.appendingPathComponent(".git")
            if let gitDirectory = gitDirectory(at: marker, in: folder),
                let head = try? String(contentsOf: gitDirectory.appendingPathComponent("HEAD"), encoding: .utf8)
            {
                return parse(head: head, root: folder, gitDirectory: gitDirectory)
            }
            if folder.path == "/" { return nil }
            folder = folder.deletingLastPathComponent()
        }
    }

    /// `.git` is a folder in a normal clone. In a linked worktree or a submodule it is a one-line
    /// file, `gitdir: <path>`, where the path may be relative to the working tree.
    private static func gitDirectory(at marker: URL, in folder: URL) -> URL? {
        guard let values = try? marker.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey]) else {
            return nil
        }
        if values.isDirectory == true { return marker }
        guard values.isRegularFile == true,
            let text = try? String(contentsOf: marker, encoding: .utf8),
            let line = text.split(whereSeparator: \.isNewline).first,
            line.hasPrefix("gitdir:")
        else { return nil }
        let path = line.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespaces)
        guard !path.isEmpty else { return nil }
        return URL(filePath: path, directoryHint: .isDirectory, relativeTo: folder).standardizedFileURL
    }

    /// `HEAD` holds `ref: refs/heads/<branch>` on a branch, and a bare commit hash otherwise.
    static func parse(head: String, root: URL, gitDirectory: URL) -> GitInfo? {
        let line = head.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return nil }
        if line.hasPrefix("ref:") {
            let reference = line.dropFirst("ref:".count).trimmingCharacters(in: .whitespaces)
            let prefix = "refs/heads/"
            let branch = reference.hasPrefix(prefix) ? String(reference.dropFirst(prefix.count)) : reference
            guard !branch.isEmpty else { return nil }
            return GitInfo(head: branch, isDetached: false, root: root, gitDirectory: gitDirectory)
        }
        return GitInfo(head: String(line.prefix(7)), isDetached: true, root: root, gitDirectory: gitDirectory)
    }
}

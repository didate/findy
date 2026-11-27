import Foundation

/// Measures the space a folder takes on disk and what takes it, level by level.
///
/// Sizes are those allocated on the volume, not the logical ones: a cloud-only file counts for
/// nothing, since it takes nothing. Symbolic links are never followed. Other volumes mounted
/// inside the folder are left out, and so are cloud folders whose listing is not on this Mac:
/// reading them would download it.
///
/// Known limits: a file with several hard links is counted once per link, and APFS clones are
/// counted in full although they share their blocks.
enum DiskUsageScanner {
    /// How many files of one folder are listed by name. The rest are counted together: a folder of
    /// 100,000 small files would otherwise cost more memory than it is worth showing.
    static let listedFilesPerFolder = 64

    // Fetched in bulk with each listing: no `stat` per file.
    private static let keys: [URLResourceKey] = [
        .isDirectoryKey, .isVolumeKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey,
    ]
    private static let keySet = Set(keys)

    /// Running totals, reported every few thousand files.
    private struct Progress {
        var files = 0
        var bytes: Int64 = 0
        var reported = 0
    }

    /// Scans `directory`, calling `report` as results come. Stops early, without error, when the
    /// task is cancelled. Throws only when `directory` itself cannot be listed.
    static func scan(_ directory: URL, report: (DiskUsageEvent) -> Void) throws {
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: keys, options: [])
        var progress = Progress()
        var folders: [URL] = []
        var files: [DiskUsageNode] = []
        for url in urls {
            switch classify(url) {
            case .folder: folders.append(url)
            case .file(let size):
                files.append(DiskUsageNode(name: url.lastPathComponent, kind: .file, size: size))
                progress.files += 1
                progress.bytes += size
            case .skipped: break
            }
        }
        for node in listed(files) { report(.entry(node)) }
        report(.progress(files: progress.files, bytes: progress.bytes))

        var unreadable = 0
        for url in folders {
            if Task.isCancelled { return }
            if let node = folder(at: url, progress: &progress, report: report) {
                report(.entry(node))
            } else {
                unreadable += 1
            }
            report(.progress(files: progress.files, bytes: progress.bytes))
        }
        if unreadable > 0 { report(.unreadable(unreadable)) }
    }

    /// The whole tree under `url`. `nil` when the folder cannot be listed.
    private static func folder(
        at url: URL, progress: inout Progress, report: (DiskUsageEvent) -> Void
    ) -> DiskUsageNode? {
        guard
            let urls = try? FileManager.default.contentsOfDirectory(
                at: url, includingPropertiesForKeys: keys, options: [])
        else { return nil }
        var children: [DiskUsageNode] = []
        var files: [DiskUsageNode] = []
        var unreadable = 0
        for child in urls {
            switch classify(child) {
            case .folder:
                // Once cancelled, nothing more is read: the caller drops what was gathered.
                if Task.isCancelled { continue }
                if let node = folder(at: child, progress: &progress, report: report) {
                    children.append(node)
                } else {
                    unreadable += 1
                }
            case .file(let size):
                files.append(DiskUsageNode(name: child.lastPathComponent, kind: .file, size: size))
                progress.files += 1
                progress.bytes += size
            case .skipped: break
            }
        }
        if progress.files - progress.reported >= 2000 {
            progress.reported = progress.files
            report(.progress(files: progress.files, bytes: progress.bytes))
        }
        children.append(contentsOf: listed(files))
        return .folder(named: url.lastPathComponent, children: children, unreadableCount: unreadable)
    }

    private enum Entry {
        case folder
        case file(Int64)
        case skipped
    }

    private static func classify(_ url: URL) -> Entry {
        guard let values = try? url.resourceValues(forKeys: keySet) else { return .skipped }
        // `isDirectory` is false for a symbolic link, whatever it points to: links are files here.
        guard values.isDirectory == true else {
            return .file(Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0))
        }
        // Another volume mounted here takes no space on this one. It also keeps a scan of "/"
        // from counting the data volume twice, once through /System/Volumes/Data.
        if values.isVolume == true { return .skipped }
        return isDataless(url) ? .skipped : .folder
    }

    /// Whether `url` is a cloud folder whose listing is not on this Mac. One `lstat` per folder,
    /// not per file: no resource key exposes this flag.
    private static func isDataless(_ url: URL) -> Bool {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { return false }
        return info.st_flags & UInt32(SF_DATALESS) != 0
    }

    /// The largest files by name, and one entry standing for all the others.
    static func listed(_ files: [DiskUsageNode]) -> [DiskUsageNode] {
        guard files.count > listedFilesPerFolder else { return files }
        let sorted = files.sorted(by: DiskUsageNode.largestFirst)
        let rest = sorted[listedFilesPerFolder...]
        return sorted.prefix(listedFilesPerFolder)
            + [
                DiskUsageNode(
                    name: "", kind: .smallerFiles, size: rest.reduce(0) { $0 + $1.size }, fileCount: rest.count)
            ]
    }
}

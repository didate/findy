import FindyCore
import Foundation
import Observation

/// What the Disk Usage sheet shows: the space a folder takes, and what takes it, level by level.
///
/// The folder is scanned once. Going down into a subfolder, or back up, reads what the scan
/// already found: nothing touches the disk again until `scan()` is called anew.
@MainActor
@Observable
public final class DiskUsageModel {
    /// The folder the sheet was opened on.
    public let root: URL
    /// Everything found so far under `root`.
    public private(set) var tree: DiskUsageNode
    /// The names leading from `root` down to the folder shown. Empty at the top.
    public private(set) var path: [String] = []
    public private(set) var isScanning = false
    /// Files counted so far, for the progress line.
    public private(set) var scannedFiles = 0
    /// Why `root` could not be read at all.
    public private(set) var errorMessage: String?
    /// A failure to tell the user about. Cleared when they dismiss it.
    public var alertMessage: String?
    /// True once something went to the Trash from here: the space is not free yet.
    public private(set) var hasTrashed = false

    private let fileSystem: any FileSystemProviding
    /// Moves one entry to the Trash, undoably. Returns what went wrong, or `nil`.
    private let trash: @MainActor (URL) async -> String?

    public init(
        root: URL,
        fileSystem: any FileSystemProviding = LocalFileSystem(),
        trash: @escaping @MainActor (URL) async -> String?
    ) {
        self.root = root
        self.fileSystem = fileSystem
        self.trash = trash
        tree = .folder(named: root.lastPathComponent, children: [])
    }

    /// The folder whose content is listed: `root`, or the subfolder the user went down into.
    public var shown: DiskUsageNode {
        tree.descendant(at: path) ?? tree
    }

    /// The names of the folders from `root` to the one shown, `root` included.
    public var breadcrumb: [String] {
        [root.lastPathComponent.isEmpty ? root.path : root.lastPathComponent] + path
    }

    public var canGoUp: Bool { !path.isEmpty }

    /// Where `node`, an entry of the folder shown, is on disk. `nil` for the small files counted
    /// together, which are no single entry.
    public func url(of node: DiskUsageNode) -> URL? {
        guard node.kind != .smallerFiles else { return nil }
        return shownURL.appendingPathComponent(node.name, isDirectory: node.kind == .folder)
    }

    /// The folder shown, on disk.
    public var shownURL: URL {
        path.reduce(root) { $0.appendingPathComponent($1, isDirectory: true) }
    }

    /// The part of the folder shown that `node` takes, from 0 to 1.
    public func share(of node: DiskUsageNode) -> Double {
        let total = shown.size
        return total > 0 ? Double(node.size) / Double(total) : 0
    }

    // MARK: Moving around

    /// Goes down into `node` when it is a folder of the folder shown.
    public func open(_ node: DiskUsageNode) {
        guard node.kind == .folder, shown.children.contains(where: { $0.id == node.id }) else { return }
        path.append(node.name)
    }

    public func goUp() {
        guard canGoUp else { return }
        path.removeLast()
    }

    /// Goes back to a level of the breadcrumb: 0 is `root`.
    public func go(toLevel level: Int) {
        guard level >= 0, level < path.count else { return }
        path.removeLast(path.count - level)
    }

    // MARK: Scanning

    /// Scans `root` from scratch. Runs until the scan ends; cancelled with the caller's task.
    public func scan() async {
        tree = .folder(named: root.lastPathComponent, children: [])
        scannedFiles = 0
        errorMessage = nil
        isScanning = true
        defer { isScanning = false }

        var entries: [DiskUsageNode] = []
        var unreadable = 0
        do {
            for try await event in fileSystem.diskUsage(of: root) {
                switch event {
                case .progress(let files, _):
                    scannedFiles = files
                case .entry(let node):
                    entries.append(node)
                    tree = .folder(named: root.lastPathComponent, children: entries, unreadableCount: unreadable)
                case .unreadable(let count):
                    unreadable = count
                    tree = .folder(named: root.lastPathComponent, children: entries, unreadableCount: unreadable)
                }
            }
        } catch {
            if !Task.isCancelled { errorMessage = error.localizedDescription }
        }
        // The folder shown may be gone from a new scan.
        while !path.isEmpty, tree.descendant(at: path)?.kind != .folder { path.removeLast() }
    }

    // MARK: Freeing space

    /// Moves `node`, an entry of the folder shown, to the Trash, and takes it out of the figures.
    public func moveToTrash(_ node: DiskUsageNode) async {
        guard let url = url(of: node) else { return }
        let target = path + [node.name]
        if let failure = await trash(url) {
            alertMessage = failure
            return
        }
        tree = tree.removing(at: target)
        hasTrashed = true
    }
}

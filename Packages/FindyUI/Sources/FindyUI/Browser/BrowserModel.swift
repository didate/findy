import AppKit
import FindyCore
import Foundation
import Observation

/// State of one browser pane: where it is, what it shows, and its navigation history.
@MainActor
@Observable
public final class BrowserModel: Identifiable {
    public nonisolated let id = UUID()

    public private(set) var location: URL
    /// The entries to display, already filtered and sorted.
    public private(set) var items: [FileItem] = []
    public private(set) var isLoading = false
    /// Why the current location could not be listed, if it could not.
    public private(set) var errorMessage: String?

    public var sort = FileSort() {
        didSet { if sort != oldValue { rebuildItems() } }
    }

    public var showsHiddenFiles = false {
        didSet { if showsHiddenFiles != oldValue { rebuildItems() } }
    }

    /// Text typed in the list. Only entries whose name contains it are shown.
    public var filterText = "" {
        didSet { if filterText != oldValue { rebuildItems() } }
    }

    /// The selected entries, by location. Always a subset of `items`.
    public var selection: Set<URL> = []

    public var selectedItems: [FileItem] {
        items.filter { selection.contains($0.url) }
    }

    /// Whether the size of each folder is computed in the background and shown in the list.
    public var calculatesFolderSizes: Bool {
        didSet {
            guard calculatesFolderSizes != oldValue else { return }
            if calculatesFolderSizes {
                needsFullSizing = true
                startSizing()
            } else {
                sizeTask?.cancel()
                sizeTask = nil
            }
            rebuildItems()
        }
    }

    /// The entry being renamed in the list, if any.
    public var renamingURL: URL?

    /// A copy or move waiting for the user to settle name conflicts.
    public var pendingTransfer: PendingTransfer?

    /// A failure to tell the user about. Cleared when they dismiss it.
    public var alertMessage: String?

    /// True while an operation on files is running.
    public internal(set) var isBusy = false

    /// Whether the path bar is a text field right now.
    public var isEditingPath = false

    public private(set) var canGoBack = false
    public private(set) var canGoForward = false

    public var canGoUp: Bool { location.path != "/" }

    public var title: String {
        location.path == "/" ? "/" : location.lastPathComponent
    }

    /// The location split into segments, from the root down.
    public var crumbs: [PathCrumb] {
        var url = URL(filePath: "/", directoryHint: .isDirectory).canonicalLocation
        var result = [PathCrumb(name: "/", url: url)]
        for component in location.pathComponents.dropFirst() {
            url = url.appendingPathComponent(component).canonicalLocation
            result.append(PathCrumb(name: component, url: url))
        }
        return result
    }

    let fileSystem: any FileSystemProviding
    let operations: any FileOperating
    /// Shared by the panes of a window, so Undo reverts the last action wherever it was made.
    public let history: UndoHistory
    /// The operation in flight. Internal so tests can await it.
    var operationTask: Task<Void, Never>?
    /// Names to select once the next listing shows them (a new folder, a renamed file…).
    /// Names, not URLs: the system spells the same folder `/var/…` or `/private/var/…` depending
    /// on who is asked, and the two do not compare equal.
    var selectAfterLoad: Set<String>?
    /// Name of the entry to start renaming once the next listing shows it.
    var renameAfterLoad: String?
    private let openFiles: @MainActor ([URL]) -> Void
    private var allItems: [FileItem] = []
    private var backStack: [URL] = [] {
        didSet { canGoBack = !backStack.isEmpty }
    }
    private var forwardStack: [URL] = [] {
        didSet { canGoForward = !forwardStack.isEmpty }
    }
    /// The listing in flight. Internal so tests can await it.
    private(set) var loadTask: Task<Void, Never>?

    /// Sizes computed so far, by folder path. Kept across navigation so a folder seen before shows
    /// its last known size at once while a fresh one is computed.
    private var folderSizes: [String: Int64] = [:]
    /// True when every folder of the listing must be sized again, not only the unknown ones.
    private var needsFullSizing = true
    /// The size computation in flight. Internal so tests can await it.
    private(set) var sizeTask: Task<Void, Never>?

    public init(
        location: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileSystem: any FileSystemProviding = LocalFileSystem(),
        operations: any FileOperating = LocalFileOperations(),
        history: UndoHistory = UndoHistory(),
        calculatesFolderSizes: Bool = true,
        openFiles: @escaping @MainActor ([URL]) -> Void = { urls in
            for url in urls { NSWorkspace.shared.open(url) }
        }
    ) {
        self.location = location.canonicalLocation
        self.fileSystem = fileSystem
        self.operations = operations
        self.history = history
        self.calculatesFolderSizes = calculatesFolderSizes
        self.openFiles = openFiles
    }

    // MARK: Navigation

    public func navigate(to url: URL) {
        let destination = url.canonicalLocation
        guard destination != location else {
            reload()
            return
        }
        backStack.append(location)
        forwardStack.removeAll()
        show(destination)
    }

    /// Navigates to a path typed by the user. `~` is expanded; anything that is not absolute is ignored.
    public func navigate(toPath path: String) {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        let expanded = NSString(string: trimmed).expandingTildeInPath
        guard expanded.hasPrefix("/") else { return }
        navigate(to: URL(filePath: expanded, directoryHint: .isDirectory))
    }

    public func goBack() {
        guard let previous = backStack.popLast() else { return }
        forwardStack.append(location)
        show(previous)
    }

    public func goForward() {
        guard let next = forwardStack.popLast() else { return }
        backStack.append(location)
        show(next)
    }

    public func goUp() {
        guard canGoUp else { return }
        navigate(to: location.deletingLastPathComponent())
    }

    /// Opens an entry the way a double-click does: folders are entered, files go to their app.
    public func open(_ item: FileItem) {
        if item.isFolder {
            navigate(to: item.url)
        } else {
            openFiles([item.url])
        }
    }

    /// Opens the selection: a single folder is entered, files go to their apps.
    public func openSelection() {
        let selected = selectedItems
        if selected.count == 1, let only = selected.first {
            open(only)
        } else {
            let files = selected.filter { !$0.isFolder }.map(\.url)
            if !files.isEmpty { openFiles(files) }
        }
    }

    // MARK: Filter

    public func appendToFilter(_ text: String) {
        filterText += text
    }

    /// Removes the last character of the filter. Returns `false` when there was no filter.
    @discardableResult
    public func deleteFilterBackward() -> Bool {
        guard !filterText.isEmpty else { return false }
        filterText.removeLast()
        return true
    }

    /// Returns `false` when there was no filter to clear.
    @discardableResult
    public func clearFilter() -> Bool {
        guard !filterText.isEmpty else { return false }
        filterText = ""
        return true
    }

    /// Lists the current location again and computes every folder size afresh.
    public func reload() {
        needsFullSizing = true
        refresh()
    }

    /// Lists the current location again, keeping what is already known about it.
    func refresh() {
        loadTask?.cancel()
        isLoading = true
        let directory = location
        loadTask = Task { [fileSystem] in
            do {
                let listed = try await fileSystem.contents(of: directory)
                guard !Task.isCancelled else { return }
                allItems = listed
                errorMessage = nil
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                allItems = []
                errorMessage = error.localizedDescription
            }
            rebuildItems()
            applyPendingSelection()
            isLoading = false
            startSizing()
        }
    }

    /// Selects, and possibly starts renaming, the entries an operation just produced.
    private func applyPendingSelection() {
        if let names = selectAfterLoad {
            let found = items.filter { names.contains($0.name) }.map(\.url)
            // Not listed yet: keep waiting for the refresh that shows them.
            if !found.isEmpty {
                selection = Set(found)
                selectAfterLoad = nil
            }
        }
        if let name = renameAfterLoad, let item = items.first(where: { $0.name == name }) {
            renamingURL = item.url
            renameAfterLoad = nil
        }
    }

    /// Computes folder sizes in the background, two folders at a time, and publishes them in batches.
    private func startSizing() {
        guard calculatesFolderSizes else { return }
        // A refresh while a computation runs must not restart it: busy folders would never finish.
        if sizeTask != nil && !needsFullSizing { return }
        // Links are skipped: their target is not part of this folder.
        var folders = allItems.filter { $0.isDirectory && !$0.isSymbolicLink }.map(\.url)
        if !needsFullSizing {
            folders.removeAll { folderSizes[$0.path] != nil }
        }
        needsFullSizing = false
        sizeTask?.cancel()
        sizeTask = nil
        guard !folders.isEmpty else { return }

        sizeTask = Task { [fileSystem] in
            var pending = folders.makeIterator()
            await withTaskGroup(of: (URL, Int64?).self) { group in
                func addNext() {
                    guard let url = pending.next() else { return }
                    group.addTask { (url, try? await fileSystem.directorySize(of: url)) }
                }
                addNext()
                addNext()
                var lastPublished = ContinuousClock.now
                for await (url, size) in group {
                    if Task.isCancelled { break }
                    if let size { folderSizes[url.path] = size }
                    addNext()
                    // Publishing every result would re-sort and redraw the list hundreds of times.
                    if ContinuousClock.now - lastPublished > .milliseconds(250) {
                        rebuildItems()
                        lastPublished = .now
                    }
                }
            }
            guard !Task.isCancelled else { return }
            rebuildItems()
            sizeTask = nil
        }
    }

    /// Keeps the listing in sync with the disk for as long as the caller awaits it.
    /// Watches the location current at the time of the call: call it again after navigating.
    public func followChanges() async {
        for await _ in fileSystem.changes(in: location) {
            refresh()
        }
    }

    private func show(_ url: URL) {
        location = url
        // The previous folder's rows must not linger under the new title while the listing runs.
        allItems = []
        items = []
        errorMessage = nil
        filterText = ""
        selection = []
        renamingURL = nil
        selectAfterLoad = nil
        renameAfterLoad = nil
        sizeTask?.cancel()
        sizeTask = nil
        reload()
    }

    private func rebuildItems() {
        var visible = showsHiddenFiles ? allItems : allItems.filter { !$0.isHidden }
        if !filterText.isEmpty {
            // Case- and diacritic-insensitive, like Finder's search.
            visible = visible.filter { $0.name.localizedStandardContains(filterText) }
        }
        if calculatesFolderSizes {
            for index in visible.indices where visible[index].isDirectory {
                if let size = folderSizes[visible[index].url.path] {
                    visible[index].size = size
                }
            }
        }
        items = sort.sorted(visible)
        if !selection.isEmpty {
            selection.formIntersection(items.map(\.url))
        }
    }
}

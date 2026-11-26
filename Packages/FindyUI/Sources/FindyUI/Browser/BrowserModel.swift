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

    /// Remembered per folder when the pane has a settings store.
    public var sort = FileSort() {
        didSet {
            guard sort != oldValue else { return }
            rebuildItems()
            saveSettings()
        }
    }

    /// Remembered per folder when the pane has a settings store.
    public var showsHiddenFiles = false {
        didSet {
            guard showsHiddenFiles != oldValue else { return }
            rebuildItems()
            saveSettings()
            // Hidden entries are left out by the search itself: it has to look again.
            if searchResults != nil { startSearch(keepingResults: true) }
        }
    }

    /// Whether the search bar is shown.
    public private(set) var isSearching = false
    /// Bumped each time the user asks for the search bar, so the field can take the focus again.
    public private(set) var searchFocusRequests = 0
    /// What to look for under the folder shown, at any depth. Empty: the list shows the folder.
    public var searchText = "" {
        didSet { if searchText != oldValue { startSearch(keepingResults: false) } }
    }
    /// True while the disk is still being searched.
    public private(set) var isSearchRunning = false
    /// True when the search stopped at `searchResultLimit` results.
    public private(set) var searchIsTruncated = false
    /// True when the list shows search results instead of the folder's own content.
    public var showsSearchResults: Bool { searchResults != nil }

    /// Whether the list is split in sections by modification date. Remembered per folder when
    /// the pane has a settings store.
    public var groupsByDate = false {
        didSet {
            guard groupsByDate != oldValue else { return }
            rebuildItems()
            saveSettings()
        }
    }

    /// Text typed in the list. Only entries whose name contains it are shown.
    public var filterText = "" {
        didSet { if filterText != oldValue { applyFilter() } }
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

    /// What the Get Info sheet is showing. `nil` when it is closed.
    public var infoTarget: InfoTarget?

    /// A failure to tell the user about. Cleared when they dismiss it.
    public var alertMessage: String?

    /// How far the running copy or move has got. `nil` when none is running.
    public internal(set) var progress: OperationProgress?

    /// True while an operation on files is running.
    public internal(set) var isBusy = false

    /// The Git repository the folder shown belongs to, if any.
    public private(set) var gitInfo: GitInfo?
    /// What changed in that repository. Arrives after the branch: Git has to be asked.
    public private(set) var gitChanges: GitChanges?
    /// Bytes left on the volume of the folder shown, when the volume reports it.
    public private(set) var availableSpace: Int64?

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
    let iconProvider: any IconProviding
    private let settingsStore: (any FolderSettingsStoring)?
    /// The folder whose saved settings are currently applied.
    private var settingsLocation: URL?
    /// True while saved settings are being applied, so applying them is not taken for a change
    /// by the user and written straight back.
    private var isApplyingSettings = false
    /// The save in flight. Internal so tests can await it.
    private(set) var settingsTask: Task<Void, Never>?
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
    private let openInTerminal: @MainActor (URL) async throws -> Void
    private let openInEditor: @MainActor ([URL]) async throws -> Void
    private let openWithApplication: @MainActor ([URL], URL) async throws -> Void
    private let revealInFinder: @MainActor ([URL]) -> Void
    /// The listing as the disk gave it.
    private var allItems: [FileItem] = []
    /// The listing without what is hidden, with folder sizes, in display order. `items` is this
    /// list narrowed by the filter, so typing a filter never sorts anything.
    private var arranged: [FileItem] = []
    private var backStack: [URL] = [] {
        didSet { canGoBack = !backStack.isEmpty }
    }
    private var forwardStack: [URL] = [] {
        didSet { canGoForward = !forwardStack.isEmpty }
    }
    /// The listing in flight. Internal so tests can await it.
    private(set) var loadTask: Task<Void, Never>?
    /// What the search found so far. `nil` when the list shows the folder itself.
    private var searchResults: [FileItem]?
    /// The search in flight. Internal so tests can await it.
    private(set) var searchTask: Task<Void, Never>?
    /// A search stops here: more results than this help nobody, and they all have to be sorted.
    static let searchResultLimit = 5_000
    /// The sort of a big folder in flight. Internal so tests can await it.
    private(set) var arrangeTask: Task<Void, Never>?
    /// Above this many entries a re-sort leaves the main thread. Below, it takes less than a
    /// frame and stays synchronous, so the list never shows a stale order.
    static let backgroundSortThreshold = 2_000
    /// The read of the Git branch and of the free space in flight. Internal so tests can await it.
    private(set) var statusTask: Task<Void, Never>?
    /// The launch of another application in flight. Internal so tests can await it.
    private(set) var terminalTask: Task<Void, Never>?

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
        settingsStore: (any FolderSettingsStoring)? = nil,
        iconProvider: any IconProviding = QuickLookIconProvider(),
        calculatesFolderSizes: Bool = true,
        openFiles: @escaping @MainActor ([URL]) -> Void = { urls in
            for url in urls { NSWorkspace.shared.open(url) }
        },
        openInTerminal: @escaping @MainActor (URL) async throws -> Void = { try await TerminalLauncher.open($0) },
        openInEditor: @escaping @MainActor ([URL]) async throws -> Void = { try await EditorLauncher.open($0) },
        openWithApplication: @escaping @MainActor ([URL], URL) async throws -> Void = { urls, application in
            _ = try await NSWorkspace.shared.open(
                urls, withApplicationAt: application, configuration: NSWorkspace.OpenConfiguration())
        },
        revealInFinder: @escaping @MainActor ([URL]) -> Void = { NSWorkspace.shared.activateFileViewerSelecting($0) }
    ) {
        self.location = location.canonicalLocation
        self.fileSystem = fileSystem
        self.operations = operations
        self.history = history
        self.settingsStore = settingsStore
        self.iconProvider = iconProvider
        self.calculatesFolderSizes = calculatesFolderSizes
        self.openFiles = openFiles
        self.openInTerminal = openInTerminal
        self.openInEditor = openInEditor
        self.openWithApplication = openWithApplication
        self.revealInFinder = revealInFinder
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

    // MARK: Terminal

    /// The folder a terminal would open in: the selected folder when exactly one entry is selected
    /// and it is a folder, the folder shown otherwise.
    public var terminalFolder: URL {
        let selected = selectedItems
        if selected.count == 1, let only = selected.first, only.isFolder {
            return only.url
        }
        return location
    }

    /// Opens a terminal window in `terminalFolder`.
    public func openTerminal() {
        let folder = terminalFolder
        terminalTask = Task {
            do {
                try await openInTerminal(folder)
            } catch {
                report(error)
            }
        }
    }

    /// What Add to Sidebar adds: the selected folders, or the folder shown when none is selected.
    public var foldersForSidebar: [URL] {
        let folders = selectedItems.filter(\.isFolder).map(\.url)
        return selection.isEmpty ? [location] : folders
    }

    // MARK: Get Info

    /// Opens Get Info on the selection, or on the folder shown when nothing is selected.
    public func getInfo() {
        let selected = selectedItems.map(\.url)
        infoTarget = InfoTarget(urls: selected.isEmpty ? [location] : selected)
    }

    // MARK: Other applications

    /// Opens the selected files in the application at `application`, whatever their default one.
    public func openSelection(withApplicationAt application: URL) {
        let urls = selectedItems.map(\.url)
        guard !urls.isEmpty else { return }
        terminalTask = Task {
            do {
                try await openWithApplication(urls, application)
            } catch {
                report(error)
            }
        }
    }

    /// Shows the selection in a Finder window, or the folder shown when nothing is selected.
    /// The way out for everything Findy leaves to Finder.
    public func showInFinder() {
        let selected = selectedItems.map(\.url)
        revealInFinder(selected.isEmpty ? [location] : selected)
    }

    // MARK: Editor

    /// What Open in Editor hands to the editor: the selection, or the folder shown when nothing
    /// is selected, which opens it as a project.
    public var editorTargets: [URL] {
        let selected = selectedItems.map(\.url)
        return selected.isEmpty ? [location] : selected
    }

    public func openEditor() {
        let targets = editorTargets
        terminalTask = Task {
            do {
                try await openInEditor(targets)
            } catch {
                report(error)
            }
        }
    }

    // MARK: Search

    /// Shows the search bar, or gives it the focus again.
    public func beginSearch() {
        isSearching = true
        searchFocusRequests += 1
    }

    /// Hides the search bar and shows the folder again.
    public func endSearch() {
        isSearching = false
        searchText = ""
    }

    /// The folder holding the only selected search result, relative to the folder shown. `nil`
    /// outside a search, or when the result sits directly in the folder shown.
    public var selectedResultFolder: String? {
        guard showsSearchResults, selection.count == 1, let item = selectedItems.first else { return nil }
        let folder = (pathInFolderShown(of: item) as NSString).deletingLastPathComponent
        return folder.isEmpty ? nil : folder
    }

    /// Looks for `searchText` under the folder shown. A new query replaces the search in flight.
    /// - Parameter keepingResults: leave the current results on screen until the new ones come,
    ///   for a search repeated because the disk or a setting changed.
    private func startSearch(keepingResults: Bool) {
        searchTask?.cancel()
        searchTask = nil
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            let wasShowingResults = searchResults != nil
            searchResults = nil
            isSearchRunning = false
            searchIsTruncated = false
            if wasShowingResults { rebuildItems() }
            return
        }
        if !keepingResults || searchResults == nil {
            searchResults = []
            rebuildItems()
        }
        isSearchRunning = true
        let directory = location
        let includingHidden = showsHiddenFiles
        searchTask = Task { [fileSystem] in
            // A word is typed in a burst: wait for the pause before walking the disk.
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            var found: [FileItem] = []
            var isTruncated = false
            for await batch in fileSystem.search(in: directory, matching: query, includingHidden: includingHidden) {
                guard !Task.isCancelled else { return }
                found += batch
                if found.count >= Self.searchResultLimit {
                    found.removeSubrange(Self.searchResultLimit...)
                    isTruncated = true
                }
                searchResults = found
                searchIsTruncated = isTruncated
                rebuildItems()
                if isTruncated { break }
            }
            guard !Task.isCancelled else { return }
            if found.isEmpty {
                // Nothing found: a repeated search must still drop what it kept on screen.
                searchResults = []
                searchIsTruncated = false
                rebuildItems()
            }
            isSearchRunning = false
        }
    }

    // MARK: Groups

    /// The section `item` is listed under when the list is grouped by date.
    public func dateGroup(of item: FileItem) -> DateGroup {
        DateGroup(for: item.modificationDate, now: Date())
    }

    // MARK: Status

    /// The sizes of the selected entries added up. `nil` when none of them has a known size.
    public var selectedSize: Int64? {
        let sizes = selectedItems.compactMap(\.size)
        return sizes.isEmpty ? nil : sizes.reduce(0, +)
    }

    /// What Copy Path puts on the clipboard: the selected entries, one per line and in the order
    /// shown, or the folder shown when nothing is selected.
    public var pathsForClipboard: String {
        let selected = selectedItems.map(\.url.path)
        return selected.isEmpty ? location.path : selected.joined(separator: "\n")
    }

    public func copyPath() {
        FilePasteboard.write(text: pathsForClipboard)
    }

    /// What Git says about an entry of the list. `nil` outside a repository, and for a tracked
    /// entry that did not change.
    public func gitState(of item: FileItem) -> GitFileState? {
        guard let gitChanges, let root = gitInfo?.root, location.path.hasPrefix(root.path) else { return nil }
        // Built from the folder shown, not from the entry's own URL: the system may spell the
        // latter `/private/tmp/…` when the repository was found under `/tmp/…` (macOS 26.3).
        let folder = location.path.dropFirst(root.path.count).drop { $0 == "/" }
        let inFolder = pathInFolderShown(of: item)
        return gitChanges.state(forRelativePath: folder.isEmpty ? inFolder : "\(folder)/\(inFolder)")
    }

    /// Where `item` is under the folder shown: its name, or a longer path for a search result
    /// found deeper.
    func pathInFolderShown(of item: FileItem) -> String {
        let prefix = location.path.hasSuffix("/") ? location.path : location.path + "/"
        return item.url.path.hasPrefix(prefix) ? String(item.url.path.dropFirst(prefix.count)) : item.name
    }

    /// Reads the Git branch and the free space again. Both are cheap, and both go stale: a copy
    /// eats space, a checkout changes the branch.
    func refreshStatus() {
        statusTask?.cancel()
        let directory = location
        statusTask = Task { [fileSystem] in
            let git = await fileSystem.gitInfo(for: directory)
            let space = await fileSystem.availableSpace(at: directory)
            guard !Task.isCancelled, location == directory else { return }
            // Changes counted for another repository must not sit next to this one's branch.
            if git?.root != gitInfo?.root { gitChanges = nil }
            gitInfo = git
            availableSpace = space
            guard let root = git?.root else { return }
            let changes = await fileSystem.gitChanges(inRepositoryAt: root)
            guard !Task.isCancelled, location == directory else { return }
            gitChanges = changes
        }
    }

    /// Follows the whole working tree, `.git` included: a file edited three folders down or a
    /// checkout made in a terminal both show up without a reload. Watches the repository current
    /// at the time of the call.
    public func followGitChanges() async {
        guard let root = gitInfo?.root else { return }
        for await _ in fileSystem.changes(under: root) {
            refreshStatus()
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
        refreshStatus()
        loadTask = Task { [fileSystem] in
            // Settings first, so the folder appears directly in the order the user chose for it.
            await applySavedSettings(for: directory)
            guard !Task.isCancelled else { return }
            do {
                let listed = try await fileSystem.contents(of: directory)
                guard !Task.isCancelled else { return }
                // Sorting thousands of names takes long enough to drop frames: it runs off the
                // main thread, on a snapshot of the settings.
                let sort = sort
                let showsHiddenFiles = showsHiddenFiles
                let groupsByDate = groupsByDate
                let sizes = calculatesFolderSizes ? folderSizes : [:]
                let sorted = await Task.detached(priority: .userInitiated) {
                    Self.arrange(
                        listed, showsHiddenFiles: showsHiddenFiles, sizes: sizes, sort: sort,
                        groupsByDate: groupsByDate)
                }.value
                guard !Task.isCancelled else { return }
                // A re-sort of the previous listing still running must not land over this one.
                arrangeTask?.cancel()
                arrangeTask = nil
                allItems = listed
                errorMessage = nil
                if searchResults != nil {
                    // The list shows results, not this listing. Something changed on disk, so the
                    // results may be stale: look again, without blanking the list meanwhile.
                    startSearch(keepingResults: true)
                } else if sort == self.sort, showsHiddenFiles == self.showsHiddenFiles,
                    groupsByDate == self.groupsByDate
                {
                    arranged = sorted
                    applyFilter()
                } else {
                    // The user changed a setting while the sort was running.
                    rebuildItems()
                }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                allItems = []
                errorMessage = error.localizedDescription
                rebuildItems()
            }
            applyPendingSelection()
            isLoading = false
            startSizing()
        }
    }

    /// Applies what the user chose for `directory` the last time, or the defaults for a folder
    /// they never customized. Does nothing when the folder's settings are already applied.
    private func applySavedSettings(for directory: URL) async {
        guard let settingsStore, settingsLocation != directory else { return }
        var saved: FolderSettings?
        do {
            saved = try await settingsStore.settings(for: directory)
        } catch {
            report(error)
        }
        guard !Task.isCancelled, location == directory else { return }
        let settings = saved ?? FolderSettings()
        isApplyingSettings = true
        sort = settings.sort
        showsHiddenFiles = settings.showsHiddenFiles
        groupsByDate = settings.groupsByDate
        isApplyingSettings = false
        settingsLocation = directory
    }

    private func saveSettings() {
        guard let settingsStore, !isApplyingSettings else { return }
        let folder = location
        let settings = FolderSettings(sort: sort, showsHiddenFiles: showsHiddenFiles, groupsByDate: groupsByDate)
        settingsLocation = folder
        // Saves are chained: two changes in a row must reach the database in the order they were
        // made, or the older one could land last and win.
        let previous = settingsTask
        settingsTask = Task {
            await previous?.value
            do {
                try await settingsStore.save(settings, for: folder)
            } catch {
                report(error)
            }
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
                        publishFolderSizes()
                        lastPublished = .now
                    }
                }
            }
            guard !Task.isCancelled else { return }
            publishFolderSizes()
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
        arrangeTask?.cancel()
        arrangeTask = nil
        allItems = []
        arranged = []
        items = []
        errorMessage = nil
        filterText = ""
        // A search belongs to the folder it was made in.
        searchTask?.cancel()
        searchTask = nil
        searchResults = nil
        isSearching = false
        isSearchRunning = false
        searchIsTruncated = false
        searchText = ""
        selection = []
        renamingURL = nil
        selectAfterLoad = nil
        renameAfterLoad = nil
        sizeTask?.cancel()
        sizeTask = nil
        reload()
    }

    /// Shows the sizes computed so far. Unless the list is sorted by size, nothing moves: the
    /// numbers are filled in where they are.
    private func publishFolderSizes() {
        guard sort.key != .size else {
            rebuildItems()
            return
        }
        for index in arranged.indices where arranged[index].isDirectory {
            if let size = folderSizes[arranged[index].url.path] {
                arranged[index].size = size
            }
        }
        applyFilter()
    }

    /// Recomputes the display order from the listing. Needed when the listing, the sort, the
    /// hidden files setting or the sizes of a list sorted by size change.
    private func rebuildItems() {
        arrangeTask?.cancel()
        arrangeTask = nil
        let listing = searchResults ?? allItems
        // The search already left hidden entries out, or kept them, as the setting says.
        let showsHiddenFiles = showsHiddenFiles || searchResults != nil
        let sizes = calculatesFolderSizes ? folderSizes : [:]
        let sort = sort
        let groupsByDate = groupsByDate
        guard listing.count > Self.backgroundSortThreshold else {
            arranged = Self.arrange(
                listing, showsHiddenFiles: showsHiddenFiles, sizes: sizes, sort: sort, groupsByDate: groupsByDate)
            applyFilter()
            return
        }
        // Sorting 10,000 names takes about 75 ms, several frames: a big folder is sorted off the
        // main thread and the list keeps its current order until the new one is ready.
        arrangeTask = Task {
            let sorted = await Task.detached(priority: .userInitiated) {
                Self.arrange(
                    listing, showsHiddenFiles: showsHiddenFiles, sizes: sizes, sort: sort,
                    groupsByDate: groupsByDate)
            }.value
            guard !Task.isCancelled else { return }
            arranged = sorted
            applyFilter()
            arrangeTask = nil
        }
    }

    /// Narrows the arranged list to the entries matching the filter. Order is kept, so this never sorts.
    private func applyFilter() {
        if filterText.isEmpty {
            items = arranged
        } else {
            // Case- and diacritic-insensitive, like Finder's search.
            items = arranged.filter { $0.name.localizedStandardContains(filterText) }
        }
        if !selection.isEmpty {
            selection.formIntersection(items.map(\.url))
        }
    }

    private nonisolated static func arrange(
        _ listing: [FileItem], showsHiddenFiles: Bool, sizes: [String: Int64], sort: FileSort,
        groupsByDate: Bool
    ) -> [FileItem] {
        var visible = showsHiddenFiles ? listing : listing.filter { !$0.isHidden }
        if !sizes.isEmpty {
            for index in visible.indices where visible[index].isDirectory {
                if let size = sizes[visible[index].url.path] {
                    visible[index].size = size
                }
            }
        }
        let sorted = sort.sorted(visible)
        // Sections come most recent first; inside a section the chosen sort applies.
        return groupsByDate ? DateGroup.grouped(sorted, now: Date()) : sorted
    }
}

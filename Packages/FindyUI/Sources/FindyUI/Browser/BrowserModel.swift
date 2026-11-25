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
    private var allItems: [FileItem] = []
    private var backStack: [URL] = [] {
        didSet { canGoBack = !backStack.isEmpty }
    }
    private var forwardStack: [URL] = [] {
        didSet { canGoForward = !forwardStack.isEmpty }
    }
    /// The listing in flight. Internal so tests can await it.
    private(set) var loadTask: Task<Void, Never>?

    public init(
        location: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileSystem: any FileSystemProviding = LocalFileSystem()
    ) {
        self.location = location.canonicalLocation
        self.fileSystem = fileSystem
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

    /// Opens an entry the way a double-click does. Returns `false` when the entry is not a folder,
    /// so the caller can hand it to the system.
    @discardableResult
    public func open(_ item: FileItem) -> Bool {
        guard item.isFolder else { return false }
        navigate(to: item.url)
        return true
    }

    /// Lists the current location again.
    public func reload() {
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
            isLoading = false
        }
    }

    private func show(_ url: URL) {
        location = url
        // The previous folder's rows must not linger under the new title while the listing runs.
        allItems = []
        items = []
        errorMessage = nil
        reload()
    }

    private func rebuildItems() {
        let visible = showsHiddenFiles ? allItems : allItems.filter { !$0.isHidden }
        items = sort.sorted(visible)
    }
}

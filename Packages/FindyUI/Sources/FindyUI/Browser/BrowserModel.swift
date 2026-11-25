import FindyCore
import Foundation
import Observation

/// State of one browser pane: where it is, what it shows, and its navigation history.
@MainActor
@Observable
public final class BrowserModel {
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

    public private(set) var canGoBack = false
    public private(set) var canGoForward = false

    public var canGoUp: Bool { location.path != "/" }

    public var title: String {
        location.path == "/" ? "/" : location.lastPathComponent
    }

    private let fileSystem: any FileSystemProviding
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

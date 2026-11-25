import FindyCore
import Foundation
import Observation

/// What one window (or tab) holds: its panes and which one has the user's attention.
@MainActor
@Observable
public final class WorkspaceModel {
    public private(set) var panes: [BrowserModel]
    public private(set) var activePaneIndex = 0

    /// The pane menu commands and the toolbar act on.
    public var activePane: BrowserModel { panes[activePaneIndex] }

    /// Applies to every pane and is remembered across launches.
    public var calculatesFolderSizes: Bool {
        didSet {
            guard calculatesFolderSizes != oldValue else { return }
            defaults.set(calculatesFolderSizes, forKey: Self.folderSizesKey)
            for pane in panes { pane.calculatesFolderSizes = calculatesFolderSizes }
        }
    }

    private static let folderSizesKey = "calculatesFolderSizes"

    /// One undo history for the whole window.
    public let history = UndoHistory()

    private let fileSystem: any FileSystemProviding
    private let operations: any FileOperating
    private let settingsStore: (any FolderSettingsStoring)?
    private let defaults: UserDefaults

    public init(
        location: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileSystem: any FileSystemProviding = LocalFileSystem(),
        operations: any FileOperating = LocalFileOperations(),
        settingsStore: (any FolderSettingsStoring)? = nil,
        defaults: UserDefaults = .standard
    ) {
        self.settingsStore = settingsStore
        self.fileSystem = fileSystem
        self.operations = operations
        self.defaults = defaults
        // On unless the user turned it off.
        let calculatesFolderSizes = defaults.object(forKey: Self.folderSizesKey) as? Bool ?? true
        self.calculatesFolderSizes = calculatesFolderSizes
        panes = [
            BrowserModel(
                location: location, fileSystem: fileSystem, operations: operations, history: history,
                settingsStore: settingsStore, calculatesFolderSizes: calculatesFolderSizes)
        ]
    }

    public var isDualPane: Bool { panes.count == 2 }

    /// The pane facing the active one, when there are two.
    public var otherPane: BrowserModel? {
        isDualPane ? panes[1 - activePaneIndex] : nil
    }

    public func activate(_ pane: BrowserModel) {
        guard let index = panes.firstIndex(where: { $0 === pane }) else { return }
        activePaneIndex = index
    }

    /// Opens a second pane on the folder being looked at, or closes the pane that is not active.
    public func toggleDualPane() {
        if isDualPane {
            panes = [activePane]
            activePaneIndex = 0
        } else {
            panes.append(makePane(at: activePane.location))
        }
    }

    /// Sends every pane showing a folder of `volume`, which is about to be ejected, to `refuge`
    /// (the home folder by default): a pane left there would keep watching a disk that is going away.
    public func leave(_ volume: URL, for refuge: URL = FileManager.default.homeDirectoryForCurrentUser) {
        let root = volume.canonicalLocation.path
        guard root != "/" else { return }
        for pane in panes where pane.location.path == root || pane.location.path.hasPrefix(root + "/") {
            pane.navigate(to: refuge)
        }
    }

    /// Gives the user's attention to the other pane.
    public func switchPane() {
        guard isDualPane else { return }
        activePaneIndex = 1 - activePaneIndex
    }

    public func copySelectionToOtherPane() {
        otherPane?.transfer(activePane.selectedItems.map(\.url), move: false)
    }

    public func moveSelectionToOtherPane() {
        otherPane?.transfer(activePane.selectedItems.map(\.url), move: true)
    }

    private func makePane(at location: URL) -> BrowserModel {
        BrowserModel(
            location: location, fileSystem: fileSystem, operations: operations, history: history,
            settingsStore: settingsStore, calculatesFolderSizes: calculatesFolderSizes)
    }
}

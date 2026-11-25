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
    private let defaults: UserDefaults

    public init(
        location: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileSystem: any FileSystemProviding = LocalFileSystem(),
        defaults: UserDefaults = .standard
    ) {
        self.fileSystem = fileSystem
        self.defaults = defaults
        // On unless the user turned it off.
        let calculatesFolderSizes = defaults.object(forKey: Self.folderSizesKey) as? Bool ?? true
        self.calculatesFolderSizes = calculatesFolderSizes
        panes = [
            BrowserModel(
                location: location, fileSystem: fileSystem, history: history,
                calculatesFolderSizes: calculatesFolderSizes)
        ]
    }

    public func activate(_ pane: BrowserModel) {
        guard let index = panes.firstIndex(where: { $0 === pane }) else { return }
        activePaneIndex = index
    }
}

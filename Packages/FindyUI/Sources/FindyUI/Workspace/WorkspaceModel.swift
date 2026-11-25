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

    private let fileSystem: any FileSystemProviding

    public init(
        location: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileSystem: any FileSystemProviding = LocalFileSystem()
    ) {
        self.fileSystem = fileSystem
        panes = [BrowserModel(location: location, fileSystem: fileSystem)]
    }

    public func activate(_ pane: BrowserModel) {
        guard let index = panes.firstIndex(where: { $0 === pane }) else { return }
        activePaneIndex = index
    }
}

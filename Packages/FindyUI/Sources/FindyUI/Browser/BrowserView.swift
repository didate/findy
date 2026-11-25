import SwiftUI

/// One browser window: sidebar on the left, panes on the right.
public struct BrowserView: View {
    @State private var workspace: WorkspaceModel
    @State private var sidebar = SidebarModel()

    /// - Parameter location: the folder to show first; the home folder when `nil`.
    ///   A window opened by New Tab shows the folder that command asked for instead.
    public init(location: URL? = nil) {
        let start = BrowserWindow.pendingLocation ?? location ?? FileManager.default.homeDirectoryForCurrentUser
        _workspace = State(
            initialValue: WorkspaceModel(location: start, settingsStore: FolderSettingsDatabase.shared))
    }

    public var body: some View {
        NavigationSplitView {
            SidebarView(model: sidebar, location: workspace.activePane.location) { url in
                workspace.activePane.navigate(to: url)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 200, max: 320)
        } detail: {
            HStack(spacing: 0) {
                ForEach(workspace.panes) { pane in
                    if pane !== workspace.panes.first { Divider() }
                    PaneView(
                        model: pane,
                        isActive: pane === workspace.activePane,
                        isDualPane: workspace.isDualPane,
                        onActivate: { workspace.activate(pane) },
                        onSwitchPane: { workspace.switchPane() }
                    )
                }
            }
            .navigationTitle(workspace.activePane.title)
            .toolbar { toolbar }
        }
        .background(WindowAccessor { BrowserWindow.windowDidAppear($0) })
        .focusedSceneValue(\.workspace, workspace)
        .task { await sidebar.loadVolumes() }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        let pane = workspace.activePane

        ToolbarItemGroup(placement: .navigation) {
            Button {
                pane.goBack()
            } label: {
                Label {
                    Text("Back", bundle: .module)
                } icon: {
                    Image(systemName: "chevron.left")
                }
            }
            .disabled(!pane.canGoBack)

            Button {
                pane.goForward()
            } label: {
                Label {
                    Text("Forward", bundle: .module)
                } icon: {
                    Image(systemName: "chevron.right")
                }
            }
            .disabled(!pane.canGoForward)

            Button {
                pane.goUp()
            } label: {
                Label {
                    Text("Enclosing Folder", bundle: .module)
                } icon: {
                    Image(systemName: "arrow.up")
                }
            }
            .disabled(!pane.canGoUp)
        }

        ToolbarItem(placement: .primaryAction) {
            Toggle(
                isOn: Binding(
                    get: { workspace.isDualPane },
                    set: { _ in workspace.toggleDualPane() }
                )
            ) {
                Label {
                    Text("Dual Pane", bundle: .module)
                } icon: {
                    Image(systemName: "rectangle.split.2x1")
                }
            }
        }

        ToolbarItem(placement: .primaryAction) {
            Toggle(
                isOn: Binding(
                    get: { pane.showsHiddenFiles },
                    set: { pane.showsHiddenFiles = $0 }
                )
            ) {
                Label {
                    Text("Show Hidden Files", bundle: .module)
                } icon: {
                    Image(systemName: pane.showsHiddenFiles ? "eye" : "eye.slash")
                }
            }
        }
    }
}

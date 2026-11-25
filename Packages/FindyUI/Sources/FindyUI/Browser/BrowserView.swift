import SwiftUI

/// One browser window: sidebar on the left, panes on the right.
public struct BrowserView: View {
    @State private var workspace = WorkspaceModel()
    @State private var sidebar = SidebarModel()

    public init() {}

    public var body: some View {
        NavigationSplitView {
            SidebarView(model: sidebar, location: workspace.activePane.location) { url in
                workspace.activePane.navigate(to: url)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 200, max: 320)
        } detail: {
            HStack(spacing: 0) {
                ForEach(workspace.panes) { pane in
                    PaneView(model: pane)
                }
            }
            .navigationTitle(workspace.activePane.title)
            .toolbar { toolbar }
        }
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

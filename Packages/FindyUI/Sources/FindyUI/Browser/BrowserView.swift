import AppKit
import FindyCore
import SwiftUI

/// One browser window: sidebar on the left, file list on the right.
public struct BrowserView: View {
    @State private var model = BrowserModel()
    @State private var sidebar = SidebarModel()

    public init() {}

    public var body: some View {
        NavigationSplitView {
            SidebarView(model: sidebar, location: model.location) { url in
                model.navigate(to: url)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 200, max: 320)
        } detail: {
            content
                .navigationTitle(model.title)
                .navigationSubtitle(model.location.path)
                .toolbar { toolbar }
        }
        .task {
            model.reload()
            await sidebar.loadVolumes()
        }
    }

    @ViewBuilder private var content: some View {
        if let errorMessage = model.errorMessage {
            ContentUnavailableView {
                Label {
                    Text("Can’t Open This Folder", bundle: .module)
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                }
            } description: {
                Text(errorMessage)
            }
        } else {
            FileListView(items: model.items, sort: $model.sort) { item in
                open(item)
            }
            .overlay {
                if model.items.isEmpty && !model.isLoading {
                    Text("Empty Folder", bundle: .module)
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button {
                model.goBack()
            } label: {
                Label {
                    Text("Back", bundle: .module)
                } icon: {
                    Image(systemName: "chevron.left")
                }
            }
            .keyboardShortcut("[", modifiers: .command)
            .disabled(!model.canGoBack)

            Button {
                model.goForward()
            } label: {
                Label {
                    Text("Forward", bundle: .module)
                } icon: {
                    Image(systemName: "chevron.right")
                }
            }
            .keyboardShortcut("]", modifiers: .command)
            .disabled(!model.canGoForward)

            Button {
                model.goUp()
            } label: {
                Label {
                    Text("Enclosing Folder", bundle: .module)
                } icon: {
                    Image(systemName: "arrow.up")
                }
            }
            .keyboardShortcut(.upArrow, modifiers: .command)
            .disabled(!model.canGoUp)
        }

        ToolbarItem(placement: .primaryAction) {
            Toggle(isOn: $model.showsHiddenFiles) {
                Label {
                    Text("Show Hidden Files", bundle: .module)
                } icon: {
                    Image(systemName: model.showsHiddenFiles ? "eye" : "eye.slash")
                }
            }
            .keyboardShortcut(".", modifiers: [.command, .shift])
        }
    }

    private func open(_ item: FileItem) {
        if item.isFolder {
            model.navigate(to: item.url)
        } else {
            NSWorkspace.shared.open(item.url)
        }
    }
}

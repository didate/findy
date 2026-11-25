import AppKit
import FindyCore
import SwiftUI

/// One pane: its path bar on top of its file list.
struct PaneView: View {
    @Bindable var model: BrowserModel

    var body: some View {
        VStack(spacing: 0) {
            PathBarView(model: model)
            Divider()
            content
        }
        .task { model.reload() }
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
                if !model.open(item) {
                    NSWorkspace.shared.open(item.url)
                }
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
}

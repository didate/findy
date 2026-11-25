import FindyCore
import SwiftUI

/// One pane: its path bar on top of its file list.
struct PaneView: View {
    @Bindable var model: BrowserModel
    let onActivate: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            PathBarView(model: model)
            Divider()
            content
            if !model.filterText.isEmpty {
                Divider()
                FilterBarView(model: model)
            }
        }
        .task { model.reload() }
        // Restarted on every navigation, cancelled when the pane goes away.
        .task(id: model.location) { await model.followChanges() }
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
            FileListView(
                model: model,
                items: model.items,
                location: model.location,
                selection: model.selection,
                sort: model.sort,
                onActivate: onActivate
            )
            .overlay {
                if model.items.isEmpty && !model.isLoading {
                    Group {
                        if model.filterText.isEmpty {
                            Text("Empty Folder", bundle: .module)
                        } else {
                            Text("No Matches", bundle: .module)
                        }
                    }
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .allowsHitTesting(false)
                }
            }
        }
    }
}

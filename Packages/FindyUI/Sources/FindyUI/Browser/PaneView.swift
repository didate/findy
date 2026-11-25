import FindyCore
import SwiftUI

/// One pane: its path bar on top of its file list.
struct PaneView: View {
    @Bindable var model: BrowserModel
    let isActive: Bool
    let isDualPane: Bool
    let onActivate: () -> Void
    let onSwitchPane: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // With two panes, a line marks the one that menus and shortcuts act on.
            if isDualPane {
                Rectangle()
                    .fill(isActive ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear))
                    .frame(height: 2)
                    .accessibilityHidden(true)
            }
            PathBarView(model: model)
            Divider()
            content
            if !model.filterText.isEmpty {
                Divider()
                FilterBarView(model: model)
            }
            Divider()
            StatusBarView(model: model)
        }
        .alert(
            Text("The operation couldn’t be completed.", bundle: .module),
            isPresented: Binding(
                get: { model.alertMessage != nil },
                set: { if !$0 { model.alertMessage = nil } }
            )
        ) {
            Button {
                model.alertMessage = nil
            } label: {
                Text("OK", bundle: .module)
            }
        } message: {
            Text(verbatim: model.alertMessage ?? "")
        }
        .overlay(alignment: .bottom) {
            if let progress = model.progress {
                OperationProgressView(progress: progress) { model.cancelOperation() }
            }
        }
        .sheet(item: $model.pendingTransfer) { transfer in
            ConflictSheet(transfer: transfer) { model.resolveTransfer($0) }
        }
        .task { model.reload() }
        // A click anywhere in a pane, its path bar included, makes it the active one.
        .simultaneousGesture(TapGesture().onEnded { onActivate() })
        // Restarted on every navigation, cancelled when the pane goes away.
        .task(id: model.location) { await model.followChanges() }
        .task(id: model.gitInfo?.root) { await model.followGitChanges() }
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
                renamingURL: model.renamingURL,
                gitChanges: model.gitChanges,
                cutFiles: FilePasteboard.cutFiles,
                isActive: isActive,
                onActivate: onActivate,
                onSwitchPane: onSwitchPane
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

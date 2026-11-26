import SwiftUI

/// The field where the user types what to look for under the folder shown (⌘F).
struct SearchBarView: View {
    @Bindable var model: BrowserModel
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField(text: $model.searchText) {
                Text("Search in “\(model.title)” and its subfolders", bundle: .module)
            }
            .textFieldStyle(.plain)
            .focused($isFieldFocused)
            .onExitCommand { model.endSearch() }
            if model.isSearchRunning {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel(Text("Searching…", bundle: .module))
            }
            Button {
                model.endSearch()
            } label: {
                Label {
                    Text("Close Search", bundle: .module)
                } icon: {
                    Image(systemName: "xmark.circle.fill")
                }
                .labelStyle(.iconOnly)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(.bar)
        .onAppear { isFieldFocused = true }
        // ⌘F pressed again while the bar is open puts the cursor back in the field.
        .onChange(of: model.searchFocusRequests) { isFieldFocused = true }
    }
}

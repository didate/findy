import SwiftUI

/// Shows the text the user typed to filter the list, with a way to clear it.
struct FilterBarView: View {
    let model: BrowserModel

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("Filter:", bundle: .module)
                .foregroundStyle(.secondary)
            Text(verbatim: model.filterText)
                .fontWeight(.medium)
                .lineLimit(1)
            Spacer()
            Button {
                model.clearFilter()
            } label: {
                Label {
                    Text("Clear Filter", bundle: .module)
                } icon: {
                    Image(systemName: "xmark.circle.fill")
                }
                .labelStyle(.iconOnly)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .frame(height: 26)
        .background(.bar)
    }
}

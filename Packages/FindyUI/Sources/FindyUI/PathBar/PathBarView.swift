import SwiftUI

/// Shows the current location as clickable segments, and turns into a text field to type a path (⌘L).
struct PathBarView: View {
    @Bindable var model: BrowserModel
    @State private var draft = ""
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        Group {
            if model.isEditingPath {
                field
            } else {
                crumbs
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
    }

    private var field: some View {
        TextField(text: $draft) {
            Text("Path", bundle: .module)
        }
        .textFieldStyle(.plain)
        .focused($isFieldFocused)
        .onSubmit {
            model.navigate(toPath: draft)
            model.isEditingPath = false
        }
        .onExitCommand { model.isEditingPath = false }
        .onAppear {
            draft = model.location.path
            isFieldFocused = true
        }
        .onChange(of: isFieldFocused) { _, focused in
            if !focused { model.isEditingPath = false }
        }
    }

    private var crumbs: some View {
        HStack(spacing: 2) {
            // Deep paths that do not fit keep their last segments, the ones the user is working in.
            ViewThatFits(in: .horizontal) {
                crumbRow(model.crumbs, truncated: false)
                crumbRow(Array(model.crumbs.suffix(4)), truncated: true)
                crumbRow(Array(model.crumbs.suffix(2)), truncated: true)
                crumbRow(Array(model.crumbs.suffix(1)), truncated: true)
            }
            Spacer(minLength: 0)
            if model.isBusy {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel(Text("Working…", bundle: .module))
            }
        }
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { model.isEditingPath = true }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Path", bundle: .module))
    }

    private func crumbRow(_ crumbs: [PathCrumb], truncated: Bool) -> some View {
        HStack(spacing: 2) {
            if truncated {
                Text(verbatim: "…").foregroundStyle(.secondary)
                separator
            }
            ForEach(crumbs) { crumb in
                Button {
                    model.navigate(to: crumb.url)
                } label: {
                    Text(verbatim: crumb.name).lineLimit(1)
                }
                .buttonStyle(.plain)
                .foregroundStyle(crumb.url == model.location ? .primary : .secondary)
                if crumb.url != model.location {
                    separator
                }
            }
        }
        .fixedSize()
    }

    private var separator: some View {
        Image(systemName: "chevron.right")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .accessibilityHidden(true)
    }
}

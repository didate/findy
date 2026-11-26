import FindyCore
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
            if let label = model.shownLabel {
                // The files of a color come from anywhere: there is no path to show.
                Label {
                    Text("Everything marked \(label.name)", bundle: .module).lineLimit(1)
                } icon: {
                    Image(systemName: "circle.fill").foregroundStyle(Color(nsColor: label.color))
                }
            } else {
                ViewThatFits(in: .horizontal) {
                    crumbRow(model.crumbs, truncated: false)
                    crumbRow(Array(model.crumbs.suffix(4)), truncated: true)
                    crumbRow(Array(model.crumbs.suffix(2)), truncated: true)
                    crumbRow(Array(model.crumbs.suffix(1)), truncated: true)
                }
            }
            Spacer(minLength: 0)
            // A copy or a move shows its own progress panel.
            if model.isBusy, model.progress == nil {
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
                PathCrumbButton(crumb: crumb, isCurrent: crumb.url == model.location, model: model)
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

/// One segment of the path. A click goes there; files dropped on it are moved or copied there.
private struct PathCrumbButton: View {
    let crumb: PathCrumb
    let isCurrent: Bool
    let model: BrowserModel

    @State private var isTargeted = false

    var body: some View {
        Button {
            model.navigate(to: crumb.url)
        } label: {
            Text(verbatim: crumb.name).lineLimit(1)
        }
        .buttonStyle(.plain)
        .foregroundStyle(isCurrent ? .primary : .secondary)
        .padding(.horizontal, 3)
        .padding(.vertical, 1)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isTargeted ? AnyShapeStyle(.tint.opacity(0.35)) : AnyShapeStyle(.clear))
        )
        .folderDropTarget(isTargeted: $isTargeted) { urls, move in
            model.drop(urls, into: crumb.url, move: move)
        }
    }
}

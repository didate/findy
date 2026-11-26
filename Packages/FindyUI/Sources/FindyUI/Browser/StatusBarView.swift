import FindyCore
import SwiftUI

/// The line under the list: how much is shown and selected, the space left on the volume, and
/// the Git branch when the folder is in a repository.
struct StatusBarView: View {
    let model: BrowserModel

    var body: some View {
        HStack(spacing: 12) {
            Text(verbatim: summary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            if let git = model.gitInfo {
                if let changes = model.gitChanges { changesView(changes) }
                Label {
                    Text(verbatim: git.head)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } icon: {
                    Image(systemName: git.isDetached ? "smallcircle.filled.circle" : "arrow.triangle.branch")
                }
                .help(Text(verbatim: git.root.path))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    git.isDetached
                        ? Text("Git commit \(git.head)", bundle: .module)
                        : Text("Git branch \(git.head)", bundle: .module))
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .frame(height: 24)
        .background(.bar)
    }

    /// Commits to push and to pull, then the number of changed files. Nothing when all is clean.
    @ViewBuilder private func changesView(_ changes: GitChanges) -> some View {
        if let ahead = changes.ahead, ahead > 0 {
            Text(verbatim: "↑\(ahead)")
                .accessibilityLabel(Text("\(ahead) commits to push", bundle: .module))
        }
        if let behind = changes.behind, behind > 0 {
            Text(verbatim: "↓\(behind)")
                .accessibilityLabel(Text("\(behind) commits to pull", bundle: .module))
        }
        if changes.changedFiles > 0 {
            Text("\(changes.changedFiles) changed", bundle: .module)
        }
    }

    private var summary: String {
        var parts: [String] = []
        let selected = model.selection.count
        if selected > 0 {
            parts.append(String(localized: "\(selected) of \(model.items.count) selected", bundle: .module))
            if let size = model.selectedSize {
                parts.append(size.formatted(.byteCount(style: .file)))
            }
        } else if model.showsSearchResults {
            parts.append(String(localized: "\(model.items.count) results", bundle: .module))
        } else {
            parts.append(String(localized: "\(model.items.count) items", bundle: .module))
        }
        if model.searchIsTruncated {
            parts.append(String(localized: "search stopped there, refine it to see more", bundle: .module))
        }
        // A result can come from any depth: say where the selected one is.
        if let folder = model.selectedResultFolder {
            parts.append(String(localized: "in \(folder)", bundle: .module))
        }
        if !model.showsSearchResults, let space = model.availableSpace {
            let formatted = space.formatted(.byteCount(style: .file))
            parts.append(String(localized: "\(formatted) available", bundle: .module))
        }
        return parts.joined(separator: " · ")
    }
}

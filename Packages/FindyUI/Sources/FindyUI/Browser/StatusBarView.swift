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

    private var summary: String {
        var parts: [String] = []
        let selected = model.selection.count
        if selected > 0 {
            parts.append(String(localized: "\(selected) of \(model.items.count) selected", bundle: .module))
            if let size = model.selectedSize {
                parts.append(size.formatted(.byteCount(style: .file)))
            }
        } else {
            parts.append(String(localized: "\(model.items.count) items", bundle: .module))
        }
        if let space = model.availableSpace {
            let formatted = space.formatted(.byteCount(style: .file))
            parts.append(String(localized: "\(formatted) available", bundle: .module))
        }
        return parts.joined(separator: " · ")
    }
}

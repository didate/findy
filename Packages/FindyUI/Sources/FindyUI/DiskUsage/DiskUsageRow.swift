import FindyCore
import SwiftUI

/// One line of the Disk Usage list: what it is, its size, and the share of the folder it takes.
struct DiskUsageRow: View {
    let node: DiskUsageNode
    /// From 0 to 1.
    let share: Double

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(node.kind == .folder ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .frame(width: 18)
                .accessibilityHidden(true)
            Text(verbatim: name)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            // The same figure as the percentage next to it, drawn.
            ProgressView(value: min(max(share, 0), 1))
                .frame(width: 120)
                .accessibilityHidden(true)
            Text(verbatim: share.formatted(.percent.precision(.fractionLength(share < 0.1 ? 1 : 0))))
                .foregroundStyle(.secondary)
                .frame(width: 48, alignment: .trailing)
            Text(verbatim: node.size.formatted(.byteCount(style: .file)))
                .frame(width: 80, alignment: .trailing)
        }
        .monospacedDigit()
        .accessibilityElement(children: .combine)
    }

    private var name: String {
        node.kind == .smallerFiles
            ? String(localized: "\(node.fileCount) smaller files", bundle: .module) : node.name
    }

    private var symbol: String {
        switch node.kind {
        case .folder: "folder.fill"
        case .file: "doc"
        case .smallerFiles: "doc.on.doc"
        }
    }
}

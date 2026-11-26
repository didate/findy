import FindyCore
import SwiftUI

/// The Get Info sheet: what an entry is, where it is, how big, and who may touch it.
struct InfoView: View {
    @State private var model: InfoModel
    let onDone: () -> Void

    init(target: InfoTarget, fileSystem: any FileSystemProviding, onDone: @escaping () -> Void) {
        _model = State(initialValue: InfoModel(urls: target.urls, fileSystem: fileSystem))
        self.onDone = onDone
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if let errorMessage = model.errorMessage {
                Text(verbatim: errorMessage)
                    .foregroundStyle(.secondary)
            } else {
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 8) {
                    rows
                }
            }
            HStack {
                Spacer()
                Button {
                    onDone()
                } label: {
                    Text("Done", bundle: .module)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 440)
        .task { await model.load() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: headerSymbol)
                .font(.largeTitle)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text(verbatim: title)
                .font(.headline)
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
    }

    private var headerSymbol: String {
        if model.urls.count > 1 { return "square.on.square" }
        if model.single?.linkDestination != nil { return "arrow.up.right.square" }
        return model.single?.isFolder == true ? "folder" : "doc"
    }

    private var title: String {
        if model.urls.count > 1 {
            return String(localized: "\(model.urls.count) items", bundle: .module)
        }
        return model.single?.name ?? model.urls.first?.lastPathComponent ?? ""
    }

    @ViewBuilder private var rows: some View {
        if let details = model.single {
            if let kind = details.kind { row("Kind:", kind) }
            sizeRow
            row("Where:", details.url.deletingLastPathComponent().path)
            if let destination = details.linkDestination { row("Points to:", destination) }
            if let date = details.creationDate { row("Created:", Self.format(date)) }
            if let date = details.modificationDate { row("Modified:", Self.format(date)) }
            if let owner = details.owner {
                row("Owner:", details.group.map { "\(owner) (\($0))" } ?? owner)
            }
            if let letters = details.permissionString, let bits = details.permissions {
                row("Permissions:", "\(letters) (\(String(bits, radix: 8)))")
            }
        } else if model.urls.count > 1 {
            sizeRow
            if let first = model.urls.first {
                row("Where:", first.deletingLastPathComponent().path)
            }
        }
    }

    private var sizeRow: some View {
        GridRow {
            label("Size:")
            HStack(spacing: 6) {
                Text(verbatim: sizeText)
                    .textSelection(.enabled)
                if model.isSizing {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel(Text("Calculating…", bundle: .module))
                }
            }
        }
    }

    private var sizeText: String {
        guard let size = model.totalSize else {
            return model.isSizing || model.details.isEmpty ? "—" : String(localized: "Unknown", bundle: .module)
        }
        let readable = size.formatted(.byteCount(style: .file))
        let exact = size.formatted(.number)
        var text = String(localized: "\(readable) (\(exact) bytes)", bundle: .module)
        if let onDisk = model.single?.sizeOnDisk, onDisk != size {
            let onDiskText = onDisk.formatted(.byteCount(style: .file))
            text += String(localized: ", \(onDiskText) on disk", bundle: .module)
        }
        return text
    }

    private func row(_ title: LocalizedStringKey, _ value: String) -> some View {
        GridRow {
            label(title)
            Text(verbatim: value)
                .textSelection(.enabled)
                .lineLimit(3)
                .truncationMode(.middle)
        }
    }

    private func label(_ title: LocalizedStringKey) -> some View {
        Text(title, bundle: .module)
            .foregroundStyle(.secondary)
            .gridColumnAlignment(.trailing)
    }

    private static func format(_ date: Date) -> String {
        date.formatted(date: .long, time: .shortened)
    }
}

import FindyCore
import SwiftUI

/// The Disk Usage sheet: what a folder holds, largest first, with the share each entry takes.
struct DiskUsageView: View {
    @State private var model: DiskUsageModel
    @State private var selection: DiskUsageNode.ID?
    /// Counts the scans asked for: changing it restarts the scan.
    @State private var scanRound = 0
    /// Shows an entry in the pane: its location, and whether it is a folder.
    let onReveal: (URL, Bool) -> Void
    let onDone: () -> Void

    init(
        target: DiskUsageTarget,
        fileSystem: any FileSystemProviding,
        trash: @escaping @MainActor (URL) async -> String?,
        onReveal: @escaping (URL, Bool) -> Void,
        onDone: @escaping () -> Void
    ) {
        _model = State(initialValue: DiskUsageModel(root: target.url, fileSystem: fileSystem, trash: trash))
        self.onReveal = onReveal
        self.onDone = onDone
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            breadcrumb
            content
            notes
            buttons
        }
        .padding(20)
        .frame(width: 620, height: 540)
        .task(id: scanRound) { await model.scan() }
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
    }

    // MARK: Parts

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.largeTitle)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: model.shown.size.formatted(.byteCount(style: .file)))
                    .font(.title2.weight(.semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                HStack(spacing: 6) {
                    if model.isScanning {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityHidden(true)
                        Text("Measuring… \(model.scannedFiles) files so far", bundle: .module)
                    } else {
                        Text("\(model.shown.fileCount) files, on disk", bundle: .module)
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }
            Spacer()
        }
    }

    /// The way down from the folder measured to the one shown. Each level but the last goes back to it.
    private var breadcrumb: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                let names = model.breadcrumb
                ForEach(Array(names.enumerated()), id: \.offset) { level, name in
                    if level > 0 {
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                    }
                    if level == names.count - 1 {
                        Text(verbatim: name)
                            .fontWeight(.medium)
                    } else {
                        Button {
                            model.go(toLevel: level)
                            selection = nil
                        } label: {
                            Text(verbatim: name)
                        }
                        .buttonStyle(.link)
                    }
                }
            }
        }
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
                Text(verbatim: errorMessage)
            }
            .frame(maxHeight: .infinity)
        } else {
            List(model.shown.children, selection: $selection) { node in
                DiskUsageRow(node: node, share: model.share(of: node))
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
            .contextMenu(forSelectionType: DiskUsageNode.ID.self) { ids in
                if let node = node(in: ids) {
                    if node.kind == .folder {
                        Button {
                            open(node)
                        } label: {
                            Text("Open", bundle: .module)
                        }
                    }
                    Button {
                        reveal(node)
                    } label: {
                        Text("Show in List", bundle: .module)
                    }
                    Divider()
                    Button {
                        Task { await model.moveToTrash(node) }
                    } label: {
                        Text("Move to Trash", bundle: .module)
                    }
                }
            } primaryAction: { ids in
                // Double-click or Return: go down into a folder.
                if let node = node(in: ids) { open(node) }
            }
            .overlay {
                if model.shown.children.isEmpty && !model.isScanning {
                    Text("Empty Folder", bundle: .module)
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
        }
    }

    @ViewBuilder private var notes: some View {
        VStack(alignment: .leading, spacing: 2) {
            if model.shown.unreadableCount > 0 {
                Text(
                    "\(model.shown.unreadableCount) folders couldn’t be read and are not counted.",
                    bundle: .module)
            }
            if model.hasTrashed {
                Text("The space is freed once the Trash is emptied.", bundle: .module)
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
    }

    private var buttons: some View {
        HStack {
            Button {
                model.goUp()
                selection = nil
            } label: {
                Label {
                    Text("Enclosing Folder", bundle: .module)
                } icon: {
                    Image(systemName: "chevron.up")
                }
            }
            .keyboardShortcut(.upArrow, modifiers: .command)
            .disabled(!model.canGoUp)

            Button {
                if let node = selected { reveal(node) }
            } label: {
                Text("Show in List", bundle: .module)
            }
            .disabled(selected == nil)

            Button {
                if let node = selected { Task { await model.moveToTrash(node) } }
            } label: {
                Text("Move to Trash", bundle: .module)
            }
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(selected == nil)

            Spacer()

            Button {
                selection = nil
                scanRound += 1
            } label: {
                Text("Measure Again", bundle: .module)
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(model.isScanning)

            Button {
                onDone()
            } label: {
                Text("Done", bundle: .module)
            }
            .keyboardShortcut(.cancelAction)
        }
    }

    // MARK: Actions

    /// The selected entry, when it is one that exists on disk.
    private var selected: DiskUsageNode? {
        guard let selection else { return nil }
        return node(in: [selection])
    }

    private func node(in ids: Set<DiskUsageNode.ID>) -> DiskUsageNode? {
        guard ids.count == 1, let id = ids.first else { return nil }
        return model.shown.children.first { $0.id == id && $0.kind != .smallerFiles }
    }

    private func open(_ node: DiskUsageNode) {
        model.open(node)
        selection = nil
    }

    private func reveal(_ node: DiskUsageNode) {
        guard let url = model.url(of: node) else { return }
        onReveal(url, node.kind == .folder)
        onDone()
    }
}

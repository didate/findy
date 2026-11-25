import AppKit
import FindyCore
import SwiftUI
import UniformTypeIdentifiers

/// The file list. Backed by `NSTableView` because SwiftUI lists do not hold up at 10 000+ rows.
struct FileListView: NSViewRepresentable {
    let items: [FileItem]
    @Binding var sort: FileSort
    let onOpen: (FileItem) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let tableView = NSTableView()
        tableView.style = .inset
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsMultipleSelection = true
        tableView.allowsColumnReordering = false
        tableView.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        tableView.rowHeight = 24
        tableView.setAccessibilityLabel(String(localized: "Files", bundle: .module))

        for column in Column.allCases {
            tableView.addTableColumn(column.makeTableColumn())
        }

        let coordinator = context.coordinator
        tableView.dataSource = coordinator
        tableView.delegate = coordinator
        tableView.target = coordinator
        tableView.doubleAction = #selector(Coordinator.openClickedRow(_:))
        tableView.sortDescriptors = [Column.sortDescriptor(for: sort)]
        coordinator.tableView = tableView

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        guard coordinator.items != items else { return }
        coordinator.items = items
        coordinator.tableView?.reloadData()
        coordinator.tableView?.scrollRowToVisible(0)
    }

    // MARK: Columns

    enum Column: String, CaseIterable {
        case name
        case dateModified
        case size

        var identifier: NSUserInterfaceItemIdentifier { .init(rawValue) }

        var sortKey: FileSort.Key {
            switch self {
            case .name: .name
            case .dateModified: .dateModified
            case .size: .size
            }
        }

        var title: String {
            switch self {
            case .name: String(localized: "Name", bundle: .module)
            case .dateModified: String(localized: "Date Modified", bundle: .module)
            case .size: String(localized: "Size", bundle: .module)
            }
        }

        @MainActor func makeTableColumn() -> NSTableColumn {
            let column = NSTableColumn(identifier: identifier)
            column.title = title
            column.sortDescriptorPrototype = NSSortDescriptor(key: rawValue, ascending: true)
            switch self {
            case .name:
                column.width = 320
                column.minWidth = 160
            case .dateModified:
                column.width = 170
                column.minWidth = 120
            case .size:
                column.width = 90
                column.minWidth = 70
            }
            return column
        }

        static func sortDescriptor(for sort: FileSort) -> NSSortDescriptor {
            NSSortDescriptor(key: sort.key.rawValue, ascending: sort.ascending)
        }
    }

    // MARK: Coordinator

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var parent: FileListView
        var items: [FileItem] = []
        weak var tableView: NSTableView?

        private var iconCache: [String: NSImage] = [:]
        private let dateFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            formatter.doesRelativeDateFormatting = true
            return formatter
        }()
        private let sizeFormatter: ByteCountFormatter = {
            let formatter = ByteCountFormatter()
            formatter.countStyle = .file
            return formatter
        }()

        init(_ parent: FileListView) {
            self.parent = parent
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            items.count
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard let tableColumn, let column = Column(rawValue: tableColumn.identifier.rawValue),
                items.indices.contains(row)
            else { return nil }
            let item = items[row]
            let cell = dequeueCell(in: tableView, for: column)

            switch column {
            case .name:
                cell.textField?.stringValue = item.name
                cell.imageView?.image = icon(for: item)
                // Hidden entries are dimmed, as in Finder.
                cell.textField?.textColor = item.isHidden ? .secondaryLabelColor : .labelColor
                cell.imageView?.alphaValue = item.isHidden ? 0.5 : 1
            case .dateModified:
                cell.textField?.stringValue = item.modificationDate.map(dateFormatter.string(from:)) ?? "—"
            case .size:
                cell.textField?.stringValue = item.size.map(sizeFormatter.string(fromByteCount:)) ?? "—"
            }
            return cell
        }

        func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
            guard let descriptor = tableView.sortDescriptors.first,
                let key = descriptor.key.flatMap(FileSort.Key.init(rawValue:))
            else { return }
            var sort = parent.sort
            sort.key = key
            sort.ascending = descriptor.ascending
            parent.sort = sort
        }

        @objc func openClickedRow(_ sender: NSTableView) {
            let row = sender.clickedRow
            guard items.indices.contains(row) else { return }
            parent.onOpen(items[row])
        }

        // MARK: Cells

        private func dequeueCell(in tableView: NSTableView, for column: Column) -> NSTableCellView {
            if let reused = tableView.makeView(withIdentifier: column.identifier, owner: nil) as? NSTableCellView {
                return reused
            }
            let cell = NSTableCellView()
            cell.identifier = column.identifier

            let textField = NSTextField(labelWithString: "")
            textField.translatesAutoresizingMaskIntoConstraints = false
            textField.lineBreakMode = column == .name ? .byTruncatingMiddle : .byTruncatingTail
            cell.addSubview(textField)
            cell.textField = textField

            var leading = cell.leadingAnchor
            var spacing: CGFloat = 2
            if column == .name {
                let imageView = NSImageView()
                imageView.translatesAutoresizingMaskIntoConstraints = false
                imageView.imageScaling = .scaleProportionallyUpOrDown
                cell.addSubview(imageView)
                cell.imageView = imageView
                NSLayoutConstraint.activate([
                    imageView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                    imageView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                    imageView.widthAnchor.constraint(equalToConstant: 18),
                    imageView.heightAnchor.constraint(equalToConstant: 18),
                ])
                leading = imageView.trailingAnchor
                spacing = 6
            } else {
                textField.textColor = .secondaryLabelColor
                textField.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
                if column == .size { textField.alignment = .right }
            }
            NSLayoutConstraint.activate([
                textField.leadingAnchor.constraint(equalTo: leading, constant: spacing),
                textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
            return cell
        }

        /// Icons come from the file's type, not from the file itself, so no row costs a disk access.
        private func icon(for item: FileItem) -> NSImage {
            let key = item.isFolder ? "/folder" : item.url.pathExtension.lowercased()
            if let cached = iconCache[key] { return cached }
            let type: UTType =
                if item.isFolder {
                    .folder
                } else {
                    UTType(filenameExtension: key) ?? .data
                }
            let image = NSWorkspace.shared.icon(for: type)
            iconCache[key] = image
            return image
        }
    }
}

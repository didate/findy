import AppKit
import FindyCore
import SwiftUI
import UniformTypeIdentifiers

/// The file list. Backed by `NSTableView` because SwiftUI lists do not hold up at 10 000+ rows.
///
/// `items`, `location`, `selection` and `sort` mirror the model's state: they are passed as values so
/// SwiftUI calls `updateNSView` whenever one of them changes.
struct FileListView: NSViewRepresentable {
    let model: BrowserModel
    let items: [FileItem]
    let location: URL
    let selection: Set<URL>
    let sort: FileSort
    let renamingURL: URL?
    let isActive: Bool
    let onActivate: () -> Void
    let onSwitchPane: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let tableView = FileTableView()
        tableView.style = .inset
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsMultipleSelection = true
        tableView.allowsColumnReordering = false
        tableView.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        tableView.rowHeight = 24
        tableView.setAccessibilityLabel(String(localized: "Files", bundle: .module))
        // Files can be dragged out to any app and dropped in from any app.
        tableView.registerForDraggedTypes([.fileURL])
        tableView.setDraggingSourceOperationMask([.move, .copy], forLocal: true)
        tableView.setDraggingSourceOperationMask([.move, .copy], forLocal: false)
        tableView.draggingDestinationFeedbackStyle = .regular

        for column in Column.allCases {
            tableView.addTableColumn(column.makeTableColumn())
        }

        let coordinator = context.coordinator
        tableView.dataSource = coordinator
        tableView.delegate = coordinator
        tableView.actions = coordinator
        tableView.target = coordinator
        tableView.doubleAction = #selector(Coordinator.openClickedRow(_:))
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
        coordinator.applyModelState()
        coordinator.takeFocusIfActivated(isActive)
    }

    // MARK: Columns

    enum Column: String, CaseIterable {
        case name
        case dateModified
        case size

        var identifier: NSUserInterfaceItemIdentifier { .init(rawValue) }

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
    }

    // MARK: Coordinator

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate,
        FileTableViewActions
    {
        var parent: FileListView
        weak var tableView: FileTableView?

        private var items: [FileItem] = []
        private var location: URL?
        /// True while the coordinator pushes model state into the table, so the table's delegate
        /// callbacks are not mistaken for user actions and echoed back to the model.
        private var isApplying = false
        private var wasActive = true
        /// The entry whose name is being edited in place, and its text field.
        private var editing: (url: URL, field: NSTextField)?

        /// Generic icons, by file extension. Shown at once, before the real icon is known.
        private var iconCache: [String: NSImage] = [:]
        /// Real icons already loaded, by path and modification date.
        private var loadedIcons: [String: NSImage] = [:]
        /// Icons being loaded for rows on screen, by row location.
        private var iconTasks: [URL: Task<Void, Never>] = [:]
        private static let iconPointSize: CGFloat = 18
        private static let loadedIconsLimit = 4_000
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

        private var model: BrowserModel { parent.model }

        init(_ parent: FileListView) {
            self.parent = parent
        }

        // MARK: Model → table

        func applyModelState() {
            // Reloading rows would tear down the field the user is typing in. The state is applied
            // when the edit ends.
            guard editing == nil else { return }
            // Read from the model, not from `parent`: this also runs right after an edit ends, when
            // `parent` still holds the values of the last SwiftUI update.
            apply(items: model.items, location: model.location, selection: model.selection, sort: model.sort)
            if let url = model.renamingURL { beginEditing(url) }
        }

        private func apply(
            items newItems: [FileItem], location newLocation: URL, selection: Set<URL>, sort: FileSort
        ) {
            guard let tableView else { return }
            isApplying = true
            defer { isApplying = false }

            let descriptor = NSSortDescriptor(key: sort.key.rawValue, ascending: sort.ascending)
            if tableView.sortDescriptors.first != descriptor {
                tableView.sortDescriptors = [descriptor]
            }

            let locationChanged = location != newLocation
            location = newLocation
            if locationChanged { cancelIconLoading() }
            if items != newItems {
                items = newItems
                tableView.reloadData()
                select(selection, in: tableView)
                // A refresh of the same folder must not move the user's scroll position.
                if locationChanged {
                    tableView.scrollRowToVisible(0)
                    // After navigating, typing must reach the list (arrows, instant filter).
                    // Only the active pane may take the focus: the other one refreshes too.
                    if parent.isActive { tableView.window?.makeFirstResponder(tableView) }
                }
            } else if selectedURLs(in: tableView) != selection {
                select(selection, in: tableView)
            }
        }

        private func select(_ selection: Set<URL>, in tableView: NSTableView) {
            var indexes = IndexSet()
            if !selection.isEmpty {
                for (row, item) in items.enumerated() where selection.contains(item.url) {
                    indexes.insert(row)
                }
            }
            tableView.selectRowIndexes(indexes, byExtendingSelection: false)
        }

        private func selectedURLs(in tableView: NSTableView) -> Set<URL> {
            Set(tableView.selectedRowIndexes.compactMap { items.indices.contains($0) ? items[$0].url : nil })
        }

        // MARK: Data source and delegate

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
                // Remembered so the row can tell which icon to stop loading when it scrolls away.
                cell.objectValue = item.url as NSURL
                if let loaded = loadedIcons[Self.iconKey(for: item)] {
                    cell.imageView?.image = loaded
                } else {
                    cell.imageView?.image = icon(for: item)
                    loadIcon(for: item, in: tableView)
                }
                // Hidden entries are dimmed, as in Finder.
                cell.textField?.textColor = item.isHidden ? .secondaryLabelColor : .labelColor
                cell.imageView?.alphaValue = item.isHidden ? 0.5 : 1
            case .dateModified:
                cell.textField?.stringValue = item.modificationDate.map(dateFormatter.string(from:)) ?? "—"
            case .size:
                // A link's own size (the length of its target path) means nothing to the user.
                let size = item.isSymbolicLink ? nil : item.size
                cell.textField?.stringValue = size.map(sizeFormatter.string(fromByteCount:)) ?? "—"
            }
            return cell
        }

        func tableView(_ tableView: NSTableView, didRemove rowView: NSTableRowView, forRow row: Int) {
            // The row left the screen: its icon is no longer worth computing.
            guard let cell = rowView.view(atColumn: 0) as? NSTableCellView, let url = cell.objectValue as? URL
            else { return }
            iconTasks.removeValue(forKey: url)?.cancel()
        }

        func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
            guard !isApplying, let descriptor = tableView.sortDescriptors.first,
                let key = descriptor.key.flatMap(FileSort.Key.init(rawValue:))
            else { return }
            model.sort.key = key
            model.sort.ascending = descriptor.ascending
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !isApplying, let tableView else { return }
            model.selection = selectedURLs(in: tableView)
        }

        @objc func openClickedRow(_ sender: NSTableView) {
            let row = sender.clickedRow
            guard items.indices.contains(row) else { return }
            model.open(items[row])
        }

        // MARK: Drag and drop

        func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> (any NSPasteboardWriting)? {
            // No drag while a name is being edited: the drag would start from the text field.
            guard editing == nil, items.indices.contains(row) else { return nil }
            return items[row].url as NSURL
        }

        func tableView(
            _ tableView: NSTableView, validateDrop info: any NSDraggingInfo, proposedRow row: Int,
            proposedDropOperation dropOperation: NSTableView.DropOperation
        ) -> NSDragOperation {
            let destination = dropDestination(in: tableView, row: row, dropOperation: dropOperation)
            let operation = Self.operation(for: info)
            guard operation != [],
                model.canAccept(Self.fileURLs(in: info), in: destination, move: operation == .move)
            else { return [] }
            return operation
        }

        func tableView(
            _ tableView: NSTableView, acceptDrop info: any NSDraggingInfo, row: Int,
            dropOperation: NSTableView.DropOperation
        ) -> Bool {
            let destination = dropDestination(in: tableView, row: row, dropOperation: dropOperation)
            let operation = Self.operation(for: info)
            let urls = Self.fileURLs(in: info)
            guard operation != [], model.canAccept(urls, in: destination, move: operation == .move) else {
                return false
            }
            parent.onActivate()
            model.transfer(urls, move: operation == .move, into: destination)
            return true
        }

        /// A drop on a folder row goes into that folder. Anywhere else it goes into the folder
        /// shown, and the whole list is highlighted instead of a gap between two rows.
        private func dropDestination(
            in tableView: NSTableView, row: Int, dropOperation: NSTableView.DropOperation
        ) -> URL {
            if dropOperation == .on, items.indices.contains(row), items[row].isFolder {
                return items[row].url
            }
            tableView.setDropRow(-1, dropOperation: .on)
            return model.location
        }

        /// A drag moves, and Option-drag copies, whatever the volumes involved. (Finder moves or
        /// copies depending on whether source and destination share a volume.) A source that only
        /// offers copies is copied.
        private static func operation(for info: any NSDraggingInfo) -> NSDragOperation {
            let mask = info.draggingSourceOperationMask
            // AppKit is documented to narrow the mask to `.copy` while Option is held. The key is
            // also read directly, so the rule does not depend on every source app honoring that.
            let optionHeld = NSEvent.modifierFlags.contains(.option)
            if optionHeld, mask.contains(.copy) { return .copy }
            if mask.contains(.move) { return .move }
            if mask.contains(.copy) { return .copy }
            return []
        }

        private static func fileURLs(in info: any NSDraggingInfo) -> [URL] {
            let objects = info.draggingPasteboard.readObjects(
                forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
            return objects as? [URL] ?? []
        }

        // MARK: FileTableViewActions

        func tableViewDidBecomeActive() {
            parent.onActivate()
        }

        func tableViewSwitchPane() {
            parent.onSwitchPane()
        }

        /// When the pane becomes the active one by a command (Tab, not a click), its list takes
        /// the keyboard focus.
        func takeFocusIfActivated(_ isActive: Bool) {
            defer { wasActive = isActive }
            guard isActive, !wasActive, editing == nil, let tableView, let window = tableView.window else { return }
            if window.firstResponder !== tableView { window.makeFirstResponder(tableView) }
        }

        func tableViewAppendToFilter(_ text: String) {
            model.appendToFilter(text)
        }

        func tableViewDeleteFilterBackward() -> Bool {
            model.deleteFilterBackward()
        }

        func tableViewClearFilter() -> Bool {
            model.clearFilter()
        }

        func tableViewBeginRename() {
            model.beginRenamingSelection()
        }

        var tableViewCanCopy: Bool { !model.selection.isEmpty }
        var tableViewCanPaste: Bool { FilePasteboard.hasFiles }

        func tableViewCopy() {
            model.copySelection()
        }

        func tableViewCut() {
            model.cutSelection()
        }

        func tableViewPaste() {
            model.paste()
        }

        // MARK: Context menu

        func tableViewContextMenu() -> NSMenu? {
            let count = model.selection.count
            let menu = NSMenu()
            menu.autoenablesItems = false
            addItem(to: menu, String(localized: "Open", bundle: .module), #selector(menuOpen), enabled: count > 0)
            addItem(to: menu, String(localized: "Open in Terminal", bundle: .module), #selector(menuTerminal))
            addItem(to: menu, String(localized: "Open in Editor", bundle: .module), #selector(menuEditor))
            addItem(
                to: menu, String(localized: "Add to Sidebar", bundle: .module), #selector(menuAddToSidebar),
                enabled: !model.foldersForSidebar.isEmpty)
            menu.addItem(.separator())
            addItem(
                to: menu, String(localized: "Rename", bundle: .module), #selector(menuRename), enabled: count == 1)
            addItem(
                to: menu, String(localized: "Move to Trash", bundle: .module), #selector(menuTrash),
                enabled: count > 0)
            menu.addItem(.separator())
            addItem(to: menu, String(localized: "Cut", bundle: .module), #selector(menuCut), enabled: count > 0)
            addItem(to: menu, String(localized: "Copy", bundle: .module), #selector(menuCopy), enabled: count > 0)
            addItem(
                to: menu, String(localized: "Paste", bundle: .module), #selector(menuPaste),
                enabled: FilePasteboard.hasFiles)
            addItem(to: menu, String(localized: "Copy Path", bundle: .module), #selector(menuCopyPath))
            menu.addItem(.separator())
            addItem(to: menu, String(localized: "New Folder", bundle: .module), #selector(menuNewFolder))
            return menu
        }

        private func addItem(to menu: NSMenu, _ title: String, _ action: Selector, enabled: Bool = true) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            item.isEnabled = enabled
            menu.addItem(item)
        }

        @objc private func menuOpen() { model.openSelection() }
        @objc private func menuEditor() { model.openEditor() }
        @objc private func menuCopyPath() { model.copyPath() }
        @objc private func menuTerminal() { model.openTerminal() }
        @objc private func menuAddToSidebar() { FavoritesStore.shared.add(model.foldersForSidebar) }
        @objc private func menuRename() { model.beginRenamingSelection() }
        @objc private func menuTrash() { model.trashSelection() }
        @objc private func menuNewFolder() { model.newFolder() }
        @objc private func menuCut() { model.cutSelection() }
        @objc private func menuCopy() { model.copySelection() }
        @objc private func menuPaste() { model.paste() }

        // MARK: Renaming in place

        private func beginEditing(_ url: URL) {
            guard let tableView, let row = items.firstIndex(where: { $0.url == url }) else {
                model.cancelRename()
                return
            }
            tableView.scrollRowToVisible(row)
            guard let cell = tableView.view(atColumn: 0, row: row, makeIfNecessary: true) as? NSTableCellView,
                let field = cell.textField
            else {
                model.cancelRename()
                return
            }
            editing = (url, field)
            field.isEditable = true
            field.drawsBackground = true
            field.backgroundColor = .textBackgroundColor
            field.textColor = .labelColor
            field.delegate = self
            tableView.window?.makeFirstResponder(field)
            // Select the name without its extension, so typing replaces only the name.
            let name = items[row].name as NSString
            let stemLength = items[row].isDirectory ? name.length : (name.deletingPathExtension as NSString).length
            let length = stemLength > 0 ? stemLength : name.length
            field.currentEditor()?.selectedRange = NSRange(location: 0, length: length)
        }

        /// Puts the field back to a plain label and gives the list the focus and its latest state.
        private func endEditing() -> (url: URL, text: String)? {
            guard let (url, field) = editing else { return nil }
            let text = field.stringValue
            editing = nil
            field.delegate = nil
            field.isEditable = false
            field.drawsBackground = false
            // Until the rename lands and the list refreshes, the row keeps showing the real name.
            field.stringValue = url.lastPathComponent
            tableView?.window?.makeFirstResponder(tableView)
            return (url, text)
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            guard let (url, text) = endEditing() else { return }
            model.commitRename(of: url, to: text)
            applyModelState()
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard selector == #selector(NSResponder.cancelOperation(_:)), editing != nil else { return false }
            // Escape: detach first, so aborting the edit is not taken for a commit.
            control.abortEditing()
            _ = endEditing()
            model.cancelRename()
            applyModelState()
            return true
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

        // MARK: Icons

        private static func iconKey(for item: FileItem) -> String {
            "\(item.url.path)|\(item.modificationDate?.timeIntervalSinceReferenceDate ?? 0)"
        }

        /// Loads the item's real icon in the background and puts it in its row if still on screen.
        private func loadIcon(for item: FileItem, in tableView: NSTableView) {
            let url = item.url
            guard iconTasks[url] == nil else { return }
            let key = Self.iconKey(for: item)
            let provider = model.iconProvider
            let scale = tableView.window?.backingScaleFactor ?? 2
            iconTasks[url] = Task { [weak self, weak tableView] in
                let image = await provider.icon(for: url, pointSize: Self.iconPointSize, scale: scale)
                // A cancelled task was already removed from `iconTasks` by whoever cancelled it.
                guard let self, !Task.isCancelled else { return }
                iconTasks[url] = nil
                guard let image else { return }
                // Previews are not always square: keep their proportions within the icon's box.
                let longestSide = CGFloat(max(image.width, image.height, 1))
                let size = NSSize(
                    width: Self.iconPointSize * CGFloat(image.width) / longestSide,
                    height: Self.iconPointSize * CGFloat(image.height) / longestSide)
                let icon = NSImage(cgImage: image, size: size)
                if loadedIcons.count >= Self.loadedIconsLimit { loadedIcons.removeAll() }
                loadedIcons[key] = icon
                guard let tableView, let row = items.firstIndex(where: { $0.url == url }),
                    let cell = tableView.view(atColumn: 0, row: row, makeIfNecessary: false) as? NSTableCellView
                else { return }
                cell.imageView?.image = icon
            }
        }

        private func cancelIconLoading() {
            for task in iconTasks.values { task.cancel() }
            iconTasks.removeAll()
        }

        /// The generic icon of the file's type. It costs no disk access, so every row has a
        /// picture at once; the real icon replaces it when it arrives.
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

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
    /// Passed so the badges are redrawn when Git reports something new.
    let gitChanges: GitChanges?
    /// Passed so the rows are redrawn when files are cut or stop being cut.
    let cutFiles: Set<URL>
    /// Passed so the sections appear or go away when the option changes.
    let groupsByDate: Bool
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
        // Section headings scroll with their rows: a floating one would hide the first row of
        // an inset list while it is being selected.
        tableView.floatsGroupRows = false
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

        /// What a table row shows: a file, or the heading of a section when the list is grouped.
        private enum Row {
            case heading(DateGroup)
            case item(FileItem)
        }

        private var items: [FileItem] = []
        /// `items` with a heading before each section. The same as `items` when nothing is grouped.
        private var rows: [Row] = []
        private var isGrouped = false
        private var location: URL?
        /// True while the coordinator pushes model state into the table, so the table's delegate
        /// callbacks are not mistaken for user actions and echoed back to the model.
        private var isApplying = false
        private var gitChanges: GitChanges?
        private var cutFiles: Set<URL> = []
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
            if items != newItems || isGrouped != model.groupsByDate {
                items = newItems
                isGrouped = model.groupsByDate
                rebuildRows()
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
            if gitChanges != model.gitChanges || cutFiles != parent.cutFiles {
                gitChanges = model.gitChanges
                cutFiles = parent.cutFiles
                // Only the names show these. Reloading that column keeps the selection.
                tableView.reloadData(
                    forRowIndexes: IndexSet(integersIn: 0..<rows.count), columnIndexes: IndexSet(integer: 0))
            }
        }

        /// The model lists the files already in section order: a heading goes wherever the
        /// section changes.
        private func rebuildRows() {
            guard isGrouped else {
                rows = items.map(Row.item)
                return
            }
            var result: [Row] = []
            result.reserveCapacity(items.count + 8)
            var current: DateGroup?
            for item in items {
                let group = model.dateGroup(of: item)
                if group != current {
                    result.append(.heading(group))
                    current = group
                }
                result.append(.item(item))
            }
            rows = result
        }

        private func item(at row: Int) -> FileItem? {
            guard rows.indices.contains(row), case .item(let item) = rows[row] else { return nil }
            return item
        }

        private func row(of url: URL) -> Int? {
            rows.firstIndex { row in
                if case .item(let item) = row { item.url == url } else { false }
            }
        }

        private func select(_ selection: Set<URL>, in tableView: NSTableView) {
            var indexes = IndexSet()
            if !selection.isEmpty {
                for (row, entry) in rows.enumerated() {
                    if case .item(let item) = entry, selection.contains(item.url) { indexes.insert(row) }
                }
            }
            tableView.selectRowIndexes(indexes, byExtendingSelection: false)
        }

        private func selectedURLs(in tableView: NSTableView) -> Set<URL> {
            Set(tableView.selectedRowIndexes.compactMap { item(at: $0)?.url })
        }

        // MARK: Data source and delegate

        func numberOfRows(in tableView: NSTableView) -> Int {
            rows.count
        }

        func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool {
            rows.indices.contains(row) && item(at: row) == nil
        }

        func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
            // A heading is not a file: the arrow keys step over it.
            item(at: row) != nil
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard rows.indices.contains(row) else { return nil }
            if case .heading(let group) = rows[row] {
                return headingCell(in: tableView, titled: group.title)
            }
            guard let tableColumn, let column = Column(rawValue: tableColumn.identifier.rawValue),
                let item = item(at: row)
            else { return nil }
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
                // So are the entries Git ignores: build products, dependencies.
                let state = model.gitState(of: item)
                // And the files that were cut, until they are pasted somewhere.
                let isDimmed = item.isHidden || state == .ignored || cutFiles.contains(item.url)
                cell.textField?.textColor = isDimmed ? .secondaryLabelColor : .labelColor
                cell.imageView?.alphaValue = isDimmed ? 0.5 : 1
                (cell as? FileNameCellView)?.show(state.flatMap(GitBadge.init))
                (cell as? FileNameCellView)?.show(item.label)
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
            self.tableView?.selectionDidChangeForQuickLook()
        }

        @objc func openClickedRow(_ sender: NSTableView) {
            guard let item = item(at: sender.clickedRow) else { return }
            model.open(item)
        }

        // MARK: Drag and drop

        func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> (any NSPasteboardWriting)? {
            // No drag while a name is being edited: the drag would start from the text field.
            guard editing == nil, let item = item(at: row) else { return nil }
            return item.url as NSURL
        }

        func tableView(
            _ tableView: NSTableView, validateDrop info: any NSDraggingInfo, proposedRow row: Int,
            proposedDropOperation dropOperation: NSTableView.DropOperation
        ) -> NSDragOperation {
            let destination = dropDestination(in: tableView, row: row, dropOperation: dropOperation)
            let operation = Self.operation(for: info)
            guard operation != [], acceptsDrop(in: destination),
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
            guard operation != [], acceptsDrop(in: destination),
                model.canAccept(urls, in: destination, move: operation == .move)
            else { return false }
            parent.onActivate()
            model.transfer(urls, move: operation == .move, into: destination)
            return true
        }

        /// A drop on a folder row goes into that folder. Anywhere else it goes into the folder
        /// shown, and the whole list is highlighted instead of a gap between two rows.
        private func dropDestination(
            in tableView: NSTableView, row: Int, dropOperation: NSTableView.DropOperation
        ) -> URL {
            if dropOperation == .on, let item = item(at: row), item.isFolder {
                return item.url
            }
            tableView.setDropRow(-1, dropOperation: .on)
            return model.location
        }

        /// Whether a drop outside a folder row has a folder to land in. The files of a color come
        /// from anywhere: there is no folder behind that list.
        private func acceptsDrop(in destination: URL) -> Bool {
            model.shownLabel == nil || destination != model.location
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

        var tableViewIsFiltering: Bool { !model.filterText.isEmpty }

        var tableViewPreviewURLs: [URL] { model.selectedItems.map(\.url) }

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
            if let openWith = openWithItem() { menu.addItem(openWith) }
            addItem(to: menu, String(localized: "Get Info", bundle: .module), #selector(menuGetInfo))
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
            addItem(
                to: menu, String(localized: "Duplicate", bundle: .module), #selector(menuDuplicate),
                enabled: count > 0)
            if count > 0 { menu.addItem(labelItem()) }
            addItem(to: menu, String(localized: "Copy Path", bundle: .module), #selector(menuCopyPath))
            addItem(to: menu, String(localized: "Show in Finder", bundle: .module), #selector(menuShowInFinder))
            menu.addItem(.separator())
            addItem(to: menu, String(localized: "New Folder", bundle: .module), #selector(menuNewFolder))
            addItem(to: menu, String(localized: "New File", bundle: .module), #selector(menuNewFile))
            return menu
        }

        /// The Open With submenu, for a selection made of files only. The applications offered are
        /// those that can open the first selected file.
        private func openWithItem() -> NSMenuItem? {
            let selected = model.selectedItems
            guard let first = selected.first, !selected.contains(where: \.isFolder) else { return nil }
            let submenu = NSMenu()
            submenu.autoenablesItems = false
            for (index, choice) in ApplicationChoice.choices(for: first.url).enumerated() {
                let title =
                    index == 0 ? String(localized: "\(choice.name) (default)", bundle: .module) : choice.name
                let item = NSMenuItem(title: title, action: #selector(menuOpenWith(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = choice.url
                let icon = NSWorkspace.shared.icon(forFile: choice.url.path)
                icon.size = NSSize(width: 16, height: 16)
                item.image = icon
                submenu.addItem(item)
                if index == 0 { submenu.addItem(.separator()) }
            }
            if submenu.items.isEmpty {
                let none = NSMenuItem(
                    title: String(localized: "No Application Found", bundle: .module), action: nil, keyEquivalent: "")
                none.isEnabled = false
                submenu.addItem(none)
            }
            let item = NSMenuItem(
                title: String(localized: "Open With", bundle: .module), action: nil, keyEquivalent: "")
            item.submenu = submenu
            return item
        }

        /// The Color Label submenu: the seven colors, the current one checked, and a way to remove it.
        private func labelItem() -> NSMenuItem {
            let current = model.selectionLabel
            let submenu = NSMenu()
            submenu.autoenablesItems = false
            for label in FileLabel.menuOrder {
                let item = NSMenuItem(title: label.name, action: #selector(menuSetLabel(_:)), keyEquivalent: "")
                item.target = self
                item.tag = label.rawValue
                item.image = label.menuImage
                item.state = label == current ? .on : .off
                submenu.addItem(item)
            }
            submenu.addItem(.separator())
            let none = NSMenuItem(
                title: String(localized: "No Color", bundle: .module), action: #selector(menuSetLabel(_:)),
                keyEquivalent: "")
            none.target = self
            none.tag = 0
            submenu.addItem(none)
            let item = NSMenuItem(
                title: String(localized: "Color Label", bundle: .module), action: nil, keyEquivalent: "")
            item.submenu = submenu
            return item
        }

        @objc private func menuSetLabel(_ sender: NSMenuItem) {
            model.setLabel(FileLabel(rawValue: sender.tag))
        }

        @objc private func menuOpenWith(_ sender: NSMenuItem) {
            guard let application = sender.representedObject as? URL else { return }
            model.openSelection(withApplicationAt: application)
        }

        private func addItem(to menu: NSMenu, _ title: String, _ action: Selector, enabled: Bool = true) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            item.isEnabled = enabled
            menu.addItem(item)
        }

        @objc private func menuOpen() { model.openSelection() }
        @objc private func menuEditor() { model.openEditor() }
        @objc private func menuGetInfo() { model.getInfo() }
        @objc private func menuCopyPath() { model.copyPath() }
        @objc private func menuDuplicate() { model.duplicateSelection() }
        @objc private func menuShowInFinder() { model.showInFinder() }
        @objc private func menuTerminal() { model.openTerminal() }
        @objc private func menuAddToSidebar() { FavoritesStore.shared.add(model.foldersForSidebar) }
        @objc private func menuRename() { model.beginRenamingSelection() }
        @objc private func menuTrash() { model.trashSelection() }
        @objc private func menuNewFolder() { model.newFolder() }
        @objc private func menuNewFile() { model.newFile() }
        @objc private func menuCut() { model.cutSelection() }
        @objc private func menuCopy() { model.copySelection() }
        @objc private func menuPaste() { model.paste() }

        // MARK: Renaming in place

        private func beginEditing(_ url: URL) {
            guard let tableView, let row = row(of: url), let item = item(at: row) else {
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
            let name = item.name as NSString
            let stemLength = item.isDirectory ? name.length : (name.deletingPathExtension as NSString).length
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

        private static let headingIdentifier = NSUserInterfaceItemIdentifier("heading")

        /// The heading of a section. It spans the whole row.
        private func headingCell(in tableView: NSTableView, titled title: String) -> NSTableCellView {
            let cell: NSTableCellView
            if let reused = tableView.makeView(withIdentifier: Self.headingIdentifier, owner: nil)
                as? NSTableCellView
            {
                cell = reused
            } else {
                cell = NSTableCellView()
                cell.identifier = Self.headingIdentifier
                let textField = NSTextField(labelWithString: "")
                textField.translatesAutoresizingMaskIntoConstraints = false
                textField.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
                textField.textColor = .secondaryLabelColor
                textField.lineBreakMode = .byTruncatingTail
                cell.addSubview(textField)
                cell.textField = textField
                NSLayoutConstraint.activate([
                    textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 26),
                    textField.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -4),
                    textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                ])
            }
            cell.textField?.stringValue = title
            return cell
        }

        private func dequeueCell(in tableView: NSTableView, for column: Column) -> NSTableCellView {
            if let reused = tableView.makeView(withIdentifier: column.identifier, owner: nil) as? NSTableCellView {
                return reused
            }
            let cell = column == .name ? FileNameCellView() : NSTableCellView()
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
            var trailing = cell.trailingAnchor
            if let nameCell = cell as? FileNameCellView {
                let badge = nameCell.badgeField
                badge.translatesAutoresizingMaskIntoConstraints = false
                badge.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
                badge.alignment = .center
                // The badge keeps its width; a long name is the one that gets truncated.
                badge.setContentHuggingPriority(.required, for: .horizontal)
                badge.setContentCompressionResistancePriority(.required, for: .horizontal)
                textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
                cell.addSubview(badge)
                let dot = nameCell.labelDot
                dot.translatesAutoresizingMaskIntoConstraints = false
                dot.image = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: nil)
                dot.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 9, weight: .regular)
                dot.setContentHuggingPriority(.required, for: .horizontal)
                dot.setContentCompressionResistancePriority(.required, for: .horizontal)
                cell.addSubview(dot)
                NSLayoutConstraint.activate([
                    badge.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
                    badge.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                    dot.trailingAnchor.constraint(equalTo: badge.leadingAnchor, constant: -4),
                    dot.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                ])
                trailing = dot.leadingAnchor
            }
            NSLayoutConstraint.activate([
                textField.leadingAnchor.constraint(equalTo: leading, constant: spacing),
                textField.trailingAnchor.constraint(equalTo: trailing, constant: -4),
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
                guard let tableView, let row = row(of: url),
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

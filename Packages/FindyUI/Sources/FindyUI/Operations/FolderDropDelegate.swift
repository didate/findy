import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Lets a SwiftUI view that stands for a folder (a sidebar row, a path segment) receive files.
///
/// Same rule as in the list: a drop moves, and a drop with Option held copies.
struct FolderDropDelegate: DropDelegate {
    /// Set while files hover over the view, so it can highlight itself.
    @Binding var isTargeted: Bool
    /// Called with the dropped files and whether to move (`true`) or copy them.
    let onDrop: @MainActor ([URL], Bool) -> Void

    private static var isCopy: Bool {
        NSEvent.modifierFlags.contains(.option)
    }

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.fileURL])
    }

    func dropEntered(info: DropInfo) {
        isTargeted = true
    }

    func dropExited(info: DropInfo) {
        isTargeted = false
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: Self.isCopy ? .copy : .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        isTargeted = false
        let providers = info.itemProviders(for: [.fileURL])
        guard !providers.isEmpty else { return false }
        let move = !Self.isCopy
        let onDrop = onDrop
        Task { @MainActor in
            var urls: [URL] = []
            for provider in providers {
                if let url = await Self.fileURL(from: provider) { urls.append(url) }
            }
            if !urls.isEmpty { onDrop(urls, move) }
        }
        return true
    }

    /// The system hands dropped files over asynchronously, one provider per file.
    static func fileURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                continuation.resume(returning: url)
            }
        }
    }
}

extension View {
    /// Makes the view accept dropped files on behalf of a folder.
    func folderDropTarget(
        isTargeted: Binding<Bool>, onDrop: @escaping @MainActor ([URL], Bool) -> Void
    ) -> some View {
        self.onDrop(of: [.fileURL], delegate: FolderDropDelegate(isTargeted: isTargeted, onDrop: onDrop))
    }
}

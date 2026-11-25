import FindyCore
import SwiftUI

struct SidebarView: View {
    let model: SidebarModel
    /// The location shown in the browser, highlighted when it matches a row.
    let location: URL
    let onSelect: (URL) -> Void
    /// Files were dropped on a row: the folder it stands for, the files, and whether to move them.
    let onDrop: (URL, [URL], Bool) -> Void

    var body: some View {
        List(selection: selection) {
            Section {
                ForEach(model.favorites) { favorite in
                    SidebarRow(name: favorite.name, systemImage: favorite.systemImage) { urls, move in
                        onDrop(favorite.url, urls, move)
                    }
                    .tag(favorite.url)
                }
            } header: {
                Text("Favorites", bundle: .module)
            }
            Section {
                ForEach(model.volumes) { volume in
                    SidebarRow(name: volume.name, systemImage: "internaldrive") { urls, move in
                        onDrop(volume.url, urls, move)
                    }
                    .tag(volume.url.canonicalLocation)
                }
            } header: {
                Text("Locations", bundle: .module)
            }
        }
        .listStyle(.sidebar)
    }

    private var selection: Binding<URL?> {
        Binding(
            get: { location },
            set: { url in
                if let url { onSelect(url) }
            }
        )
    }
}

/// One sidebar entry. It lights up while files hover over it and takes them when dropped.
private struct SidebarRow: View {
    let name: String
    let systemImage: String
    let onDrop: @MainActor ([URL], Bool) -> Void

    @State private var isTargeted = false

    var body: some View {
        Label(name, systemImage: systemImage)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .listRowBackground(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isTargeted ? AnyShapeStyle(.tint.opacity(0.35)) : AnyShapeStyle(.clear))
                    .padding(.horizontal, 6)
            )
            .folderDropTarget(isTargeted: $isTargeted, onDrop: onDrop)
    }
}

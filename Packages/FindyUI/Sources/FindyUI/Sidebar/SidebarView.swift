import FindyCore
import SwiftUI

struct SidebarView: View {
    @Bindable var model: SidebarModel
    /// What the browser shows, highlighted when it matches a row.
    let shown: SidebarSelection
    let onSelect: (SidebarSelection) -> Void
    /// Files were dropped on a row: the folder it stands for, the files, and whether to move them.
    let onDrop: (URL, [URL], Bool) -> Void
    /// The user asked to eject a volume.
    let onEject: (Volume) -> Void

    var body: some View {
        List(selection: selection) {
            Section {
                ForEach(model.favorites) { favorite in
                    SidebarRow(name: favorite.name, systemImage: favorite.systemImage) { urls, move in
                        onDrop(favorite.url, urls, move)
                    }
                    .tag(SidebarSelection.folder(favorite.url))
                    .contextMenu {
                        Button {
                            model.removeFavorite(favorite.url)
                        } label: {
                            Text("Remove from Sidebar", bundle: .module)
                        }
                    }
                }
                .onMove { source, destination in
                    model.moveFavorites(fromOffsets: source, toOffset: destination)
                }
                // Folders dropped between two rows become favorites, at that place.
                .onInsert(of: [.fileURL]) { index, providers in
                    Task {
                        var urls: [URL] = []
                        for provider in providers {
                            if let url = await FolderDropDelegate.fileURL(from: provider) { urls.append(url) }
                        }
                        await model.addFavorites(urls, at: index)
                    }
                }
            } header: {
                Text("Favorites", bundle: .module)
            }
            Section {
                ForEach(model.cloudLocations) { location in
                    SidebarRow(name: location.name, systemImage: model.systemImage(forCloudLocation: location)) {
                        urls, move in
                        onDrop(location.url, urls, move)
                    }
                    .tag(SidebarSelection.folder(location.url))
                }
                SidebarRow(name: model.home.name, systemImage: model.home.systemImage) { urls, move in
                    onDrop(model.home.url, urls, move)
                }
                .tag(SidebarSelection.folder(model.home.url))
                ForEach(model.volumes) { volume in
                    HStack(spacing: 4) {
                        SidebarRow(
                            name: volume.name, systemImage: volume.isEjectable ? "externaldrive" : "internaldrive"
                        ) { urls, move in
                            onDrop(volume.url, urls, move)
                        }
                        if volume.isEjectable {
                            Button {
                                onEject(volume)
                            } label: {
                                Label {
                                    Text("Eject \(volume.name)", bundle: .module)
                                } icon: {
                                    Image(systemName: "eject.fill")
                                }
                                .labelStyle(.iconOnly)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                        }
                    }
                    .tag(SidebarSelection.folder(volume.url.canonicalLocation))
                    .contextMenu {
                        if volume.isEjectable {
                            Button {
                                onEject(volume)
                            } label: {
                                Text("Eject", bundle: .module)
                            }
                        }
                    }
                }
            } header: {
                Text("Locations", bundle: .module)
            }
            Section {
                ForEach(FileLabel.menuOrder, id: \.self) { label in
                    Label {
                        Text(verbatim: label.name)
                    } icon: {
                        Image(systemName: "circle.fill").foregroundStyle(Color(nsColor: label.color))
                    }
                    .tag(SidebarSelection.label(label))
                }
            } header: {
                Text("Tags", bundle: .module)
            }
        }
        .listStyle(.sidebar)
        .alert(
            Text("The volume couldn’t be ejected.", bundle: .module),
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

    private var selection: Binding<SidebarSelection?> {
        Binding(
            get: { shown },
            set: { selected in
                if let selected { onSelect(selected) }
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

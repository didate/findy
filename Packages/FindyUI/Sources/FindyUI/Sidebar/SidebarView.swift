import FindyCore
import SwiftUI

struct SidebarView: View {
    let model: SidebarModel
    /// The location shown in the browser, highlighted when it matches a row.
    let location: URL
    let onSelect: (URL) -> Void

    var body: some View {
        List(selection: selection) {
            Section {
                ForEach(model.favorites) { favorite in
                    Label(favorite.name, systemImage: favorite.systemImage)
                        .tag(favorite.url)
                }
            } header: {
                Text("Favorites", bundle: .module)
            }
            Section {
                ForEach(model.volumes) { volume in
                    Label(volume.name, systemImage: "internaldrive")
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

import AppKit
import UniformTypeIdentifiers

/// An application offered by Open With.
struct ApplicationChoice: Identifiable, Hashable {
    let url: URL
    let name: String

    var id: URL { url }

    /// The applications that say they can open `file`, the default one first, then by name.
    /// Asked of Launch Services, which answers from its own database without reading the file.
    @MainActor
    static func choices(for file: URL) -> [ApplicationChoice] {
        let workspace = NSWorkspace.shared
        let preferred = workspace.urlForApplication(toOpen: file)
        var seen: Set<String> = []
        var others: [ApplicationChoice] = []
        for url in workspace.urlsForApplications(toOpen: file) where url != preferred {
            let choice = ApplicationChoice(url: url)
            // The same app is often registered twice (a copy in a disk image, an old version).
            if seen.insert(choice.name).inserted { others.append(choice) }
        }
        others.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        let first = preferred.map { [ApplicationChoice(url: $0)] } ?? []
        return first + others.filter { $0.name != first.first?.name }
    }

    init(url: URL) {
        self.url = url
        name = url.deletingPathExtension().lastPathComponent
    }
}

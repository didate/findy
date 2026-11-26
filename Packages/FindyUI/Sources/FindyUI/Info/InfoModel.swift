import FindyCore
import Foundation
import Observation

/// Loads what the Get Info sheet shows. Details come first; the size of folders, which has to be
/// added up, fills in afterwards.
@MainActor
@Observable
public final class InfoModel {
    public let urls: [URL]
    /// The details of each entry that could be read, in the order asked.
    public private(set) var details: [FileDetails] = []
    /// The sizes added up, folders included. `nil` until at least one size is known.
    public private(set) var totalSize: Int64?
    /// True while folder sizes are still being added up.
    public private(set) var isSizing = false
    /// Why the entry could not be read, when none could.
    public private(set) var errorMessage: String?

    private let fileSystem: any FileSystemProviding

    public init(urls: [URL], fileSystem: any FileSystemProviding = LocalFileSystem()) {
        self.urls = urls
        self.fileSystem = fileSystem
    }

    /// The only entry, when Get Info was asked about exactly one.
    public var single: FileDetails? {
        urls.count == 1 ? details.first : nil
    }

    /// Runs until everything is loaded. Cancelled with the task of the view that shows it.
    public func load() async {
        var loaded: [FileDetails] = []
        var firstError: (any Error)?
        for url in urls {
            do {
                loaded.append(try await fileSystem.details(of: url))
            } catch {
                firstError = firstError ?? error
            }
        }
        guard !Task.isCancelled else { return }
        details = loaded
        if loaded.isEmpty { errorMessage = firstError?.localizedDescription }

        let files = loaded.compactMap(\.size)
        if !files.isEmpty { totalSize = files.reduce(0, +) }
        let folders = loaded.filter(\.isFolder)
        guard !folders.isEmpty else { return }
        isSizing = true
        for folder in folders {
            // A folder that cannot be measured leaves the total short rather than missing.
            if let size = try? await fileSystem.directorySize(of: folder.url) {
                guard !Task.isCancelled else { return }
                totalSize = (totalSize ?? 0) + size
            }
        }
        isSizing = false
    }
}

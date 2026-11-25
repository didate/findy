import FindyCore
import Foundation

/// Turns an error into a sentence for the user.
enum ErrorMessage {
    static func text(for error: any Error) -> String {
        switch error as? FileOperationError {
        case .nameAlreadyExists(let url):
            String(
                localized: "An item named “\(url.lastPathComponent)” already exists in this location.",
                bundle: .module)
        case .invalidName(let name):
            String(localized: "“\(name)” can’t be used as a name.", bundle: .module)
        case .destinationInsideSource(let source, _):
            String(localized: "“\(source.lastPathComponent)” can’t be copied or moved into itself.", bundle: .module)
        case nil:
            // System errors already name the file and the cause, in the user's language.
            error.localizedDescription
        }
    }
}

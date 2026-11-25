import CoreGraphics
import Foundation
import QuickLookThumbnailing

/// Icons and previews from the system's Quick Look thumbnail service, which works off the main
/// thread and keeps its own cache on disk.
public struct QuickLookIconProvider: IconProviding {
    /// `SF_DATALESS`: the file's content is not on this Mac (iCloud, Google Drive…).
    private static let datalessFlag: UInt32 = 0x4000_0000

    public init() {}

    public func icon(for url: URL, pointSize: CGFloat, scale: CGFloat) async -> CGImage? {
        // A preview needs the content. For a cloud-only file that would mean downloading it just
        // to draw a 18-point picture, so those only get the icon of their type.
        let types: QLThumbnailGenerator.Request.RepresentationTypes =
            Self.isDataless(url) ? .icon : [.icon, .thumbnail]
        let request = QLThumbnailGenerator.Request(
            fileAt: url, size: CGSize(width: pointSize, height: pointSize), scale: scale,
            representationTypes: types)
        request.iconMode = true

        // Safe to share with the cancellation handler: the request is not mutated after this
        // point, and the generator's methods may be called from any thread.
        nonisolated(unsafe) let sharedRequest = request
        return await withTaskCancellationHandler {
            // Any failure (unreadable file, no preview for this type) means "no icon".
            try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: sharedRequest).cgImage
        } onCancel: {
            QLThumbnailGenerator.shared.cancel(sharedRequest)
        }
    }

    private static func isDataless(_ url: URL) -> Bool {
        var info = stat()
        return lstat(url.path, &info) == 0 && info.st_flags & datalessFlag != 0
    }
}

import CoreGraphics
import Foundation

/// Supplies the picture shown next to a file's name.
public protocol IconProviding: Sendable {
    /// The icon of the item at `url`: an app's own icon, a folder's custom icon, a preview of an
    /// image or a document. `nil` when none can be produced; the caller keeps its generic icon.
    ///
    /// - Parameters:
    ///   - pointSize: the side of the square the icon is drawn in, in points.
    ///   - scale: pixels per point of the display.
    func icon(for url: URL, pointSize: CGFloat, scale: CGFloat) async -> CGImage?
}

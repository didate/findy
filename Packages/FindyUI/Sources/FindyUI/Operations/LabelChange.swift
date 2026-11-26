import FindyCore
import Foundation

/// The color of one item, before and after a change, so the change can be undone.
struct LabelChange: Hashable, Sendable {
    let url: URL
    let old: FileLabel?
    let new: FileLabel?

    var reversed: LabelChange {
        LabelChange(url: url, old: new, new: old)
    }
}

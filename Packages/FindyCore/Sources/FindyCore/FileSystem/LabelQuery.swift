import CoreServices
import Foundation

/// Asks Spotlight which files carry a color label.
enum LabelQuery {
    /// The paths of everything marked with `label` on the local volumes. Blocks until the index
    /// has answered (70 ms for an empty answer on macOS 26.3): call it off the main thread.
    static func paths(labeled label: FileLabel) -> [String] {
        let predicate = predicate(for: label) as CFString
        guard let query = MDQueryCreate(kCFAllocatorDefault, predicate, nil, nil) else { return [] }
        MDQuerySetSearchScope(query, [kMDQueryScopeComputer] as CFArray, 0)
        // Synchronous: the query gathers on the calling thread and needs no run loop.
        guard MDQueryExecute(query, CFOptionFlags(kMDQuerySynchronous.rawValue)) else { return [] }
        var paths: [String] = []
        for index in 0..<MDQueryGetResultCount(query) {
            if Task.isCancelled { break }
            guard let pointer = MDQueryGetResultAtIndex(query, index) else { continue }
            // The query hands out its results as untyped pointers to items it keeps alive.
            let item = Unmanaged<MDItem>.fromOpaque(pointer).takeUnretainedValue()
            if let path = MDItemCopyAttribute(item, kMDItemPath) as? String { paths.append(path) }
        }
        return paths
    }

    /// Finder flags a labeled folder may carry besides its label: extension hidden, inited, custom
    /// icon, bundle, invisible.
    private static let otherFlags = [0x0010, 0x0100, 0x0400, 0x2000, 0x4000]

    /// The Spotlight query for `label`.
    ///
    /// `kMDItemFSLabel` is the Finder label number, the value `FileLabel` stores, but the index
    /// only answers it for files: a folder marked with a color is not found by it (macOS 26.3).
    /// Folders are found by their Finder flags instead, whose bits 1 to 3 hold the label. A query
    /// cannot mask bits, so it names the label alone and with each mix of the flags a folder
    /// commonly carries. A folder with a rarer mix is missed; nothing is found by mistake, since
    /// the caller reads the label of every entry again.
    static func predicate(for label: FileLabel) -> String {
        let labelBits = label.rawValue << 1
        var terms = ["kMDItemFSLabel == \(label.rawValue)"]
        for mix in 0..<(1 << otherFlags.count) {
            var flags = labelBits
            for (bit, flag) in otherFlags.enumerated() where mix & (1 << bit) != 0 { flags |= flag }
            terms.append("kMDItemFSFinderFlags == \(flags)")
        }
        return terms.joined(separator: " || ")
    }
}

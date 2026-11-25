import Foundation
import os

/// Adds up the bytes a copy reports from its own thread, for the main thread to read now and then.
///
/// A lock, and not a stream of updates: the copy reports thousands of times per second, far more
/// than the interface can consume one by one, and a queue of updates makes the progress bar trail
/// seconds behind the copy. The callback comes from a C API (`copyfile`), outside any actor.
final class ByteCounter: Sendable {
    private let total = OSAllocatedUnfairLock(initialState: Int64(0))

    func add(_ bytes: Int64) {
        total.withLock { $0 += bytes }
    }

    var value: Int64 {
        total.withLock { $0 }
    }
}

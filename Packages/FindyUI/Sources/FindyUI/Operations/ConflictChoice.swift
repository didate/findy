import Foundation

/// What to do with an incoming item whose name is already taken at the destination.
public enum ConflictChoice: Sendable {
    /// Bring it in under a free name (`photo 2.jpg`). The default: nothing is lost.
    case keepBoth
    /// Send the existing item to the Trash, then bring the new one in. Undoable.
    case replace
    /// Leave the existing item alone and do not bring this one in.
    case skip
}

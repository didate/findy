import FindyCore
import Foundation

/// What a row of the sidebar stands for: a folder to go to, or a color whose files to show.
enum SidebarSelection: Hashable {
    case folder(URL)
    case label(FileLabel)
}

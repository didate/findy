import AppKit
import FindyCore

extension FileLabel {
    /// The name of the color, for menus and VoiceOver.
    var name: String {
        switch self {
        case .red: String(localized: "Red", bundle: .module)
        case .orange: String(localized: "Orange", bundle: .module)
        case .yellow: String(localized: "Yellow", bundle: .module)
        case .green: String(localized: "Green", bundle: .module)
        case .blue: String(localized: "Blue", bundle: .module)
        case .purple: String(localized: "Purple", bundle: .module)
        case .gray: String(localized: "Gray", bundle: .module)
        }
    }

    /// A system color, so the dot follows light and dark mode and the accessibility settings.
    var color: NSColor {
        switch self {
        case .red: .systemRed
        case .orange: .systemOrange
        case .yellow: .systemYellow
        case .green: .systemGreen
        case .blue: .systemBlue
        case .purple: .systemPurple
        case .gray: .systemGray
        }
    }

    /// A filled dot of the color, for a menu item.
    @MainActor var menuImage: NSImage? {
        let configuration = NSImage.SymbolConfiguration(paletteColors: [color])
        return NSImage(systemSymbolName: "circle.fill", accessibilityDescription: name)?
            .withSymbolConfiguration(configuration)
    }
}

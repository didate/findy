/// One of the seven colors Finder can mark a file or a folder with.
///
/// The raw value is the number macOS stores with the file (its Finder label), so a color set here
/// shows in Finder and a color set in Finder shows here.
public enum FileLabel: Int, CaseIterable, Hashable, Sendable {
    case gray = 1
    case green = 2
    case purple = 3
    case blue = 4
    case yellow = 5
    case red = 6
    case orange = 7

    /// The order Finder's menu shows them in.
    public static let menuOrder: [FileLabel] = [.red, .orange, .yellow, .green, .blue, .purple, .gray]
}

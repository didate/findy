import FindyCore
import Foundation

extension DateGroup {
    /// The heading of the section, as Finder words it.
    var title: String {
        switch self {
        case .today:
            String(localized: "Today", bundle: .module)
        case .yesterday:
            String(localized: "Yesterday", bundle: .module)
        case .previous7Days:
            String(localized: "Previous 7 Days", bundle: .module)
        case .previous30Days:
            String(localized: "Previous 30 Days", bundle: .module)
        case .month(_, let month):
            Self.monthName(month)
        case .year(let year):
            // Not a quantity: no thousands separator.
            String(year)
        case .unknown:
            String(localized: "No Date", bundle: .module)
        }
    }

    private static func monthName(_ month: Int) -> String {
        let names = Calendar.current.standaloneMonthSymbols
        guard names.indices.contains(month - 1) else { return String(month) }
        // Some languages write month names in lower case; a heading starts with a capital.
        let name = names[month - 1]
        return name.prefix(1).localizedUppercase + name.dropFirst()
    }
}

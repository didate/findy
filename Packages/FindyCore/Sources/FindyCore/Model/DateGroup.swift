import Foundation

/// The section an entry falls in when a list is grouped by date, the way Finder groups it:
/// recent days first, then the months of this year, then whole years.
public enum DateGroup: Hashable, Sendable, Comparable {
    case today
    case yesterday
    case previous7Days
    case previous30Days
    /// A month of the current year, older than 30 days.
    case month(year: Int, month: Int)
    /// A year before the current one.
    case year(Int)
    /// The entry has no date.
    case unknown

    /// The group of an entry modified at `date`, seen from `now`.
    public init(for date: Date?, now: Date, calendar: Calendar = .current) {
        guard let date else {
            self = .unknown
            return
        }
        let startOfToday = calendar.startOfDay(for: now)
        func daysAgo(_ days: Int) -> Date {
            calendar.date(byAdding: .day, value: -days, to: startOfToday) ?? startOfToday
        }
        // A date in the future (a clock set wrong, a file from another time zone) counts as today.
        if date >= startOfToday {
            self = .today
        } else if date >= daysAgo(1) {
            self = .yesterday
        } else if date >= daysAgo(7) {
            self = .previous7Days
        } else if date >= daysAgo(30) {
            self = .previous30Days
        } else {
            let parts = calendar.dateComponents([.year, .month], from: date)
            let year = parts.year ?? 0
            if year == calendar.component(.year, from: now) {
                self = .month(year: year, month: parts.month ?? 1)
            } else {
                self = .year(year)
            }
        }
    }

    /// Most recent first.
    public static func < (lhs: DateGroup, rhs: DateGroup) -> Bool {
        lhs.rank < rhs.rank
    }

    private var rank: (Int, Int) {
        switch self {
        case .today: (0, 0)
        case .yesterday: (1, 0)
        case .previous7Days: (2, 0)
        case .previous30Days: (3, 0)
        case .month(let year, let month): (4, -(year * 12 + month))
        case .year(let year): (5, -year)
        case .unknown: (6, 0)
        }
    }

    /// Puts `items` in sections, most recent first, keeping inside each section the order they
    /// came in. Sort first, then group.
    public static func grouped(_ items: [FileItem], now: Date, calendar: Calendar = .current) -> [FileItem] {
        var sections: [DateGroup: [FileItem]] = [:]
        for item in items {
            sections[DateGroup(for: item.modificationDate, now: now, calendar: calendar), default: []].append(item)
        }
        return sections.keys.sorted().flatMap { sections[$0] ?? [] }
    }
}

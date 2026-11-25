import Foundation
import Testing

@testable import FindyCore

@Suite struct DateGroupTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour)) ?? .distantPast
    }

    /// Wednesday 25 November 2026, 3 pm.
    private var now: Date { date(2026, 11, 25, hour: 15) }

    private func group(_ date: Date?) -> DateGroup {
        DateGroup(for: date, now: now, calendar: calendar)
    }

    @Test func putsDatesInTheSectionsFinderUses() {
        #expect(group(date(2026, 11, 25, hour: 0)) == .today)
        #expect(group(date(2026, 11, 24, hour: 23)) == .yesterday)
        #expect(group(date(2026, 11, 23)) == .previous7Days)
        #expect(group(date(2026, 11, 18, hour: 0)) == .previous7Days)
        #expect(group(date(2026, 11, 17, hour: 23)) == .previous30Days)
        #expect(group(date(2026, 10, 26, hour: 0)) == .previous30Days)
        #expect(group(date(2026, 10, 25, hour: 23)) == .month(year: 2026, month: 10))
        #expect(group(date(2026, 1, 1)) == .month(year: 2026, month: 1))
        #expect(group(date(2025, 12, 31)) == .year(2025))
        #expect(group(nil) == .unknown)
    }

    @Test func aDateInTheFutureCountsAsToday() {
        #expect(group(date(2027, 3, 1)) == .today)
    }

    @Test func sectionsGoFromTheMostRecentToTheOldest() {
        let shuffled: [DateGroup] = [
            .year(2019), .unknown, .month(year: 2026, month: 3), .previous30Days, .today, .year(2025),
            .month(year: 2026, month: 9), .yesterday, .previous7Days,
        ]

        #expect(
            shuffled.sorted() == [
                .today, .yesterday, .previous7Days, .previous30Days, .month(year: 2026, month: 9),
                .month(year: 2026, month: 3), .year(2025), .year(2019), .unknown,
            ])
    }

    @Test func groupingKeepsTheOrderInsideEachSection() {
        func item(_ name: String, _ date: Date?) -> FileItem {
            FileItem(url: URL(fileURLWithPath: "/fake/\(name)"), modificationDate: date)
        }
        let sorted = [
            item("a", date(2025, 5, 1)), item("b", date(2026, 11, 25)), item("c", nil),
            item("d", date(2026, 11, 24)), item("e", date(2026, 11, 25)), item("f", date(2025, 2, 1)),
        ]

        let grouped = DateGroup.grouped(sorted, now: now, calendar: calendar)

        #expect(grouped.map(\.name) == ["b", "e", "d", "a", "f", "c"])
    }
}

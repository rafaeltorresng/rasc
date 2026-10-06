import Foundation
import Testing
@testable import Rasc

@Suite
@MainActor
struct HomeTemporalGroupingTests {
    @Test
    func groupsNotesByCalendarDayBoundaries() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))

        let now = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 9,
            day: 20,
            hour: 10,
            minute: 0
        )))
        let startOfToday = calendar.startOfDay(for: now)
        let yesterdayLate = try #require(calendar.date(byAdding: .hour, value: -1, to: startOfToday))
        let yesterdayMorning = try #require(calendar.date(byAdding: .hour, value: -12, to: startOfToday))
        let earlier = try #require(calendar.date(byAdding: .day, value: -3, to: startOfToday))

        let todayNote = makeNote(updatedAt: now)
        let yesterdayLateNote = makeNote(updatedAt: yesterdayLate)
        let yesterdayMorningNote = makeNote(updatedAt: yesterdayMorning)
        let earlierNote = makeNote(updatedAt: earlier)

        let groups = HomeTemporalGrouping.groups(
            from: [earlierNote, yesterdayLateNote, todayNote, yesterdayMorningNote],
            calendar: calendar,
            now: now
        )

        #expect(groups.map(\.section) == [.today, .yesterday, .earlier])
        #expect(groups[0].notes == [todayNote])
        #expect(groups[1].notes == [yesterdayLateNote, yesterdayMorningNote])
        #expect(groups[2].notes == [earlierNote])
    }

    @Test
    func omitsEmptySections() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt

        let now = Date(timeIntervalSince1970: 1_000_000)
        let startOfToday = calendar.startOfDay(for: now)
        let earlier = calendar.date(byAdding: .day, value: -2, to: startOfToday) ?? now
        let note = makeNote(updatedAt: earlier)

        let groups = HomeTemporalGrouping.groups(from: [note], calendar: calendar, now: now)

        #expect(groups.map(\.section) == [.earlier])
    }

    @Test
    func formatsCompactTimestamps() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))

        let now = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 9,
            day: 20,
            hour: 15,
            minute: 31
        )))
        let startOfToday = calendar.startOfDay(for: now)
        let yesterdayLate = try #require(calendar.date(byAdding: .hour, value: -2, to: startOfToday))
        let earlier = try #require(calendar.date(byAdding: .day, value: -5, to: startOfToday))

        let timeFormatter = DateFormatter()
        timeFormatter.locale = calendar.locale ?? .current
        timeFormatter.calendar = calendar
        timeFormatter.timeZone = calendar.timeZone
        timeFormatter.setLocalizedDateFormatFromTemplate("jm")
        #expect(HomeNoteTimestampFormatter.format(now, calendar: calendar, now: now) == timeFormatter.string(from: now))
        #expect(HomeNoteTimestampFormatter.format(yesterdayLate, calendar: calendar, now: now) == "Yesterday")

        let earlierLabel = HomeNoteTimestampFormatter.format(earlier, calendar: calendar, now: now)
        let dateFormatter = DateFormatter()
        dateFormatter.locale = calendar.locale ?? .current
        dateFormatter.calendar = calendar
        dateFormatter.timeZone = calendar.timeZone
        dateFormatter.setLocalizedDateFormatFromTemplate("MMMd")
        #expect(earlierLabel == dateFormatter.string(from: earlier))
    }

    private func makeNote(updatedAt: Date) -> Note {
        Note(
            id: UUID(),
            content: "Example note",
            createdAt: updatedAt,
            updatedAt: updatedAt,
            deletedAt: nil,
            keptAt: nil
        )
    }
}

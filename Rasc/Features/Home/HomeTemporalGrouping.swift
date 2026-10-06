import Foundation

enum HomeTemporalSection: String, CaseIterable, Sendable {
    case today = "Today"
    case yesterday = "Yesterday"
    case earlier = "Earlier"
}

struct HomeTemporalGroup: Identifiable, Equatable, Sendable {
    let section: HomeTemporalSection
    let notes: [Note]

    var id: String { section.rawValue }
}

enum HomeTemporalGrouping {
    static func groups(
        from notes: [Note],
        calendar: Calendar,
        now: Date
    ) -> [HomeTemporalGroup] {
        let startOfToday = calendar.startOfDay(for: now)
        guard let startOfYesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday) else {
            return notes.isEmpty ? [] : [HomeTemporalGroup(section: .earlier, notes: notes)]
        }

        var today: [Note] = []
        var yesterday: [Note] = []
        var earlier: [Note] = []

        for note in notes {
            let updated = note.updatedAt
            if updated >= startOfToday {
                today.append(note)
            } else if updated >= startOfYesterday {
                yesterday.append(note)
            } else {
                earlier.append(note)
            }
        }

        var groups: [HomeTemporalGroup] = []
        if !today.isEmpty {
            groups.append(HomeTemporalGroup(section: .today, notes: today))
        }
        if !yesterday.isEmpty {
            groups.append(HomeTemporalGroup(section: .yesterday, notes: yesterday))
        }
        if !earlier.isEmpty {
            groups.append(HomeTemporalGroup(section: .earlier, notes: earlier))
        }
        return groups
    }
}

@MainActor
enum HomeNoteTimestampFormatter {
    private static let timeFormatter = DateFormatter()
    private static let dateFormatter = DateFormatter()
    static func format(
        _ date: Date,
        calendar: Calendar,
        now: Date
    ) -> String {
        let startOfToday = calendar.startOfDay(for: now)
        guard let startOfYesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday) else {
            return configured(dateFormatter, template: "MMMd", calendar: calendar).string(from: date)
        }

        if date >= startOfToday {
            return configured(timeFormatter, template: "jm", calendar: calendar).string(from: date)
        }
        if date >= startOfYesterday {
            return "Yesterday"
        }
        return configured(dateFormatter, template: "MMMd", calendar: calendar).string(from: date)
    }

    private static func configured(_ formatter: DateFormatter, template: String, calendar: Calendar) -> DateFormatter {
        let locale = calendar.locale ?? .autoupdatingCurrent
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        // "j" honors the user's 12/24-hour preference, including system overrides.
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter
    }
}

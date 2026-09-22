import Foundation

struct HomeBrowseGroup: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case kept
        case temporal(HomeTemporalSection)
    }

    let kind: Kind
    let notes: [Note]

    var id: String {
        switch kind {
        case .kept:
            "kept"
        case let .temporal(section):
            section.rawValue
        }
    }

    var sectionTitle: String {
        switch kind {
        case .kept:
            "Kept"
        case let .temporal(section):
            section.rawValue
        }
    }
}

enum HomeLifecycleGrouping {
    static let keptSectionLimit = 12

    static func browseGroups(
        from notes: [Note],
        calendar: Calendar,
        now: Date
    ) -> [HomeBrowseGroup] {
        let keptNotes = notes
            .filter(\.isKept)
            .sorted { lhs, rhs in
                let lhsDate = lhs.keptAt ?? lhs.updatedAt
                let rhsDate = rhs.keptAt ?? rhs.updatedAt
                if lhsDate == rhsDate {
                    return lhs.id.uuidString > rhs.id.uuidString
                }
                return lhsDate > rhsDate
            }

        let unfinishedNotes = notes.filter { !$0.isKept }
        let temporalGroups = HomeTemporalGrouping.groups(
            from: unfinishedNotes,
            calendar: calendar,
            now: now
        )

        var groups: [HomeBrowseGroup] = []
        if !keptNotes.isEmpty {
            groups.append(
                HomeBrowseGroup(
                    kind: .kept,
                    notes: Array(keptNotes.prefix(keptSectionLimit))
                )
            )
        }
        groups.append(contentsOf: temporalGroups.map {
            HomeBrowseGroup(kind: .temporal($0.section), notes: $0.notes)
        })
        return groups
    }
}

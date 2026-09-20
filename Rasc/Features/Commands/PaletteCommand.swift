import Foundation

enum PaletteCommand: String, CaseIterable, Identifiable, Equatable {
    case newScratch
    case findNote
    case openHome
    case refine
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newScratch:
            "New Scratch"
        case .findNote:
            "Find Note"
        case .openHome:
            "Open Home"
        case .refine:
            "Refine"
        case .settings:
            "Settings"
        }
    }

    var shortcutLabel: String {
        switch self {
        case .newScratch:
            "⌘N"
        case .findNote:
            "⌘P"
        case .openHome:
            ""
        case .refine:
            "⌘J"
        case .settings:
            "⌘,"
        }
    }

    var accessibilityHint: String {
        switch self {
        case .newScratch:
            "Creates a new empty scratch"
        case .findNote:
            "Opens history and search"
        case .openHome:
            "Opens Rasc Home"
        case .refine:
            "Refines the current note"
        case .settings:
            "Opens Rasc settings"
        }
    }

    static func filtered(by query: String) -> [PaletteCommand] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return allCases }

        let normalizedQuery = trimmed.folding(
            options: [.diacriticInsensitive, .caseInsensitive],
            locale: .current
        )

        return allCases.filter { command in
            let haystack = "\(command.title) \(command.shortcutLabel)".folding(
                options: [.diacriticInsensitive, .caseInsensitive],
                locale: .current
            )
            return haystack.contains(normalizedQuery)
        }
    }
}

import Foundation

enum PaletteCommand: String, CaseIterable, Identifiable, Equatable {
    case keep
    case unkeep
    case copyNote
    case shareNote
    case discardNote
    case newScratch
    case findNote
    case openHome
    case refine
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .keep:
            "Keep"
        case .unkeep:
            "Unkeep"
        case .copyNote:
            "Copy Note"
        case .shareNote:
            "Share…"
        case .discardNote:
            "Discard Note"
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
        case .keep:
            "⇧⌘K"
        case .unkeep:
            ""
        case .copyNote:
            ""
        case .shareNote:
            ""
        case .discardNote:
            ""
        case .newScratch:
            "⌘N"
        case .findNote:
            "⌘P"
        case .openHome:
            "⌘⌥\\"
        case .refine:
            "⌘J"
        case .settings:
            "⌘,"
        }
    }

    var accessibilityHint: String {
        switch self {
        case .keep:
            "Marks this thought as kept and closes the scratchpad"
        case .unkeep:
            "Marks this kept thought as unfinished again"
        case .copyNote:
            "Copies the entire note to the clipboard"
        case .shareNote:
            "Shares the note using macOS share sheet"
        case .discardNote:
            "Soft-deletes this note"
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

    static func availableCommands(
        isKept: Bool,
        hasPersistableContent: Bool,
        canPerformCompletion: Bool
    ) -> [PaletteCommand] {
        var commands: [PaletteCommand] = []

        if canPerformCompletion, hasPersistableContent || isKept {
            if isKept {
                commands.append(.unkeep)
            } else if hasPersistableContent {
                commands.append(.keep)
            }
            if hasPersistableContent {
                commands.append(.copyNote)
                commands.append(.shareNote)
            }
            commands.append(.discardNote)
        }

        commands.append(contentsOf: [.newScratch, .findNote, .openHome, .refine, .settings])
        return commands
    }

    static func filtered(
        by query: String,
        in commands: [PaletteCommand]
    ) -> [PaletteCommand] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return commands }

        let normalizedQuery = trimmed.folding(
            options: [.diacriticInsensitive, .caseInsensitive],
            locale: .current
        )

        return commands.filter { command in
            let haystack = "\(command.title) \(command.shortcutLabel)".folding(
                options: [.diacriticInsensitive, .caseInsensitive],
                locale: .current
            )
            return haystack.contains(normalizedQuery)
        }
    }
}

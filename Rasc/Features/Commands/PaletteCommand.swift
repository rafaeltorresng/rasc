import Foundation

enum PaletteCommand: String, CaseIterable, Identifiable, Equatable {
    case keep
    case unkeep
    case copyNote
    case shareNote
    case exportThought
    case exportThoughts
    case discardNote
    case newScratch
    case findNote
    case openHome
    case refine
    case voiceCapture
    case keyboardShortcuts
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
        case .exportThought:
            "Export Thought…"
        case .exportThoughts:
            "Export Thoughts…"
        case .discardNote:
            "Discard Note"
        case .newScratch:
            "New Scratch"
        case .findNote:
            "Search thoughts"
        case .openHome:
            "Open Home"
        case .refine:
            "Refine"
        case .voiceCapture:
            "Voice Capture"
        case .keyboardShortcuts:
            "Keyboard Shortcuts"
        case .settings:
            "Settings"
        }
    }

    var shortcutLabel: String {
        switch self {
        case .keep:
            RascShortcutCatalog.keep.shortcut
        case .unkeep:
            ""
        case .copyNote:
            ""
        case .shareNote, .exportThought, .exportThoughts, .voiceCapture:
            ""
        case .discardNote:
            ""
        case .newScratch:
            RascShortcutCatalog.newScratch.shortcut
        case .findNote:
            RascShortcutCatalog.searchThoughts.shortcut
        case .openHome:
            // Search alias for the documented default. Visible surfaces use the stored shortcut.
            "⌘⌥\\"
        case .refine:
            RascShortcutCatalog.refine.shortcut
        case .keyboardShortcuts:
            ""
        case .settings:
            RascShortcutCatalog.settings.shortcut
        }
    }

    @MainActor
    func displayedShortcutLabel() -> String {
        switch self {
        case .openHome:
            return GlobalShortcutFormatting.currentHomeShortcutDisplay()
        case .newScratch:
            return InternalShortcutStore.shared.displayString(for: .newScratch)
        case .findNote:
            return InternalShortcutStore.shared.displayString(for: .search)
        case .refine:
            return InternalShortcutStore.shared.displayString(for: .refine)
        case .keep:
            return InternalShortcutStore.shared.displayString(for: .keep)
        case .voiceCapture:
            return GlobalShortcutFormatting.currentVoiceShortcutDisplay()
        default:
            return shortcutLabel
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
        case .exportThought:
            "Saves a copy of this thought with its images"
        case .exportThoughts:
            "Choose which thoughts to save as files"
        case .discardNote:
            "Discards this thought. Undo restores it while Rasc is running"
        case .newScratch:
            "Creates a new empty scratch"
        case .findNote:
            "Searches your local thoughts"
        case .openHome:
            "Opens Rasc Home"
        case .refine:
            "Refines the current note"
        case .voiceCapture:
            "Record a new thought or open Voice Capture setup"
        case .keyboardShortcuts:
            "Opens keyboard shortcut settings"
        case .settings:
            "Opens Rasc settings"
        }
    }

    static func availableCommands(
        isKept: Bool,
        hasPersistableContent: Bool,
        canPerformCompletion: Bool,
        includesVoiceCapture: Bool = false
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
                commands.append(.exportThought)
            }
            commands.append(.discardNote)
        }

        commands.append(contentsOf: [
            .newScratch,
            .findNote,
            .openHome,
            .exportThoughts,
            .refine,
            .keyboardShortcuts,
            .settings
        ])
        if includesVoiceCapture, let index = commands.firstIndex(of: .newScratch) {
            commands.insert(.voiceCapture, at: index + 1)
        }
        return commands
    }

    @MainActor
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
            let alias = command == .findNote ? "Find Note" : ""
            let haystack = "\(command.title) \(command.displayedShortcutLabel()) \(command.shortcutLabel) \(alias)".folding(
                options: [.diacriticInsensitive, .caseInsensitive],
                locale: .current
            )
            return haystack.contains(normalizedQuery)
        }
    }
}

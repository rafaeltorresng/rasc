import KeyboardShortcuts
import SwiftUI

@MainActor
enum GlobalShortcutFormatting {
    static func currentToggleShortcutDisplay() -> String {
        display(for: .toggleScratchpad)
    }

    static func currentHomeShortcutDisplay() -> String {
        display(for: .toggleHome)
    }

    static func hasValidToggleShortcut() -> Bool {
        KeyboardShortcuts.getShortcut(for: .toggleScratchpad) != nil
    }

    static func hasValidHomeShortcut() -> Bool {
        KeyboardShortcuts.getShortcut(for: .toggleHome) != nil
    }

    private static func display(for name: KeyboardShortcuts.Name) -> String {
        guard let shortcut = KeyboardShortcuts.getShortcut(for: name) else {
            return "—"
        }
        return shortcut.description
    }
}

@MainActor
enum GlobalShortcutPolicy {
    static func validation(
        proposed: KeyboardShortcuts.Shortcut,
        other: KeyboardShortcuts.Name,
        otherTitle: String
    ) -> KeyboardShortcuts.ValidationResult {
        if KeyboardShortcuts.getShortcut(for: other) == proposed {
            return .disallow(reason: "Already used by \(otherTitle).")
        }
        return .allow
    }

    @discardableResult
    static func restoreDefault(
        _ name: KeyboardShortcuts.Name,
        other: KeyboardShortcuts.Name
    ) -> Bool {
        guard let initial = name.initialShortcut else {
            KeyboardShortcuts.setShortcut(nil, for: name)
            return true
        }
        if KeyboardShortcuts.getShortcut(for: other) == initial {
            return false
        }
        KeyboardShortcuts.reset(name)
        return true
    }

    static func isUsingInitialShortcut(_ name: KeyboardShortcuts.Name) -> Bool {
        KeyboardShortcuts.getShortcut(for: name) == name.initialShortcut
    }
}

struct RascShortcutEntry: Identifiable, Equatable {
    let id: String
    let title: String
    let shortcut: String
    let detail: String?
}

enum RascShortcutCatalog {
    static let newScratch = RascShortcutEntry(
        id: "new-scratch",
        title: "New Scratch",
        shortcut: "⌘N",
        detail: nil
    )
    static let refine = RascShortcutEntry(
        id: "refine",
        title: "Refine",
        shortcut: "⌘J",
        detail: nil
    )
    static let keep = RascShortcutEntry(
        id: "keep",
        title: "Keep",
        shortcut: "⇧⌘K",
        detail: nil
    )
    static let searchThoughts = RascShortcutEntry(
        id: "search-thoughts",
        title: "Search thoughts",
        shortcut: "⌘P",
        detail: nil
    )
    static let commandPalette = RascShortcutEntry(
        id: "command-palette",
        title: "Command Palette",
        shortcut: "⌘K",
        detail: nil
    )
    static let settings = RascShortcutEntry(
        id: "settings",
        title: "Settings",
        shortcut: "⌘,",
        detail: nil
    )
    static let hideScratchpad = RascShortcutEntry(
        id: "hide-scratchpad",
        title: "Hide Scratchpad",
        shortcut: "Esc",
        detail: nil
    )
    static let keepOriginal = RascShortcutEntry(
        id: "keep-original",
        title: "Keep original",
        shortcut: "Esc",
        detail: "Refinement preview"
    )
    static let acceptSuggestion = RascShortcutEntry(
        id: "accept-suggestion",
        title: "Accept suggestion",
        shortcut: "↵",
        detail: "Refinement preview"
    )
    static let quit = RascShortcutEntry(
        id: "quit",
        title: "Quit Rasc",
        shortcut: "⌘Q",
        detail: nil
    )

    static let insideRasc: [RascShortcutEntry] = [
        newScratch,
        refine,
        keep,
        searchThoughts,
        commandPalette,
        settings,
        hideScratchpad,
        keepOriginal,
        acceptSuggestion,
        quit
    ]
}

private struct GlobalShortcutChangeObserver: ViewModifier {
    let action: () -> Void

    func body(content: Content) -> some View {
        content.onReceive(NotificationCenter.default.publisher(for: GlobalShortcutChange.notification)) { _ in
            action()
        }
    }
}

private enum GlobalShortcutChange {
    /// `KeyboardShortcuts` posts this when a stored shortcut changes. The symbol is internal to the package.
    static let notification = Notification.Name("KeyboardShortcuts_shortcutByNameDidChange")
}

extension View {
    func onGlobalShortcutChange(perform action: @escaping () -> Void) -> some View {
        modifier(GlobalShortcutChangeObserver(action: action))
    }
}

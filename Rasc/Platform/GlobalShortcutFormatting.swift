import KeyboardShortcuts

@MainActor
enum GlobalShortcutFormatting {
    static func currentToggleShortcutDisplay() -> String {
        guard let shortcut = KeyboardShortcuts.getShortcut(for: .toggleScratchpad) else {
            return "—"
        }
        return shortcut.description
    }

    static func hasValidToggleShortcut() -> Bool {
        KeyboardShortcuts.getShortcut(for: .toggleScratchpad) != nil
    }
}

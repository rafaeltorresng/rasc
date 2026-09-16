import KeyboardShortcuts

enum GlobalShortcutMigration {
    static let previousDefault = KeyboardShortcuts.Shortcut(.space, modifiers: [.option])
    static let currentDefault = KeyboardShortcuts.Shortcut(.backslash, modifiers: [.option])

    @MainActor
    static func migrateFromPreviousDefaultIfNeeded() {
        guard KeyboardShortcuts.getShortcut(for: .toggleScratchpad) == previousDefault else {
            return
        }
        KeyboardShortcuts.setShortcut(currentDefault, for: .toggleScratchpad)
    }
}

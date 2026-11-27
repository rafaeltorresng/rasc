import Foundation
import KeyboardShortcuts

enum GlobalShortcutMigration {
    static let previousDefault = KeyboardShortcuts.Shortcut(.space, modifiers: [.option])
    static let currentDefault = KeyboardShortcuts.Shortcut(.backslash, modifiers: [.option])
    static let migrationCompletedKey = "globalShortcutOptionSpaceMigratedV1"

    @MainActor
    static func migrateFromPreviousDefaultIfNeeded(userDefaults: UserDefaults = .standard) {
        guard !userDefaults.bool(forKey: migrationCompletedKey) else { return }
        defer { userDefaults.set(true, forKey: migrationCompletedKey) }
        guard KeyboardShortcuts.getShortcut(for: .toggleScratchpad) == previousDefault else {
            return
        }
        KeyboardShortcuts.setShortcut(currentDefault, for: .toggleScratchpad)
    }
}

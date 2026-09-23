import KeyboardShortcuts
import Testing
@testable import Rasc

struct GlobalShortcutMigrationTests {
    @Test
    func currentDefaultUsesOptionBackslash() {
        #expect(GlobalShortcutMigration.currentDefault.key == .backslash)
        #expect(GlobalShortcutMigration.currentDefault.modifiers == [.option])
    }

    @Test
    func previousDefaultWasOptionSpace() {
        #expect(GlobalShortcutMigration.previousDefault.key == .space)
        #expect(GlobalShortcutMigration.previousDefault.modifiers == [.option])
    }

    @Test
    @MainActor
    func homeToggleDefaultUsesCommandOptionBackslash() {
        let shortcut = KeyboardShortcuts.getShortcut(for: .toggleHome)
        #expect(shortcut?.key == .backslash)
        #expect(shortcut?.modifiers == [.command, .option])
    }
}

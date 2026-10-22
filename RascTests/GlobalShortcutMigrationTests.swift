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
        let shortcut = KeyboardShortcuts.Name.toggleHome.initialShortcut
        #expect(shortcut?.key == .backslash)
        #expect(shortcut?.modifiers == [.command, .option])
    }

    @Test
    @MainActor
    func rejectsAssigningTheSameShortcutToBothGlobals() {
        withPreservedGlobalShortcuts {
            let shared = KeyboardShortcuts.Shortcut(.f6, modifiers: [.command, .option, .control])
            KeyboardShortcuts.setShortcut(shared, for: .toggleHome)
            let result = GlobalShortcutPolicy.validation(
                proposed: shared,
                other: .toggleHome,
                otherTitle: "Toggle Home"
            )
            #expect(result == .disallow(reason: "Already used by Toggle Home."))
            #expect(
                GlobalShortcutPolicy.validation(
                    proposed: KeyboardShortcuts.Shortcut(.f5, modifiers: [.command, .option, .control]),
                    other: .toggleHome,
                    otherTitle: "Toggle Home"
                ) == .allow
            )
        }
    }

    @Test
    @MainActor
    func customShortcutRoundTripsAndRestoreLeavesTheOtherShortcut() {
        withPreservedGlobalShortcuts {
            let scratchpadCustom = KeyboardShortcuts.Shortcut(.f5, modifiers: [.command, .option, .control])
            let homeCustom = KeyboardShortcuts.Shortcut(.f6, modifiers: [.command, .option, .control])
            KeyboardShortcuts.setShortcut(scratchpadCustom, for: .toggleScratchpad)
            KeyboardShortcuts.setShortcut(homeCustom, for: .toggleHome)

            #expect(KeyboardShortcuts.getShortcut(for: .toggleScratchpad) == scratchpadCustom)
            #expect(GlobalShortcutPolicy.restoreDefault(.toggleScratchpad, other: .toggleHome))
            #expect(KeyboardShortcuts.getShortcut(for: .toggleScratchpad) == KeyboardShortcuts.Name.toggleScratchpad.initialShortcut)
            #expect(KeyboardShortcuts.getShortcut(for: .toggleHome) == homeCustom)
        }
    }

    @Test
    @MainActor
    func restoreDefaultRefusesWhenTheOtherGlobalUsesThatCombination() {
        withPreservedGlobalShortcuts {
            let scratchpadDefault = KeyboardShortcuts.Name.toggleScratchpad.initialShortcut
            let scratchpadCustom = KeyboardShortcuts.Shortcut(.f5, modifiers: [.command, .option, .control])
            KeyboardShortcuts.setShortcut(scratchpadCustom, for: .toggleScratchpad)
            KeyboardShortcuts.setShortcut(scratchpadDefault, for: .toggleHome)

            #expect(!GlobalShortcutPolicy.restoreDefault(.toggleScratchpad, other: .toggleHome))
            #expect(KeyboardShortcuts.getShortcut(for: .toggleScratchpad) == scratchpadCustom)
            #expect(KeyboardShortcuts.getShortcut(for: .toggleHome) == scratchpadDefault)
        }
    }

    @Test
    @MainActor
    func clearingAGlobalShortcutDoesNotChangeTheOther() {
        withPreservedGlobalShortcuts {
            let homeCustom = KeyboardShortcuts.Shortcut(.f6, modifiers: [.command, .option, .control])
            KeyboardShortcuts.setShortcut(homeCustom, for: .toggleHome)
            KeyboardShortcuts.setShortcut(nil, for: .toggleScratchpad)

            #expect(GlobalShortcutFormatting.currentToggleShortcutDisplay() == "—")
            #expect(!GlobalShortcutFormatting.hasValidToggleShortcut())
            #expect(KeyboardShortcuts.getShortcut(for: .toggleHome) == homeCustom)
            #expect(GlobalShortcutFormatting.currentHomeShortcutDisplay() == homeCustom.description)
        }
    }

    @Test
    @MainActor
    func keyboardShortcutsRevealRequestIsConsumedOnce() {
        _ = SettingsNavigation.consumeKeyboardShortcutsRequest()
        SettingsNavigation.prepareKeyboardShortcutsReveal()
        #expect(SettingsNavigation.consumeKeyboardShortcutsRequest())
        #expect(!SettingsNavigation.consumeKeyboardShortcutsRequest())
    }
}

@MainActor
private func withPreservedGlobalShortcuts(_ body: () -> Void) {
    let scratchpad = KeyboardShortcuts.getShortcut(for: .toggleScratchpad)
    let home = KeyboardShortcuts.getShortcut(for: .toggleHome)
    defer {
        KeyboardShortcuts.setShortcut(scratchpad, for: .toggleScratchpad)
        KeyboardShortcuts.setShortcut(home, for: .toggleHome)
    }
    body()
}

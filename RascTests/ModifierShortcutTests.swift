import AppKit
import Foundation
import Testing
@testable import Rasc

@MainActor
@Suite(.serialized)
struct ModifierShortcutTests {
    private let start = ContinuousClock.Instant.now

    private func at(_ milliseconds: Int) -> ContinuousClock.Instant {
        start.advanced(by: .milliseconds(milliseconds))
    }

    private func makeRecognizer(
        _ shortcut: ModifierShortcut? = .option,
        maximumTapDuration: Duration = .milliseconds(400)
    ) -> ModifierTapRecognizer {
        ModifierTapRecognizer(shortcut: shortcut, maximumTapDuration: maximumTapDuration)
    }

    // MARK: isolated tap vs chord

    @Test func isolatedModifierTapFires() {
        var recognizer = makeRecognizer()
        _ = recognizer.handle(.modifierPressed(.option, otherModifiersDown: false), at: at(0))
        let fired = recognizer.handle(.modifierReleased(.option, otherModifiersDown: false), at: at(120))
        #expect(fired)
    }

    @Test func tapWhileAnotherModifierIsDownDoesNotFire() {
        var recognizer = makeRecognizer()
        _ = recognizer.handle(.modifierPressed(.command, otherModifiersDown: false), at: at(0))
        _ = recognizer.handle(.modifierPressed(.option, otherModifiersDown: true), at: at(10))
        _ = recognizer.handle(.modifierReleased(.option, otherModifiersDown: true), at: at(60))
        _ = recognizer.handle(.modifierReleased(.command, otherModifiersDown: false), at: at(80))
        _ = recognizer.handle(.modifierPressed(.option, otherModifiersDown: false), at: at(200))
        let fired = recognizer.handle(.modifierReleased(.option, otherModifiersDown: false), at: at(250))
        #expect(fired)
    }

    @Test func tapWhileOtherModifierIsDownDoesNotFire() {
        var recognizer = makeRecognizer()
        _ = recognizer.handle(.modifierPressed(.option, otherModifiersDown: false), at: at(0))
        _ = recognizer.handle(.modifierPressed(.command, otherModifiersDown: true), at: at(10))
        _ = recognizer.handle(.modifierReleased(.command, otherModifiersDown: true), at: at(20))
        let fired = recognizer.handle(.modifierReleased(.option, otherModifiersDown: false), at: at(30))
        #expect(!fired)
    }

    @Test func chordWithAnotherKeyDoesNotFire() {
        var recognizer = makeRecognizer()
        _ = recognizer.handle(.modifierPressed(.option, otherModifiersDown: false), at: at(0))
        _ = recognizer.handle(.otherKeyDown, at: at(20)) // e.g. Option + backslash
        let fired = recognizer.handle(.modifierReleased(.option, otherModifiersDown: false), at: at(40))
        #expect(!fired)
    }

    @Test func diacriticTypingDoesNotFire() {
        // On macOS, Option + letter produces a keyDown before releasing Option.
        var recognizer = makeRecognizer()
        _ = recognizer.handle(.modifierPressed(.option, otherModifiersDown: false), at: at(0))
        _ = recognizer.handle(.otherKeyDown, at: at(30))
        _ = recognizer.handle(.modifierReleased(.option, otherModifiersDown: false), at: at(45))
        let fired = recognizer.handle(.modifierReleased(.option, otherModifiersDown: false), at: at(50))
        #expect(!fired)
    }

    @Test func holdingPastThresholdDoesNotFire() {
        var recognizer = makeRecognizer(maximumTapDuration: .milliseconds(400))
        _ = recognizer.handle(.modifierPressed(.option, otherModifiersDown: false), at: at(0))
        let fired = recognizer.handle(.modifierReleased(.option, otherModifiersDown: false), at: at(600))
        #expect(!fired)
    }

    @Test func pointerInputDuringTapDoesNotFire() {
        var recognizer = makeRecognizer(.control)
        _ = recognizer.handle(.modifierPressed(.control, otherModifiersDown: false), at: at(0))
        _ = recognizer.handle(.otherInput, at: at(15)) // e.g. Control-click
        let fired = recognizer.handle(.modifierReleased(.control, otherModifiersDown: false), at: at(30))
        #expect(!fired)
    }

    @Test func nonConfiguredModifierTapDoesNotFire() {
        var recognizer = makeRecognizer()
        _ = recognizer.handle(.modifierPressed(.command, otherModifiersDown: false), at: at(0))
        let fired = recognizer.handle(.modifierReleased(.command, otherModifiersDown: false), at: at(50))
        #expect(!fired)
    }

    @Test func resetClearsCandidate() {
        var recognizer = makeRecognizer()
        _ = recognizer.handle(.modifierPressed(.option, otherModifiersDown: false), at: at(0))
        _ = recognizer.handle(.reset, at: at(10))
        let fired = recognizer.handle(.modifierReleased(.option, otherModifiersDown: false), at: at(20))
        #expect(!fired)
    }

    @Test func repeatedTapFiresAgain() {
        var recognizer = makeRecognizer()
        for _ in 0..<3 {
            _ = recognizer.handle(.modifierPressed(.option, otherModifiersDown: false), at: at(0))
            let fired = recognizer.handle(.modifierReleased(.option, otherModifiersDown: false), at: at(50))
            #expect(fired)
        }
    }

    @Test func disabledShortcutNeverFires() {
        var recognizer = makeRecognizer(nil)
        _ = recognizer.handle(.modifierPressed(.option, otherModifiersDown: false), at: at(0))
        let fired = recognizer.handle(.modifierReleased(.option, otherModifiersDown: false), at: at(10))
        #expect(!fired)
    }

    // MARK: store

    @Test func storePersistsAndRoundTrips() throws {
        let suite = "ModifierShortcutTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = ModifierShortcutStore(userDefaults: defaults)
        #expect(store.shortcut == nil)
        store.set(.option)
        #expect(store.shortcut == .option)
        #expect(ModifierShortcutStore(userDefaults: defaults).shortcut == .option)
        store.set(nil)
        #expect(ModifierShortcutStore(userDefaults: defaults).shortcut == nil)
    }

    @Test func matchingFindsConfiguredModifier() {
        #expect(ModifierShortcut.matching(.option) == .option)
        #expect(ModifierShortcut.matching(.command) == .command)
        #expect(ModifierShortcut.matching(.shift) == .shift)
        #expect(ModifierShortcut.matching(.control) == .control)
        #expect(ModifierShortcut.matching(NSEvent.ModifierFlags()) == nil)
        // `matching` reports a contained flag; callers require exclusivity.
        #expect(ModifierShortcut.matching([.command, .option]) != nil)
    }
}

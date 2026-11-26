import AppKit
import Foundation
import os
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
        _ = recognizer.handle(.modifierPressed(.option, otherModifiersDown: false), at: at(100))
        let recovered = recognizer.handle(.modifierReleased(.option, otherModifiersDown: false), at: at(150))
        #expect(recovered)
    }

    @Test func repeatedPressAfterInterferenceDoesNotReArmCleanTap() {
        var recognizer = makeRecognizer()
        _ = recognizer.handle(.modifierPressed(.option, otherModifiersDown: false), at: at(0))
        _ = recognizer.handle(.otherKeyDown, at: at(15))
        _ = recognizer.handle(.modifierPressed(.option, otherModifiersDown: false), at: at(25))
        let fired = recognizer.handle(.modifierReleased(.option, otherModifiersDown: false), at: at(45))
        #expect(!fired)

        // Following isolated tap recovers cleanly.
        _ = recognizer.handle(.modifierPressed(.option, otherModifiersDown: false), at: at(100))
        let recovered = recognizer.handle(.modifierReleased(.option, otherModifiersDown: false), at: at(140))
        #expect(recovered)
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

    @Test func exclusiveIgnoresNonChordSystemFlagsAndRejectsMultipleModifiers() {
        #expect(ModifierShortcut.exclusive(in: [.option, .capsLock, .function, .numericPad]) == .option)
        #expect(ModifierShortcut.exclusive(in: [.command, .capsLock]) == .command)
        #expect(ModifierShortcut.exclusive(in: [.command, .option]) == nil)
        #expect(ModifierShortcut.exclusive(in: [.capsLock, .function]) == nil)
        #expect(ModifierShortcut.exclusive(in: []) == nil)
    }

    @Test func voiceShortcutDisplayFormatsModifierAndChordCombinations() {
        #expect(GlobalShortcutFormatting.voiceShortcutDisplay(
            modifier: .option, modifierActive: true, chord: nil, chordActive: false
        ) == "⌥")
        #expect(GlobalShortcutFormatting.voiceShortcutDisplay(
            modifier: nil, modifierActive: false, chord: "⌃⌥\\", chordActive: true
        ) == "⌃⌥\\")
        #expect(GlobalShortcutFormatting.voiceShortcutDisplay(
            modifier: .option, modifierActive: true, chord: "⌃⌥\\", chordActive: true
        ) == "⌥ or ⌃⌥\\")
        #expect(GlobalShortcutFormatting.voiceShortcutDisplay(
            modifier: .option, modifierActive: false, chord: "⌃⌥\\", chordActive: true
        ) == "⌃⌥\\")
        #expect(GlobalShortcutFormatting.voiceShortcutDisplay(
            modifier: .option, modifierActive: false, chord: "⌃⌥\\", chordActive: false
        ) == "")
    }

    @Test func voiceCapturePublishesModifierShortcutChangesAndAccessibilityState() async throws {
        let suite = "ModifierShortcutTests.VoiceCapture.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: VoiceCapture.preferenceKey)

        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let repository = try NoteRepository(databaseURL: dir.appending(path: "rasc.sqlite"))
        defer { try? repository.closeForTesting() }

        let store = ModifierShortcutStore(userDefaults: defaults)
        let trustState = OSAllocatedUnfairLock(initialState: false)
        let capture = VoiceCapture(
            preferences: defaults,
            supported: true,
            input: .init(
                authorization: { .authorized },
                requestAccess: { true },
                start: { _, _ in MicBuffer(rate: 16_000) },
                stop: { _ in }
            ),
            presentWindows: false,
            speech: .init(assetsAvailable: { true }, prepare: {}, transcribe: { _, ready in
                await ready()
                return "ok"
            }, release: {}),
            modifierStore: store,
            accessibilityTrusted: { trustState.withLock { $0 } }
        )
        capture.connect(repository: repository)

        let changeNotifications = OSAllocatedUnfairLock(initialState: 0)
        let token = NotificationCenter.default.addObserver(
            forName: ModifierShortcutStore.didChange,
            object: store,
            queue: nil
        ) { _ in
            changeNotifications.withLock { $0 += 1 }
        }
        defer { NotificationCenter.default.removeObserver(token) }

        #expect(capture.modifierShortcut == nil)
        capture.setModifierShortcut(.option)
        #expect(capture.modifierShortcut == .option)
        #expect(store.shortcut == .option)
        #expect(!capture.modifierShortcutHasAccess)
        #expect(changeNotifications.withLock { $0 } == 1)

        trustState.withLock { $0 = true }
        capture.refreshModifierShortcut()
        #expect(capture.modifierShortcutHasAccess)

        capture.cancel()
        capture.setEnabled(false)
        #expect(!capture.enabled)
        #expect(capture.modifierShortcut == .option)
    }
}

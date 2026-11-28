import AppKit
import Carbon.HIToolbox
import Foundation
import KeyboardShortcuts
import Testing
@testable import Rasc

@MainActor
@Suite(.serialized)
struct UnifiedShortcutTests {
    @Test
    func defaultTriggersAndDisplaysMatchCatalog() throws {
        let (store, cleanup) = try makeIsolatedStore()
        defer { cleanup() }

        #expect(store.trigger(for: .toggleScratchpad) == .chord(KeyboardShortcuts.Shortcut(.backslash, modifiers: [.option])))
        #expect(store.trigger(for: .toggleHome) == .chord(KeyboardShortcuts.Shortcut(.backslash, modifiers: [.command, .option])))
        #expect(store.trigger(for: .voiceScratchpad) == nil)
        #expect(store.trigger(for: .voiceDictate) == nil)

        #expect(store.displayString(for: .toggleScratchpad) == "⌥\\")
        #expect(store.displayString(for: .voiceScratchpad) == "—")
    }

    @Test
    func supportsSettingBothChordsAndSingleModifiersAndDetectsConflicts() throws {
        let (store, cleanup) = try makeIsolatedStore()
        defer { cleanup() }

        #expect(store.set(.modifier(.option), for: .voiceScratchpad) == nil)
        #expect(store.trigger(for: .voiceScratchpad) == .modifier(.option))
        #expect(store.displayString(for: .voiceScratchpad) == "⌥")

        // Reject duplicate modifier across actions
        let duplicateModifier = store.set(.modifier(.option), for: .voiceDictate)
        #expect(duplicateModifier == "Already used by Voice to Scratchpad.")
        #expect(store.trigger(for: .voiceDictate) == nil)

        // Different modifier succeeds
        #expect(store.set(.modifier(.control), for: .voiceDictate) == nil)
        #expect(store.trigger(for: .voiceDictate) == .modifier(.control))

        // Reject duplicate chord across actions
        let f6 = KeyboardShortcuts.Shortcut(.f6, modifiers: [.command, .option])
        #expect(store.set(.chord(f6), for: .voiceScratchpad) == nil)
        #expect(store.set(.chord(f6), for: .toggleHome) == "Already used by Voice to Scratchpad.")
    }

    @Test
    func rejectsSystemReservedAndInternalShortcuts() throws {
        let suite = "UnifiedShortcutTests.Internal.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let internalStore = InternalShortcutStore(userDefaults: defaults)
        let store = GlobalShortcutStore(
            userDefaults: defaults,
            chordBacking: .userDefaultsOnly,
            internalStore: internalStore
        )
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(store.set(.chord(KeyboardShortcuts.Shortcut(.q, modifiers: [.command])), for: .voiceScratchpad) != nil)
        #expect(store.set(.chord(KeyboardShortcuts.Shortcut(.w, modifiers: [.command])), for: .voiceScratchpad) != nil)
        #expect(store.set(.chord(KeyboardShortcuts.Shortcut(.space, modifiers: [.command])), for: .voiceScratchpad) != nil)
        #expect(store.set(.chord(KeyboardShortcuts.Shortcut(.escape, modifiers: [])), for: .voiceScratchpad) != nil)
        #expect(store.set(.chord(KeyboardShortcuts.Shortcut(.a, modifiers: [])), for: .voiceScratchpad) != nil)

        // Internal default Command-N ("New Scratch") must conflict cleanly
        let cmdN = KeyboardShortcuts.Shortcut(.n, modifiers: [.command])
        #expect(store.set(.chord(cmdN), for: .voiceDictate) == "Already used inside Rasc by New Scratch.")

        // Standalone Function key without modifier is allowed cleanly
        let f5 = KeyboardShortcuts.Shortcut(.f5, modifiers: [])
        #expect(store.set(.chord(f5), for: .voiceDictate) == nil)
        #expect(store.trigger(for: .voiceDictate) == .chord(f5))
    }

    @Test
    func activeModifierBindingsRespectEnablementFilter() throws {
        let (store, cleanup) = try makeIsolatedStore()
        defer { cleanup() }

        #expect(store.set(.modifier(.option), for: .toggleScratchpad) == nil)
        #expect(store.set(.modifier(.control), for: .voiceDictate) == nil)
        #expect(store.set(.chord(KeyboardShortcuts.Shortcut(.f7, modifiers: [.option])), for: .voiceScratchpad) == nil)

        let whenVoiceOff = store.activeModifierBindings { action in
            !action.isVoiceAction
        }
        #expect(whenVoiceOff == [.toggleScratchpad: .option])

        let whenVoiceOn = store.activeModifierBindings { _ in true }
        #expect(whenVoiceOn == [.toggleScratchpad: .option, .voiceDictate: .control])
    }

    @Test
    func migratesLegacyScratchpadModifierOnce() throws {
        let suite = "UnifiedShortcutTests.MigrationScratch.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set(ModifierShortcut.option.rawValue, forKey: ModifierShortcutStore.preferenceKey)
        defaults.set("scratchpad", forKey: VoiceCapture.outputPreferenceKey)

        let store = GlobalShortcutStore(userDefaults: defaults, chordBacking: .userDefaultsOnly)
        store.migrateLegacyPreferencesIfNeeded()

        #expect(store.trigger(for: .voiceScratchpad) == .modifier(.option))
        #expect(store.trigger(for: .voiceDictate) == nil)
        #expect(defaults.string(forKey: VoiceCapture.dictationDeliveryPreferenceKey) == VoiceDictationDelivery.insertAtCursor.rawValue)
        #expect(defaults.string(forKey: ModifierShortcutStore.preferenceKey) == nil)
        #expect(defaults.bool(forKey: GlobalShortcutStore.migrationCompletedKey))
    }

    @Test
    func migratesLegacyClipboardModeAndHistoryToDictateAction() throws {
        let suite = "UnifiedShortcutTests.MigrationDictate.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set(ModifierShortcut.control.rawValue, forKey: ModifierShortcutStore.preferenceKey)
        defaults.set("clipboard", forKey: VoiceCapture.outputPreferenceKey)
        defaults.set(true, forKey: VoiceCapture.standaloneHistoryPreferenceKey)

        let store = GlobalShortcutStore(userDefaults: defaults, chordBacking: .userDefaultsOnly)
        store.migrateLegacyPreferencesIfNeeded()

        #expect(store.trigger(for: .voiceDictate) == .modifier(.control))
        #expect(store.trigger(for: .voiceScratchpad) == nil)
        #expect(defaults.string(forKey: VoiceCapture.dictationDeliveryPreferenceKey) == VoiceDictationDelivery.clipboard.rawValue)
        #expect(defaults.bool(forKey: VoiceCapture.dictationSaveCopyPreferenceKey))
    }

    @Test
    func seedsFirstRunVoiceShortcutsFromCommandBackslashAndOptionTap() throws {
        let suite = "UnifiedShortcutTests.Seed.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = GlobalShortcutStore(userDefaults: defaults, chordBacking: .userDefaultsOnly)

        store.seedVoiceDefaultsIfNeeded()

        #expect(store.trigger(for: .voiceScratchpad) == .chord(
            KeyboardShortcuts.Shortcut(.backslash, modifiers: [.command])
        ))
        #expect(store.trigger(for: .voiceDictate) == .modifier(.option))
        #expect(store.isUsingDefault(for: .voiceScratchpad))
        #expect(defaults.bool(forKey: GlobalShortcutStore.voiceDefaultsSeededKey))

        // Seeding is a one-time migration.
        store.set(nil, for: .voiceDictate)
        store.seedVoiceDefaultsIfNeeded()
        #expect(store.trigger(for: .voiceDictate) == nil)
    }

    @Test
    func seedingPreservesExistingInstallAndExplicitRemoval() throws {
        let completedSuite = "UnifiedShortcutTests.SeedCompleted.\(UUID())"
        let completedDefaults = try #require(UserDefaults(suiteName: completedSuite))
        defer { completedDefaults.removePersistentDomain(forName: completedSuite) }
        OnboardingStore(userDefaults: completedDefaults).isCompleted = true
        let completedStore = GlobalShortcutStore(userDefaults: completedDefaults, chordBacking: .userDefaultsOnly)
        completedStore.seedVoiceDefaultsIfNeeded()
        #expect(completedStore.trigger(for: .voiceScratchpad) == nil)
        #expect(completedStore.trigger(for: .voiceDictate) == nil)

        let clearedSuite = "UnifiedShortcutTests.SeedCleared.\(UUID())"
        let clearedDefaults = try #require(UserDefaults(suiteName: clearedSuite))
        defer { clearedDefaults.removePersistentDomain(forName: clearedSuite) }
        let clearedStore = GlobalShortcutStore(userDefaults: clearedDefaults, chordBacking: .userDefaultsOnly)
        #expect(clearedStore.set(nil, for: .voiceDictate) == nil)
        clearedStore.seedVoiceDefaultsIfNeeded()
        #expect(clearedStore.trigger(for: .voiceDictate) == nil)
        #expect(clearedStore.trigger(for: .voiceScratchpad) == .chord(
            KeyboardShortcuts.Shortcut(.backslash, modifiers: [.command])
        ))
    }

    @Test
    func unifiedRecorderCapturesSingleModifierTapOrChordWithoutCrosstalk() throws {
        let (store, cleanup) = try makeIsolatedStore()
        defer { cleanup() }

        let recorder = UnifiedShortcutRecorderModel(action: .voiceScratchpad, store: store)

        // 1. Single modifier tap: press Option -> release cleanly
        recorder.begin()
        defer { recorder.cancel() }
        recorder.handleModifierFlags([.option])
        #expect(recorder.pendingModifier == .option)
        recorder.handleModifierFlags([])
        #expect(!recorder.isRecording)
        #expect(store.trigger(for: .voiceScratchpad) == .modifier(.option))

        // 2. Chord overrides pending modifier: press Option -> press F5 keyDown -> release Option
        recorder.begin()
        recorder.handleModifierFlags([.option])
        let f5Option = KeyboardShortcuts.Shortcut(.f5, modifiers: [.option])
        #expect(recorder.handleKeyInput(
            keyCode: kVK_F5,
            modifiers: [.option],
            chordCandidate: f5Option
        ))
        #expect(!recorder.isRecording)
        #expect(store.trigger(for: .voiceScratchpad) == .chord(f5Option))

        // 3. Multiple simultaneous modifiers never assign a lone modifier
        recorder.begin()
        recorder.handleModifierFlags([.command, .option])
        #expect(recorder.pendingModifier == nil)
        recorder.handleModifierFlags([])
        #expect(recorder.isRecording)
        #expect(store.trigger(for: .voiceScratchpad) == .chord(f5Option))

        // 4. Bare Escape cancels without clearing
        #expect(recorder.handleKeyInput(keyCode: kVK_Escape, modifiers: [], chordCandidate: nil))
        #expect(!recorder.isRecording)
        #expect(store.trigger(for: .voiceScratchpad) == .chord(f5Option))

        // 5. Bare Delete clears shortcut
        recorder.begin()
        #expect(recorder.handleKeyInput(keyCode: kVK_Delete, modifiers: [], chordCandidate: nil))
        #expect(!recorder.isRecording)
        #expect(store.trigger(for: .voiceScratchpad) == nil)
    }

    private func makeIsolatedStore() throws -> (GlobalShortcutStore, () -> Void) {
        let suite = "UnifiedShortcutTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let store = GlobalShortcutStore(userDefaults: defaults, chordBacking: .userDefaultsOnly)
        return (store, { defaults.removePersistentDomain(forName: suite) })
    }
}

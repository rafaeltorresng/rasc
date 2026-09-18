import Foundation
import Testing
@testable import Rasc

@Suite(.serialized)
struct OnboardingEligibilityTests {
    @Test
    func freshUserRequiresOnboarding() {
        let defaults = makeDefaults()
        let context = OnboardingEligibility.Context(
            store: OnboardingStore(userDefaults: defaults),
            activeNoteStore: ActiveNoteStore(userDefaults: defaults),
            hasSavedNotes: false,
            hasSavedWindowFrame: false,
            forceReset: false
        )

        #expect(OnboardingEligibility.shouldPresentOnboarding(context))
    }

    @Test
    func establishedUserWithNotesSkipsOnboarding() {
        let defaults = makeDefaults()
        let store = OnboardingStore(userDefaults: defaults)
        let context = OnboardingEligibility.Context(
            store: store,
            activeNoteStore: ActiveNoteStore(userDefaults: defaults),
            hasSavedNotes: true,
            hasSavedWindowFrame: false,
            forceReset: false
        )

        #expect(!OnboardingEligibility.shouldPresentOnboarding(context))
        #expect(store.isCompleted)
    }

    @Test
    func establishedActiveNoteStateSkipsOnboarding() {
        let defaults = makeDefaults()
        let store = OnboardingStore(userDefaults: defaults)
        defaults.set(UUID().uuidString, forKey: ActiveNoteStore.key)
        let context = OnboardingEligibility.Context(
            store: store,
            activeNoteStore: ActiveNoteStore(userDefaults: defaults),
            hasSavedNotes: false,
            hasSavedWindowFrame: false,
            forceReset: false
        )

        #expect(!OnboardingEligibility.shouldPresentOnboarding(context))
        #expect(store.isCompleted)
    }

    @Test
    func savedWindowFrameSkipsOnboarding() {
        let defaults = makeDefaults()
        let store = OnboardingStore(userDefaults: defaults)
        let context = OnboardingEligibility.Context(
            store: store,
            activeNoteStore: ActiveNoteStore(userDefaults: defaults),
            hasSavedNotes: false,
            hasSavedWindowFrame: true,
            forceReset: false
        )

        #expect(!OnboardingEligibility.shouldPresentOnboarding(context))
        #expect(store.isCompleted)
    }

    @Test
    func forceResetDoesNotClearNotesOrShortcutKeys() {
        let defaults = makeDefaults()
        defaults.set(UUID().uuidString, forKey: ActiveNoteStore.key)
        defaults.set("{{100, 100}, {520, 340}}", forKey: "scratchpadWindowFrame")
        let store = OnboardingStore(userDefaults: defaults)
        store.markCompleted()

        let context = OnboardingEligibility.Context(
            store: store,
            activeNoteStore: ActiveNoteStore(userDefaults: defaults),
            hasSavedNotes: true,
            hasSavedWindowFrame: true,
            forceReset: true
        )

        #expect(OnboardingEligibility.shouldPresentOnboarding(context))
        #expect(!store.isCompleted)
        #expect(defaults.string(forKey: ActiveNoteStore.key) != nil)
        #expect(defaults.string(forKey: "scratchpadWindowFrame") != nil)
    }

    private func makeDefaults() -> UserDefaults {
        let suite = "RascTests.OnboardingEligibility.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}

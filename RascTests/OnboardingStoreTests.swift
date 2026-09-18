import Foundation
import Testing
@testable import Rasc

@Suite(.serialized)
struct OnboardingStoreTests {
    @Test
    func freshStoreRequiresOnboarding() {
        let defaults = makeDefaults()
        let store = OnboardingStore(userDefaults: defaults)

        #expect(!store.isCompleted)
        #expect(store.step == .welcome)
    }

    @Test
    func skipMarksCompletedAndClearsTransientState() {
        let defaults = makeDefaults()
        let store = OnboardingStore(userDefaults: defaults)
        store.meaningfulTextEntered = true
        store.refineAttempted = true

        store.markCompleted()

        #expect(store.isCompleted)
        #expect(store.step == .finished)
        #expect(!store.meaningfulTextEntered)
        #expect(!store.refineAttempted)
    }

    @Test
    func resetOnboardingStateOnlyPreservesCompletionKeysIndependently() {
        let defaults = makeDefaults()
        let store = OnboardingStore(userDefaults: defaults)
        store.markCompleted()

        store.resetOnboardingStateOnly()

        #expect(!store.isCompleted)
        #expect(store.step == .welcome)
    }

    @Test
    func persistsResumeStep() {
        let defaults = makeDefaults()
        let store = OnboardingStore(userDefaults: defaults)

        store.persistProgress(step: .shortcut)
        #expect(store.step == .shortcut)

        store.persistProgress(step: .capturePractice, captureSubstep: .waitingForShortcut)
        #expect(store.step == .capturePractice)
        #expect(store.captureSubstep == .waitingForShortcut)
    }

    private func makeDefaults() -> UserDefaults {
        let suite = "RascTests.Onboarding.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}

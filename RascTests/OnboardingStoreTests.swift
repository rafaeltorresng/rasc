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
    func historyHintPolicyRequiresNotesVisitsAndNoDismissal() {
        #expect(
            !FeatureDiscoveryPolicy.shouldShowHistoryHint(
                noteCount: 2, homeVisitCount: 2, dismissed: false
            )
        )
        #expect(
            !FeatureDiscoveryPolicy.shouldShowHistoryHint(
                noteCount: 3, homeVisitCount: 1, dismissed: false
            )
        )
        #expect(
            FeatureDiscoveryPolicy.shouldShowHistoryHint(
                noteCount: 3, homeVisitCount: 2, dismissed: false
            )
        )
        #expect(
            !FeatureDiscoveryPolicy.shouldShowHistoryHint(
                noteCount: 10, homeVisitCount: 5, dismissed: true
            )
        )
    }

    @Test
    func discoveryStatePersistsAndResetsWithOnboardingState() {
        let defaults = makeDefaults()
        let store = OnboardingStore(userDefaults: defaults)
        store.recordHomeVisit()
        store.recordHomeVisit()
        store.dismissHistoryHint()

        let reopened = OnboardingStore(userDefaults: defaults)
        #expect(reopened.homeVisitCount == 2)
        #expect(reopened.historyHintDismissed)

        reopened.resetOnboardingStateOnly()
        #expect(reopened.homeVisitCount == 0)
        #expect(!reopened.historyHintDismissed)
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

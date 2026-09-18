import Foundation

enum OnboardingEligibility {
    struct Context {
        let store: OnboardingStore
        let activeNoteStore: ActiveNoteStore
        let hasSavedNotes: Bool
        let hasSavedWindowFrame: Bool
        let forceReset: Bool
    }

    /// Returns whether first-run onboarding should be presented.
    static func shouldPresentOnboarding(_ context: Context) -> Bool {
        if context.forceReset {
            context.store.resetOnboardingStateOnly()
            return true
        }

        if context.store.isCompleted {
            return false
        }

        if !context.store.migrationApplied {
            if context.hasSavedNotes
                || context.activeNoteStore.hasEstablishedState
                || context.hasSavedWindowFrame
            {
                context.store.markCompletedForExistingUser()
                return false
            }
            context.store.markMigrationApplied()
        }

        return true
    }
}

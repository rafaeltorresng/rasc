import Foundation

struct OnboardingStore {
    static let completedKey = "onboardingCompleted"
    static let stepKey = "onboardingStep"
    static let captureSubstepKey = "onboardingCaptureSubstep"
    static let migrationAppliedKey = "onboardingMigrationApplied"
    static let meaningfulTextEnteredKey = "onboardingMeaningfulTextEntered"
    static let refineAttemptedKey = "onboardingRefineAttempted"
    static let refineSkippedKey = "onboardingRefineSkipped"
    static let historyHintDismissedKey = "onboardingHistoryHintDismissed"
    static let homeVisitCountKey = "onboardingHomeVisitCount"

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    var isCompleted: Bool {
        get { userDefaults.bool(forKey: Self.completedKey) }
        nonmutating set { userDefaults.set(newValue, forKey: Self.completedKey) }
    }

    var migrationApplied: Bool {
        get { userDefaults.bool(forKey: Self.migrationAppliedKey) }
        nonmutating set { userDefaults.set(newValue, forKey: Self.migrationAppliedKey) }
    }

    var step: OnboardingStep {
        get {
            let raw = userDefaults.integer(forKey: Self.stepKey)
            return OnboardingStep(rawValue: raw) ?? .welcome
        }
        nonmutating set {
            userDefaults.set(newValue.rawValue, forKey: Self.stepKey)
        }
    }

    var captureSubstep: OnboardingCaptureSubstep {
        get {
            guard let raw = userDefaults.string(forKey: Self.captureSubstepKey),
                  let value = OnboardingCaptureSubstep(rawValue: raw)
            else {
                return .waitingForShortcut
            }
            return value
        }
        nonmutating set {
            userDefaults.set(newValue.rawValue, forKey: Self.captureSubstepKey)
        }
    }

    var meaningfulTextEntered: Bool {
        get { userDefaults.bool(forKey: Self.meaningfulTextEnteredKey) }
        nonmutating set { userDefaults.set(newValue, forKey: Self.meaningfulTextEnteredKey) }
    }

    var refineAttempted: Bool {
        get { userDefaults.bool(forKey: Self.refineAttemptedKey) }
        nonmutating set { userDefaults.set(newValue, forKey: Self.refineAttemptedKey) }
    }

    var refineSkipped: Bool {
        get { userDefaults.bool(forKey: Self.refineSkippedKey) }
        nonmutating set { userDefaults.set(newValue, forKey: Self.refineSkippedKey) }
    }

    var historyHintDismissed: Bool {
        get { userDefaults.bool(forKey: Self.historyHintDismissedKey) }
        nonmutating set { userDefaults.set(newValue, forKey: Self.historyHintDismissedKey) }
    }

    var homeVisitCount: Int {
        get { userDefaults.integer(forKey: Self.homeVisitCountKey) }
        nonmutating set { userDefaults.set(newValue, forKey: Self.homeVisitCountKey) }
    }

    func recordHomeVisit() {
        homeVisitCount += 1
    }

    func dismissHistoryHint() {
        historyHintDismissed = true
    }

    func markCompleted() {
        isCompleted = true
        step = .finished
        clearTransientState()
    }

    func markCompletedForExistingUser() {
        migrationApplied = true
        historyHintDismissed = true
        markCompleted()
    }

    func markMigrationApplied() {
        migrationApplied = true
    }

    func resetOnboardingStateOnly() {
        isCompleted = false
        step = .welcome
        captureSubstep = .waitingForShortcut
        migrationApplied = false
        historyHintDismissed = false
        homeVisitCount = 0
        clearTransientState()
    }

    func clearTransientState() {
        meaningfulTextEntered = false
        refineAttempted = false
        refineSkipped = false
        captureSubstep = .waitingForShortcut
    }

    func persistProgress(
        step: OnboardingStep,
        captureSubstep: OnboardingCaptureSubstep? = nil
    ) {
        self.step = step
        if let captureSubstep {
            self.captureSubstep = captureSubstep
        }
    }
}

enum FeatureDiscoveryPolicy {
    static let minimumNotesForHistoryHint = 3
    static let minimumHomeVisitsForHistoryHint = 2

    static func shouldShowHistoryHint(
        noteCount: Int,
        homeVisitCount: Int,
        dismissed: Bool
    ) -> Bool {
        guard !dismissed, noteCount >= minimumNotesForHistoryHint else { return false }
        return homeVisitCount >= minimumHomeVisitsForHistoryHint
    }
}

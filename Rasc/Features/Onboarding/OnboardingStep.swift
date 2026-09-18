import Foundation

enum OnboardingStep: Int, Codable, CaseIterable, Sendable {
    case welcome
    case shortcut
    case capturePractice
    case refinePractice
    case completion
    case finished
}

enum OnboardingCaptureSubstep: String, Codable, Sendable {
    case waitingForShortcut
    case liveCapture
}

enum OnboardingRefineUnavailablePresentation: Equatable, Sendable {
    case appleIntelligenceDisabled
    case modelPreparing
    case unsupported
}

struct OnboardingScratchpadGuidance: Equatable, Sendable {
    static let inactive = OnboardingScratchpadGuidance(isActive: false)

    var isActive: Bool
    var showEmptyHint = true
    var showRefineHint = false
    var showEscapeHint = false
    var unavailablePresentation: OnboardingRefineUnavailablePresentation?

    init(isActive: Bool) {
        self.isActive = isActive
    }
}

struct OnboardingMeaningfulInput {
    static let minimumVisibleCharacters = 3

    static func isMeaningful(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).count >= minimumVisibleCharacters
    }
}

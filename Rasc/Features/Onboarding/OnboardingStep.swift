import Foundation

enum OnboardingFocus: String, Codable, CaseIterable, Sendable, Identifiable {
    case scratchpadAndVoice
    case scratchpadOnly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .scratchpadAndVoice: "Scratchpad + Voice & Dictate"
        case .scratchpadOnly: "Scratchpad only"
        }
    }

    var subtitle: String {
        switch self {
        case .scratchpadAndVoice:
            "Capture quick thoughts with a shortcut, or speak notes and dictate into any app."
        case .scratchpadOnly:
            "Keyboard-first floating scratchpad, instant retrieval, and optional on-device Refine."
        }
    }
}

enum OnboardingStep: Int, Codable, CaseIterable, Sendable {
    case welcome = 0
    case shortcut = 1
    case capturePractice = 2
    case refinePractice = 3
    case completion = 4
    case finished = 5
    case voiceSetup = 6
}

enum OnboardingCaptureSubstep: String, Codable, Sendable {
    case waitingForShortcut
    case liveCapture
    case waitingToResume
    case liveResume
}

enum OnboardingRefineUnavailablePresentation: Equatable, Sendable {
    case appleIntelligenceDisabled
    case modelPreparing
    case unsupported
}

struct OnboardingEnvironment: Equatable, Sendable {
    var isVoiceSupported: Bool
    var isVoiceModelInstalled: Bool
    var isMicrophoneAuthorized: Bool
    var isAccessibilityTrusted: Bool
    var isRefineAvailable: Bool

    static let `default` = OnboardingEnvironment(
        isVoiceSupported: VoiceCapture.isSupported,
        isVoiceModelInstalled: false,
        isMicrophoneAuthorized: false,
        isAccessibilityTrusted: false,
        isRefineAvailable: false
    )
}

struct OnboardingScratchpadGuidance: Equatable, Sendable {
    static let inactive = OnboardingScratchpadGuidance(isActive: false)

    var isActive: Bool
    var showEmptyHint = true
    var showRefineHint = false
    var showEscapeHint = false
    var showKeepHint = false
    var isResumeBeat = false
    var canShowRefineHint = true
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

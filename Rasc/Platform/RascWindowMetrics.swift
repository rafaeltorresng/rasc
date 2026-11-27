import AppKit

/// Initial, minimum and maximum content sizes for Rasc's main surfaces.
/// Sizes are intentionally different per surface: capture is compact,
/// Home is a library, and onboarding is stable enough for a guided flow.
enum RascWindowMetrics {
    static let scratchpadDefault = NSSize(width: 600, height: 350)
    static let scratchpadMinimum = NSSize(width: 480, height: 260)
    static let scratchpadMaximum = NSSize(width: 760, height: 620)

    static let homeDefault = NSSize(width: 1_000, height: 680)
    static let homeMinimum = NSSize(width: 760, height: 520)

    static let onboarding = NSSize(width: 640, height: 540)
    static let onboardingMinimum = NSSize(width: 560, height: 480)
    static let onboardingMaximum = NSSize(width: 760, height: 640)
}

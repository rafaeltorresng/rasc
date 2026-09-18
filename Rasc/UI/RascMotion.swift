import SwiftUI

enum RascMotion {
    static let microDuration: Double = 0.15
    static let surfaceDuration: Double = 0.2
    static let morphDuration: Double = 0.3
    static let heroSettleDuration: Double = 0.5

    static let micro = Animation.easeOut(duration: microDuration)
    static let surface = Animation.easeOut(duration: surfaceDuration)
    static let morph = Animation.spring(response: 0.32, dampingFraction: 0.86)
    static let heroSettle = Animation.easeOut(duration: heroSettleDuration)
    static let keycapPress = Animation.spring(response: 0.18, dampingFraction: 0.78)
    static let keycapRelease = Animation.spring(response: 0.26, dampingFraction: 0.84)

    static func micro(reduceMotion: Bool) -> Animation? {
        reduceMotion ? .easeOut(duration: 0.1) : micro
    }

    static func surface(reduceMotion: Bool) -> Animation? {
        reduceMotion ? .easeOut(duration: 0.12) : surface
    }

    static func morph(reduceMotion: Bool) -> Animation? {
        reduceMotion ? .easeOut(duration: 0.12) : morph
    }

    static func heroSettle(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : heroSettle
    }

    static func stageTransition(reduceMotion: Bool) -> AnyTransition {
        if reduceMotion {
            return .opacity
        }
        return .opacity.combined(with: .scale(scale: 0.985))
    }
}

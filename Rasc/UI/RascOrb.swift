import SwiftUI
import ThinkingOrbsKit

enum RascOrbState: Equatable {
    case note
    case searching
    case refining
    case connecting
    case composing

    static func resolve(isRefining: Bool, isSearching: Bool = false) -> Self {
        if isRefining {
            return .refining
        }
        if isSearching {
            return .searching
        }
        return .note
    }

    var thinkingOrbState: OrbState {
        switch self {
        case .note:
            .solving
        case .searching:
            .searching
        case .refining:
            .shaping
        case .connecting:
            .connecting
        case .composing:
            .composing
        }
    }

    var speed: Double {
        switch self {
        case .note:
            0.5
        case .searching:
            0.68
        case .refining:
            1
        case .connecting:
            0.58
        case .composing:
            0.48
        }
    }

    var opacity: Double {
        0.96
    }

    var isPaused: Bool {
        false
    }
}

enum RascOrbSize {
    case hero
    case inline
}

// Shared with the landing's Orb: violet-led diagonal tint, restrained orange
// at the lower trailing edge. Fixed sRGB keeps the identity across appearances.
private enum RascOrbPalette {
    static let violet = Color(.sRGB, red: 117 / 255, green: 100 / 255, blue: 216 / 255, opacity: 1)
    static let orange = Color(.sRGB, red: 199 / 255, green: 74 / 255, blue: 20 / 255, opacity: 1)
    static let gradient = Gradient(stops: [
        .init(color: violet, location: 0),
        .init(color: violet, location: 0.58),
        .init(color: orange, location: 1),
    ])
}

struct RascOrb: View {
    let state: RascOrbState
    let size: RascOrbSize
    var decorative: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ThinkingOrb(
            state: state.thinkingOrbState,
            size: thinkingOrbSize,
            theme: .auto,
            speed: state.speed,
            paused: state.isPaused,
            gradient: RascOrbPalette.gradient
        )
        .frame(width: pointSize, height: pointSize)
        .opacity(state.opacity)
        .animation(
            reduceMotion ? nil : .easeOut(duration: RascMotion.orbTransitionDuration),
            value: state
        )
        .accessibilityHidden(decorative)
    }

    private var thinkingOrbSize: OrbSize {
        switch size {
        case .hero:
            .px64
        case .inline:
            .px20
        }
    }

    private var pointSize: CGFloat {
        switch size {
        case .hero:
            64
        case .inline:
            RascSurfaceLayout.orbSize
        }
    }
}

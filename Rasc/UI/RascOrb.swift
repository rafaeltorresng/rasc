import SwiftUI
import ThinkingOrbsKit

enum RascOrbState: Equatable {
    case note
    case searching
    case refining

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
        }
    }

    var opacity: Double {
        switch self {
        case .note:
            0.88
        case .searching:
            0.88
        case .refining:
            0.9
        }
    }

    var isPaused: Bool {
        false
    }
}

enum RascOrbSize {
    case hero
    case inline
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
            paused: state.isPaused
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

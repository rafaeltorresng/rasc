import SwiftUI
import ThinkingOrbsKit

enum RascOrbState: Equatable {
    case note
    case refining

    static func resolve(isRefining: Bool) -> Self {
        isRefining ? .refining : .note
    }

    var thinkingOrbState: OrbState {
        switch self {
        case .note:
            .solving
        case .refining:
            .shaping
        }
    }

    var speed: Double {
        switch self {
        case .note:
            0.5
        case .refining:
            1
        }
    }

    var opacity: Double {
        switch self {
        case .note:
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
        .id(state)
        .transition(.opacity)
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
            RascSurfaceMetrics.inlineOrbSize
        }
    }
}

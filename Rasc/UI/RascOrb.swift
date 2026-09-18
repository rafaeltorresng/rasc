import SwiftUI
import ThinkingOrbsKit

enum RascOrbState {
    case idle
    case shaping
}

enum RascOrbSize {
    case hero
    case inline
}

struct RascOrb: View {
    let state: RascOrbState
    let size: RascOrbSize
    var decorative: Bool = false

    var body: some View {
        ThinkingOrb(
            state: thinkingOrbState,
            size: thinkingOrbSize,
            theme: .auto
        )
        .accessibilityHidden(decorative)
    }

    private var thinkingOrbState: OrbState {
        switch state {
        case .idle:
            .composing
        case .shaping:
            .shaping
        }
    }

    private var thinkingOrbSize: OrbSize {
        switch size {
        case .hero:
            .px64
        case .inline:
            .px20
        }
    }
}

struct ShapingIndicator: View {
    var label: String? = "refining…"

    var body: some View {
        HStack(spacing: 8) {
            RascOrb(state: .shaping, size: .inline, decorative: true)
            if let label {
                Text(label)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label ?? "Processing")
    }
}

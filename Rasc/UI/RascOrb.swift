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
        .frame(width: pointSize, height: pointSize)
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

    private var pointSize: CGFloat {
        switch size {
        case .hero:
            64
        case .inline:
            RascSurfaceMetrics.inlineOrbSize
        }
    }
}

struct ShapingIndicator: View {
    var label: String? = "refining…"

    var body: some View {
        HStack(spacing: 9) {
            RascOrb(state: .shaping, size: .inline, decorative: true)
            if let label {
                Text(label)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .processingIndicatorSurface()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label ?? "Processing")
    }
}

import SwiftUI

extension View {
    @ViewBuilder
    func transientSurfaceBackground() -> some View {
        modifier(TransientSurfaceBackgroundModifier(cornerRadius: 10))
    }

    @ViewBuilder
    func refinementPreviewSurface() -> some View {
        modifier(RefinementPreviewSurfaceModifier())
    }
}

private struct TransientSurfaceBackgroundModifier: ViewModifier {
    let cornerRadius: CGFloat
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            }
        } else if #available(macOS 26.0, *) {
            content.background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.clear)
                    .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
            }
        } else {
            content.background(.ultraThinMaterial)
        }
    }
}

private struct RefinementPreviewSurfaceModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            }
        } else if #available(macOS 26.0, *) {
            content.background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.clear)
                    .glassEffect(.regular, in: .rect(cornerRadius: 8))
            }
        } else {
            content.background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.72))
            }
        }
    }
}

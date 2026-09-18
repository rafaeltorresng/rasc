import AppKit
import SwiftUI

enum RascSurfaceMetrics {
    static let editorPadding: CGFloat = 20
    static let textContainerHorizontalInset: CGFloat = 5
    static let placeholderLeadingInset = editorPadding + textContainerHorizontalInset
    static let placeholderTopInset: CGFloat = 22

    static let previewCornerRadius: CGFloat = 14
    static let transientCornerRadius: CGFloat = 12
    static let feedbackCornerRadius: CGFloat = 10
    static let inlineOrbSize: CGFloat = 20
}

enum RascSurfacePalette {
    static let panelBackground = NSColor(
        name: NSColor.Name("RascPanelBackground")
    ) { appearance in
        if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            graphiteBackground
        } else {
            warmBackground
        }
    }

    static func canvas(for colorScheme: ColorScheme) -> Color {
        Color(nsColor: colorScheme == .dark ? graphiteBackground : warmBackground)
    }

    static func raisedFill(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color.white.opacity(0.055)
            : Color.white.opacity(0.58)
    }

    static func subtleFill(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color.white.opacity(0.045)
            : Color.black.opacity(0.035)
    }

    static func border(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color.white.opacity(0.10)
            : Color.black.opacity(0.09)
    }

    static func innerHighlight(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color.white.opacity(0.055)
            : Color.white.opacity(0.72)
    }

    static func accent(for colorScheme: ColorScheme) -> Color {
        Color(nsColor: accentNSColor(for: colorScheme))
    }

    static func accentNSColor(for colorScheme: ColorScheme) -> NSColor {
        colorScheme == .dark ? darkAccent : lightAccent
    }

    private static let warmBackground = NSColor(
        srgbRed: 0.965,
        green: 0.957,
        blue: 0.937,
        alpha: 1
    )

    private static let graphiteBackground = NSColor(
        srgbRed: 0.082,
        green: 0.088,
        blue: 0.102,
        alpha: 1
    )

    private static let lightAccent = NSColor(
        srgbRed: 0.27,
        green: 0.42,
        blue: 0.55,
        alpha: 1
    )

    private static let darkAccent = NSColor(
        srgbRed: 0.34,
        green: 0.47,
        blue: 0.57,
        alpha: 1
    )
}

extension View {
    func scratchpadCanvas() -> some View {
        modifier(ScratchpadCanvasModifier())
    }

    @ViewBuilder
    func transientSurfaceBackground() -> some View {
        modifier(TransientSurfaceBackgroundModifier(
            cornerRadius: RascSurfaceMetrics.transientCornerRadius
        ))
    }

    @ViewBuilder
    func refinementPreviewSurface() -> some View {
        modifier(RefinementPreviewSurfaceModifier())
    }

    func processingIndicatorSurface() -> some View {
        modifier(QuietRaisedSurfaceModifier(
            cornerRadius: RascSurfaceMetrics.feedbackCornerRadius,
            shadowOpacity: 0.08
        ))
    }

    func confirmationSurface() -> some View {
        modifier(QuietRaisedSurfaceModifier(
            cornerRadius: RascSurfaceMetrics.feedbackCornerRadius,
            shadowOpacity: 0.045
        ))
    }

    func onboardingFeatureSurface() -> some View {
        modifier(QuietRaisedSurfaceModifier(
            cornerRadius: RascSurfaceMetrics.previewCornerRadius,
            shadowOpacity: 0.07
        ))
    }
}

private struct ScratchpadCanvasModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background(RascSurfacePalette.canvas(for: colorScheme).ignoresSafeArea())
            .tint(RascSurfacePalette.accent(for: colorScheme))
    }
}

private struct QuietRaisedSurfaceModifier: ViewModifier {
    let cornerRadius: CGFloat
    let shadowOpacity: Double

    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(RascSurfacePalette.raisedFill(for: colorScheme))
                    .shadow(
                        color: .black.opacity(shadowOpacity),
                        radius: 8,
                        y: 3
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(RascSurfacePalette.border(for: colorScheme), lineWidth: 1)
            }
    }
}

private struct TransientSurfaceBackgroundModifier: ViewModifier {
    let cornerRadius: CGFloat

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(RascSurfacePalette.canvas(for: colorScheme))
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
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let cornerRadius = RascSurfaceMetrics.previewCornerRadius

        if reduceTransparency {
            content.background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(RascSurfacePalette.raisedFill(for: colorScheme))
            }
        } else if #available(macOS 26.0, *) {
            content.background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.clear)
                    .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
            }
        } else {
            content.background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.regularMaterial)
            }
        }
    }
}

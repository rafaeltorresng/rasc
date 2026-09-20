import AppKit
import SwiftUI

enum RascSurfaceMetrics {
    static let editorHorizontalPadding = RascSurfaceLayout.horizontalInset
    static let editorPadding = editorHorizontalPadding
    static let inlineOrbSize = RascSurfaceLayout.orbSize
    static let anchorLeadingInset = RascSurfaceLayout.horizontalInset
    static let anchorTopInset = RascSurfaceLayout.topInset
    static let anchorContentGap = RascSurfaceLayout.scratchpadContentGap
    static let anchorBandHeight: CGFloat = RascSurfaceLayout.topInset + RascSurfaceLayout.orbSize
    static let searchFieldHeight = RascSurfaceLayout.searchFieldHeight
    static let searchFieldCornerRadius = RascSurfaceLayout.searchFieldCornerRadius
    static let editorTopPadding = RascSurfaceLayout.scratchpadEditorTopPadding
    static let editorBottomPadding = RascSurfaceLayout.bottomInset
    static let textContainerHorizontalInset = RascSurfaceLayout.textContainerHorizontalInset
    static let placeholderLeadingInset = RascSurfaceLayout.noteTextLeadingInset
    static let placeholderTopInset = RascSurfaceLayout.scratchpadEditorTopPadding
    static let commandRowSpacing = RascSurfaceLayout.listRowSpacing
    static let commandRowVerticalPadding = RascSurfaceLayout.listRowVerticalPadding
    static let commandRowCornerRadius = RascSurfaceLayout.listRowCornerRadius
    static let commandRowTextHeight: CGFloat = 14.5
    static let commandRowHeight = RascSurfaceLayout.commandRowMinHeight
    static let searchRowSpacing = RascSurfaceLayout.listRowSpacing
    static let searchRowVerticalPadding = RascSurfaceLayout.listRowVerticalPadding
    static let searchRowCornerRadius = RascSurfaceLayout.listRowCornerRadius
    static let searchTitleFontSize: CGFloat = 14.5
    static let searchSnippetFontSize: CGFloat = 13
    static let searchTimestampFontSize: CGFloat = 11.5

    static func commandPaletteHeight(commandCount: Int) -> CGFloat {
        let clampedCount = max(commandCount, 1)
        let rowsHeight = CGFloat(clampedCount) * RascSurfaceLayout.commandRowMinHeight
            + CGFloat(clampedCount - 1) * RascSurfaceLayout.listRowSpacing
        let headerHeight = RascSurfaceLayout.topInset
            + RascSurfaceLayout.orbSize
            + RascSurfaceLayout.transientHeaderBodyGap
        return headerHeight + rowsHeight + RascSurfaceLayout.bottomInset
    }
    static let noteFontSize: CGFloat = 16
    static let noteLineSpacing: CGFloat = 4.5

    static let previewCornerRadius: CGFloat = 14
    static let transientCornerRadius: CGFloat = 12
    static let feedbackCornerRadius: CGFloat = 10
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
        Color(nsColor: colorScheme == .dark ? darkElevated : lightElevated)
    }

    static func subtleFill(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color.white.opacity(0.045)
            : Color.black.opacity(0.035)
    }

    static func border(for colorScheme: ColorScheme) -> Color {
        Color(nsColor: colorScheme == .dark ? darkBorder : lightBorder)
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
        colorScheme == .dark ? darkControlAccent : lightControlAccent
    }

    static func violet(for colorScheme: ColorScheme) -> Color {
        Color(nsColor: colorScheme == .dark ? darkViolet : lightViolet)
    }

    static func actionAccent(for colorScheme: ColorScheme) -> Color {
        Color(nsColor: colorScheme == .dark ? darkActionAccent : lightActionAccent)
    }

    static func selectionFill(for colorScheme: ColorScheme) -> Color {
        violet(for: colorScheme).opacity(colorScheme == .dark ? 0.18 : 0.13)
    }

    static func selectionStroke(for colorScheme: ColorScheme) -> Color {
        violet(for: colorScheme).opacity(colorScheme == .dark ? 0.42 : 0.34)
    }

    static func focusedFieldBorder(for colorScheme: ColorScheme) -> Color {
        violet(for: colorScheme).opacity(colorScheme == .dark ? 0.52 : 0.44)
    }

    private static let warmBackground = NSColor(
        srgbRed: 0.984,
        green: 0.980,
        blue: 0.992,
        alpha: 1
    )

    private static let graphiteBackground = NSColor(
        srgbRed: 0.090,
        green: 0.082,
        blue: 0.110,
        alpha: 1
    )

    private static let lightElevated = NSColor(
        srgbRed: 0.969,
        green: 0.957,
        blue: 0.980,
        alpha: 1
    )

    private static let darkElevated = NSColor(
        srgbRed: 0.110,
        green: 0.098,
        blue: 0.133,
        alpha: 1
    )

    private static let lightBorder = NSColor(
        srgbRed: 0.886,
        green: 0.867,
        blue: 0.906,
        alpha: 1
    )

    private static let darkBorder = NSColor(
        srgbRed: 0.204,
        green: 0.180,
        blue: 0.235,
        alpha: 1
    )

    private static let lightViolet = NSColor(
        srgbRed: 0.459,
        green: 0.392,
        blue: 0.847,
        alpha: 1
    )

    private static let darkViolet = NSColor(
        srgbRed: 0.604,
        green: 0.537,
        blue: 0.933,
        alpha: 1
    )

    private static let lightControlAccent = NSColor(
        srgbRed: 0.690,
        green: 0.247,
        blue: 0.035,
        alpha: 1
    )

    private static let darkControlAccent = NSColor(
        srgbRed: 0.690,
        green: 0.247,
        blue: 0.035,
        alpha: 1
    )

    private static let lightActionAccent = NSColor(
        srgbRed: 0.835,
        green: 0.318,
        blue: 0.106,
        alpha: 1
    )

    private static let darkActionAccent = NSColor(
        srgbRed: 0.965,
        green: 0.482,
        blue: 0.208,
        alpha: 1
    )
}

extension View {
    func scratchpadCanvas() -> some View {
        modifier(ScratchpadCanvasModifier())
    }

    func scratchpadOverlayBackground() -> some View {
        modifier(ScratchpadOverlayBackgroundModifier())
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

    func rascWindowSurface() -> some View {
        modifier(RascWindowSurfaceModifier())
    }
}

struct RascTransientSelectionBackground: View {
    let cornerRadius: CGFloat

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(RascSurfacePalette.selectionFill(for: colorScheme))
            .overlay {
                if colorSchemeContrast == .increased {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(
                            RascSurfacePalette.selectionStroke(for: colorScheme),
                            lineWidth: 1
                        )
                }
            }
    }
}

struct RascKeyboardActionHint: View {
    let shortcut: String
    let title: String

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 4) {
            Text(shortcut)
                .font(.system(size: 11, weight: .medium))
            Text(title)
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(RascSurfacePalette.violet(for: colorScheme).opacity(0.82))
    }
}

struct RascTransientInputShell<Content: View>: View {
    let isFocused: Bool
    @ViewBuilder var content: () -> Content

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        content()
            .frame(maxWidth: .infinity, minHeight: RascSurfaceMetrics.searchFieldHeight, alignment: .leading)
            .padding(.horizontal, 12)
            .background {
                RoundedRectangle(
                    cornerRadius: RascSurfaceMetrics.searchFieldCornerRadius,
                    style: .continuous
                )
                .fill(RascSurfacePalette.raisedFill(for: colorScheme))
            }
            .overlay {
                RoundedRectangle(
                    cornerRadius: RascSurfaceMetrics.searchFieldCornerRadius,
                    style: .continuous
                )
                .strokeBorder(
                    isFocused
                        ? RascSurfacePalette.focusedFieldBorder(for: colorScheme)
                        : RascSurfacePalette.border(for: colorScheme).opacity(0.72),
                    lineWidth: 1
                )
            }
    }
}

private struct RascWindowSurfaceModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content
                .containerBackground(RascSurfacePalette.canvas(for: colorScheme), for: .window)
                .tint(RascSurfacePalette.violet(for: colorScheme))
        } else {
            content
                .background {
                    RascSurfacePalette.canvas(for: colorScheme)
                        .ignoresSafeArea()
                }
                .tint(RascSurfacePalette.violet(for: colorScheme))
        }
    }
}

private struct ScratchpadOverlayBackgroundModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content.background {
            RascSurfacePalette.canvas(for: colorScheme)
                .ignoresSafeArea()
        }
    }
}

private struct ScratchpadCanvasModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.controlActiveState) private var controlActiveState

    func body(content: Content) -> some View {
        content
            .background {
                RascSurfacePalette.canvas(for: colorScheme)
                    .ignoresSafeArea()
            }
            .overlay {
                ContainerRelativeShape()
                    .strokeBorder(
                        controlActiveState == .key
                            ? RascSurfacePalette.violet(for: colorScheme).opacity(0.34)
                            : RascSurfacePalette.border(for: colorScheme).opacity(0.62),
                        lineWidth: 1
                    )
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
            .tint(RascSurfacePalette.violet(for: colorScheme))
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

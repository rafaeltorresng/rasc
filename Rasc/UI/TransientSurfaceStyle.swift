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
    static let editorTopPadding = RascSurfaceLayout.scratchpadEditorContentTopPadding
    static let editorBottomPadding = RascSurfaceLayout.bottomInset
    static let textContainerHorizontalInset = RascSurfaceLayout.textContainerHorizontalInset
    static let placeholderLeadingInset = RascSurfaceLayout.noteTextLeadingInset
    static let placeholderTopInset = RascSurfaceLayout.scratchpadEditorContentTopPadding
    static let scratchpadChromeToBodyGap = RascSurfaceLayout.scratchpadChromeToBodyGap
    static let scratchpadEmptySupportingGap = RascSurfaceLayout.scratchpadEmptySupportingGap
    static let scratchpadChromeHeight = RascSurfaceLayout.scratchpadChromeHeight
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
    /// Matches `noteFontSize` so the caret lines up with the empty-state prompt.
    static let scratchpadPlaceholderFontSize: CGFloat = noteFontSize

    static var noteFont: NSFont {
        NSFont.systemFont(ofSize: noteFontSize, weight: .regular)
    }
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
        Color(nsColor: canvasNSColor(for: colorScheme))
    }

    static func canvasNSColor(for colorScheme: ColorScheme) -> NSColor {
        colorScheme == .dark ? graphiteBackground : warmBackground
    }

    static func raisedFill(for colorScheme: ColorScheme) -> Color {
        Color(nsColor: raisedFillNSColor(for: colorScheme))
    }

    static func raisedFillNSColor(for colorScheme: ColorScheme) -> NSColor {
        colorScheme == .dark ? darkElevated : lightElevated
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

    /// Scratchpad caret; mirrors the SwiftUI editor tint before the AppKit text surface.
    static let scratchpadInsertionPoint = NSColor(
        name: NSColor.Name("RascScratchpadInsertionPoint")
    ) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? darkViolet : lightViolet
    }

    // MARK: Text roles

    static func primaryText(for colorScheme: ColorScheme) -> Color {
        .primary
    }

    /// Functional supporting copy: snippets, descriptions and action labels.
    static func secondaryText(for colorScheme: ColorScheme) -> Color {
        Color(nsColor: secondaryTextNSColor(for: colorScheme))
    }

    static func secondaryTextNSColor(for colorScheme: ColorScheme) -> NSColor {
        colorScheme == .dark
            ? NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.60)
            : NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.58)
    }

    /// Functional metadata: shortcuts, timestamps and section labels.
    static func metadataText(for colorScheme: ColorScheme) -> Color {
        Color(nsColor: metadataTextNSColor(for: colorScheme))
    }

    static func metadataTextNSColor(for colorScheme: ColorScheme) -> NSColor {
        colorScheme == .dark
            ? NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.55)
            : NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.57)
    }

    /// Non-essential hints only. Never use for shortcuts or functional labels.
    static func tertiaryText(for colorScheme: ColorScheme) -> Color {
        Color(nsColor: tertiaryTextNSColor(for: colorScheme))
    }

    static func tertiaryTextNSColor(for colorScheme: ColorScheme) -> NSColor {
        colorScheme == .dark
            ? NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.42)
            : NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.45)
    }

    /// Destructive actions. Text only, never a fill, never the default selection.
    static func destructiveText(for colorScheme: ColorScheme) -> Color {
        Color(nsColor: destructiveTextNSColor(for: colorScheme))
    }

    static func destructiveTextNSColor(for colorScheme: ColorScheme) -> NSColor {
        colorScheme == .dark
            ? NSColor(srgbRed: 1.0, green: 0.541, blue: 0.502, alpha: 1)
            : NSColor(srgbRed: 0.702, green: 0.149, blue: 0.118, alpha: 1)
    }

    // MARK: Actions

    /// Neutral primary action. Keep is the only copper action in the app.
    static func actionPrimaryFill(for colorScheme: ColorScheme) -> Color {
        Color(nsColor: actionPrimaryFillNSColor(for: colorScheme))
    }

    static func actionPrimaryFillNSColor(for colorScheme: ColorScheme) -> NSColor {
        colorScheme == .dark ? darkActionPrimaryFill : lightActionPrimaryFill
    }

    static func actionPrimaryLabel(for colorScheme: ColorScheme) -> Color {
        Color(nsColor: actionPrimaryLabelNSColor(for: colorScheme))
    }

    static func actionPrimaryLabelNSColor(for colorScheme: ColorScheme) -> NSColor {
        colorScheme == .dark ? graphiteBackground : warmBackground
    }

    /// Approved Keep pair: `#9C421F` on `#F5E5DA`, and `#F0A780` on `#382822`.
    static func keepAccent(for colorScheme: ColorScheme) -> Color {
        Color(nsColor: keepAccentNSColor(for: colorScheme))
    }

    static func keepAccentNSColor(for colorScheme: ColorScheme) -> NSColor {
        colorScheme == .dark ? darkKeepAccent : lightKeepAccent
    }

    static func keepFill(for colorScheme: ColorScheme) -> Color {
        Color(nsColor: keepFillNSColor(for: colorScheme))
    }

    static func keepFillNSColor(for colorScheme: ColorScheme) -> NSColor {
        colorScheme == .dark ? darkKeepFill : lightKeepFill
    }

    static func violet(for colorScheme: ColorScheme) -> Color {
        Color(nsColor: colorScheme == .dark ? darkViolet : lightViolet)
    }

    // MARK: Selection

    static func selectionFill(for colorScheme: ColorScheme) -> Color {
        Color(nsColor: selectionFillNSColor(for: colorScheme))
    }

    static func selectionFillNSColor(for colorScheme: ColorScheme) -> NSColor {
        colorScheme == .dark
            ? NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.12)
            : NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.10)
    }

    static func selectionStroke(for colorScheme: ColorScheme) -> Color {
        Color(nsColor: selectionStrokeNSColor(for: colorScheme))
    }

    static func selectionStrokeNSColor(for colorScheme: ColorScheme) -> NSColor {
        colorScheme == .dark
            ? NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.26)
            : NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.18)
    }

    static func focusedFieldBorder(for colorScheme: ColorScheme) -> Color {
        Color.primary.opacity(colorScheme == .dark ? 0.36 : 0.30)
    }

    static func homeCardFill(for colorScheme: ColorScheme) -> Color {
        Color(nsColor: homeCardFillNSColor(for: colorScheme))
    }

    static func homeCardFillNSColor(for colorScheme: ColorScheme) -> NSColor {
        colorScheme == .dark ? darkHomeCard : .white
    }

    static func homeCardBorder(
        for colorScheme: ColorScheme,
        isHovered: Bool,
        increasedContrast: Bool
    ) -> Color {
        let opacities = homeCardBorderOpacities(for: colorScheme, increasedContrast: increasedContrast)
        return border(for: colorScheme)
            .opacity(isHovered ? opacities.hover : opacities.base)
    }

    private static func homeCardBorderOpacities(
        for colorScheme: ColorScheme,
        increasedContrast: Bool
    ) -> (base: Double, hover: Double) {
        switch colorScheme {
        case .dark:
            increasedContrast ? (0.68, 0.82) : (0.52, 0.66)
        case .light:
            increasedContrast ? (0.78, 0.90) : (0.58, 0.72)
        @unknown default:
            (0.55, 0.70)
        }
    }

    static func homeSupportingText(for colorScheme: ColorScheme) -> Color {
        secondaryText(for: colorScheme)
    }

    static func homeSectionLabel(for colorScheme: ColorScheme) -> Color {
        metadataText(for: colorScheme)
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

    /// Home cards in dark mode: lifted graphite with a restrained violet undertone.
    private static let darkHomeCard = NSColor(
        srgbRed: 0.128,
        green: 0.114,
        blue: 0.152,
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

    private static let lightActionPrimaryFill = NSColor(
        srgbRed: 0.149,
        green: 0.141,
        blue: 0.169,
        alpha: 1
    )

    private static let darkActionPrimaryFill = NSColor(
        srgbRed: 0.929,
        green: 0.914,
        blue: 0.941,
        alpha: 1
    )

    private static let lightKeepAccent = NSColor(
        srgbRed: 0.612,
        green: 0.259,
        blue: 0.122,
        alpha: 1
    )

    private static let darkKeepAccent = NSColor(
        srgbRed: 0.941,
        green: 0.655,
        blue: 0.502,
        alpha: 1
    )

    private static let lightKeepFill = NSColor(
        srgbRed: 0.961,
        green: 0.898,
        blue: 0.855,
        alpha: 1
    )

    private static let darkKeepFill = NSColor(
        srgbRed: 0.220,
        green: 0.157,
        blue: 0.133,
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
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        RascSurfacePalette.selectionStroke(for: colorScheme),
                        lineWidth: colorSchemeContrast == .increased ? 1.5 : 1
                    )
            }
    }
}

struct RascKeyboardActionHint: View {
    let shortcut: String
    let title: String

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 5) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(RascSurfacePalette.secondaryText(for: colorScheme))
            Text(shortcut)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(RascSurfacePalette.metadataText(for: colorScheme))
        }
    }
}

@MainActor
enum RascAccessibility {
    static func announce(_ message: String) {
        guard let app = NSApp else { return }
        NSAccessibility.post(element: app, notification: .announcementRequested, userInfo: [
            .announcement: message,
            .priority: NSAccessibilityPriorityLevel.medium.rawValue
        ])
    }
}

struct RascTransientInputShell<Content: View>: View {
    let isFocused: Bool
    @Environment(\.colorSchemeContrast) private var contrast
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
                        ? (contrast == .increased ? RascSurfacePalette.primaryText(for: colorScheme) : RascSurfacePalette.focusedFieldBorder(for: colorScheme))
                        : RascSurfacePalette.border(for: colorScheme).opacity(contrast == .increased ? 1 : 0.72),
                    lineWidth: contrast == .increased ? 1.5 : 1
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

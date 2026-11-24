import AppKit
import SwiftUI

/// Theme styles are independent of the native appearance.
enum ThemePreset: String, CaseIterable, Identifiable, Sendable {
    case graphitePaper = "graphitePaper"
    case slate = "slate"
    case porcelain = "porcelain"
    case custom = "custom"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .graphitePaper:
            "Graphite Paper"
        case .slate:
            "Slate"
        case .porcelain:
            "Porcelain"
        case .custom:
            "Custom"
        }
    }

    var caption: String {
        switch self {
        case .graphitePaper:
            "The default. Warm paper and graphite."
        case .slate:
            "Cool blue-gray neutrals."
        case .porcelain:
            "True neutral with crisper contrast."
        case .custom:
            "Choose colors for Light and Dark appearances."
        }
    }
}

struct ThemeSettingsStore {
    static let presetKey = "appThemePreset"
    static let customPaletteKey = "appThemeCustomPalette"
    /// Legacy Custom stored named tone and ink choices.
    static let toneKey = "appThemeCustomTone"
    static let inkKey = "appThemeCustomInk"

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func loadPreset() -> ThemePreset {
        guard let raw = userDefaults.string(forKey: Self.presetKey),
              let preset = ThemePreset(rawValue: raw),
              preset != .custom || savedCustomPalette() != nil
        else {
            return .graphitePaper
        }
        return preset
    }

    func savePreset(_ preset: ThemePreset) {
        userDefaults.set(preset.rawValue, forKey: Self.presetKey)
    }

    func savedCustomPalette() -> CustomTheme? {
        guard let data = userDefaults.data(forKey: Self.customPaletteKey),
              let palette = try? JSONDecoder().decode(CustomTheme.self, from: data),
              palette.light.issue(for: .light) == nil,
              palette.dark.issue(for: .dark) == nil else { return nil }
        return palette
    }

    func saveCustomPalette(_ palette: CustomTheme) {
        guard let data = try? JSONEncoder().encode(palette) else { return }
        userDefaults.set(data, forKey: Self.customPaletteKey)
    }

    var isCustomized: Bool {
        loadPreset() != .graphitePaper
    }

    /// Restores the out-of-the-box look: Graphite Paper preset.
    /// The appearance mode (System / Light / Dark) is restored by the caller.
    func reset() {
        userDefaults.removeObject(forKey: Self.presetKey)
        userDefaults.removeObject(forKey: Self.toneKey)
        userDefaults.removeObject(forKey: Self.inkKey)
    }
}

/// Resolved colors for one appearance of one preset. Built on demand; every field
/// is a plain value. Copper (keepAccent/keepFill) is intentionally absent — it is
/// invariant across presets and stays owned by `RascSurfacePalette`.
struct ThemePalette {
    let canvas: NSColor
    let raisedFill: NSColor
    let homeCardFill: NSColor
    let border: NSColor
    let focus: NSColor
    let actionPrimaryFill: NSColor
    let actionPrimaryLabel: NSColor
    let secondaryText: NSColor
    let metadataText: NSColor
    let tertiaryText: NSColor
    let selectionStroke: NSColor
    let searchMark: NSColor
    let searchMarkContrast: NSColor
    var noteText: NSColor? = nil
    var subtleFill: NSColor? = nil
}

enum ThemeCatalog {
    static func resolve(
        preset: ThemePreset,
        scheme: ColorScheme,
        custom: CustomTheme = .standard
    ) -> ThemePalette {
        let dark = scheme == .dark
        switch preset {
        case .graphitePaper:
            return dark ? .graphiteDark : .graphiteLight
        case .slate:
            return dark ? .slateDark : .slateLight
        case .porcelain:
            return dark ? .porcelainDark : .porcelainLight
        case .custom:
            return custom[scheme].palette(for: scheme)
        }
    }
}

struct RascAppearanceView<Content: View>: View {
    @ObservedObject private var theme = ThemeStore.shared
    @AppStorage(NoteTextSize.preferenceKey) private var textSize: NoteTextSize = .standard
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .environment(\.rascPalette, theme.palette)
            .environment(\.noteTextSize, textSize)
    }
}

extension EnvironmentValues {
    @Entry var rascPalette = RascSurfacePalette.standard
    @Entry var noteTextSize: NoteTextSize = .standard
}

enum NoteTextSize: String, CaseIterable, Identifiable {
    static let preferenceKey = "noteTextSize"
    case small, standard, large

    var id: Self { self }

    var title: String {
        switch self {
        case .small: "Small"
        case .standard: "Default"
        case .large: "Large"
        }
    }

    func points(_ base: CGFloat) -> CGFloat {
        switch self {
        case .small: base - 1.5
        case .standard: base
        case .large: base + 3
        }
    }
}

@MainActor
final class ThemeStore: ObservableObject {
    static let shared = ThemeStore()

    @Published private(set) var palette: RascSurfacePalette
    private(set) var custom: CustomTheme
    private let store: ThemeSettingsStore

    init(store: ThemeSettingsStore = ThemeSettingsStore()) {
        self.store = store
        custom = store.savedCustomPalette() ?? .standard
        palette = RascSurfacePalette(preset: store.loadPreset(), custom: custom)
    }

    var preset: ThemePreset { palette.preset }
    var isCustomized: Bool { preset != .graphitePaper }

    func selectPreset(_ newPreset: ThemePreset) {
        guard newPreset != preset else { return }
        if newPreset == .custom { store.saveCustomPalette(custom) }
        store.savePreset(newPreset)
        palette = RascSurfacePalette(preset: newPreset, custom: custom)
    }

    func applyCustomPalette(_ newPalette: CustomTheme) {
        guard newPalette != custom,
              newPalette.light.issue(for: .light) == nil,
              newPalette.dark.issue(for: .dark) == nil else { return }
        store.saveCustomPalette(newPalette)
        custom = newPalette
        palette = RascSurfacePalette(preset: preset, custom: custom)
    }

    func reset() {
        store.reset()
        palette = .standard
    }

    func palette(for colorScheme: ColorScheme) -> ThemePalette {
        palette.colors(for: colorScheme)
    }
}

struct CustomTheme: Codable, Equatable {
    var light: CustomThemeColors
    var dark: CustomThemeColors

    static let standard = Self(
        light: CustomThemeColors(
            background: ThemePalette.graphiteLight.canvas,
            noteText: ThemePalette.graphiteLight.actionPrimaryFill
        ),
        dark: CustomThemeColors(
            background: ThemePalette.graphiteDark.canvas,
            noteText: ThemePalette.graphiteDark.actionPrimaryFill
        )
    )

    subscript(scheme: ColorScheme) -> CustomThemeColors {
        get { scheme == .dark ? dark : light }
        set {
            if scheme == .dark { dark = newValue } else { light = newValue }
        }
    }
}

struct CustomThemeColors: Codable, Equatable {
    var background: ThemeColor
    var noteText: ThemeColor

    init(background: NSColor, noteText: NSColor) {
        self.background = ThemeColor(background)!
        self.noteText = ThemeColor(noteText)!
    }

    /// The native controls and brand mark use the appearance's own ink.
    /// Reject inaccessible drafts explicitly, while previewing the exact colors.
    func issue(for scheme: ColorScheme) -> String? {
        let canvas = background.nsColor
        if !Self.chromeIsReadable(over: canvas, scheme: scheme) {
            return scheme == .dark
                ? "Dark needs a darker background."
                : "Light needs a lighter background."
        }
        if ThemeColor.contrast(canvas, noteText.nsColor) < 4.5 {
            return scheme == .dark ? "Dark needs more text contrast." : "Light needs more text contrast."
        }
        return nil
    }

    func palette(for scheme: ColorScheme) -> ThemePalette {
        let dark = scheme == .dark
        let base: ThemePalette = dark ? .graphiteDark : .graphiteLight
        let canvas = background.nsColor
        let noteInk = noteText.nsColor
        let ink = base.actionPrimaryFill

        // Keep note text and native labels readable on raised or highlighted surfaces.
        func surface(toward tint: NSColor, amount: CGFloat) -> NSColor {
            let fill = ThemeColor.mix(canvas, tint, amount: amount)
            return ThemeColor.contrast(fill, noteInk) >= 4.5 && Self.chromeIsReadable(over: fill, scheme: scheme)
                ? fill : canvas
        }

        func supportingInk(_ amount: CGFloat, minimum: Double = 4.5) -> NSColor {
            let candidate = ThemeColor.mix(ink, canvas, amount: amount)
            return [canvas, raised, card].allSatisfy {
                ThemeColor.contrast(candidate, $0) >= minimum
            } ? candidate : ink
        }

        let raised = surface(toward: ink, amount: dark ? 0.055 : 0.035)
        let card = surface(toward: dark ? ink : .white, amount: dark ? 0.085 : 0.42)
        let mark = surface(toward: ink, amount: 0.16)
        let strongerMark = surface(toward: ink, amount: 0.22)
        let hoverOpacity: CGFloat = 0.045
        let hoverPreservesContrast = [canvas, raised, card].allSatisfy {
            let hovered = ThemeColor.mix($0, ink, amount: hoverOpacity)
            return ThemeColor.contrast(hovered, noteInk) >= 4.5 && Self.chromeIsReadable(over: hovered, scheme: scheme)
        }
        return ThemePalette(
            canvas: canvas,
            raisedFill: raised,
            homeCardFill: card,
            border: supportingInk(0.72, minimum: 1.4),
            focus: supportingInk(0.34, minimum: 3),
            actionPrimaryFill: ink,
            actionPrimaryLabel: canvas,
            secondaryText: supportingInk(0.24),
            metadataText: supportingInk(0.27),
            tertiaryText: supportingInk(0.42, minimum: 3),
            selectionStroke: supportingInk(0.53, minimum: 3),
            searchMark: mark,
            searchMarkContrast: strongerMark,
            noteText: noteInk,
            subtleFill: ink.withAlphaComponent(hoverPreservesContrast ? hoverOpacity : 0)
        )
    }

    private static func chromeIsReadable(over background: NSColor, scheme: ColorScheme) -> Bool {
        let dark = scheme == .dark
        let graphiteInk = dark ? ThemePalette.graphiteDark.actionPrimaryFill : ThemePalette.graphiteLight.actionPrimaryFill
        // macOS labelColor is approximately 85% opaque. Check it composited onto
        // the canvas as well as the opaque ink used by Rasc's own controls.
        let nativeLabel = ThemeColor.mix(background, dark ? .white : .black, amount: 0.84)
        return ThemeColor.contrast(background, nativeLabel) >= 4.5
            && ThemeColor.contrast(background, graphiteInk) >= 4.5
    }
}

/// Extended sRGB preserves native color-panel choices outside standard sRGB.
struct ThemeColor: Codable, Equatable {
    private let red: CGFloat
    private let green: CGFloat
    private let blue: CGFloat

    init?(_ color: NSColor) {
        guard let rgb = color.usingColorSpace(.extendedSRGB),
              rgb.redComponent.isFinite, rgb.greenComponent.isFinite, rgb.blueComponent.isFinite else { return nil }
        red = rgb.redComponent
        green = rgb.greenComponent
        blue = rgb.blueComponent
    }

    var nsColor: NSColor {
        NSColor(colorSpace: .extendedSRGB, components: [red, green, blue, 1], count: 4)
    }

    static func mix(_ first: NSColor, _ second: NSColor, amount: CGFloat) -> NSColor {
        guard let first = ThemeColor(first), let second = ThemeColor(second) else { return first }
        return NSColor(colorSpace: .extendedSRGB, components: [
            first.red + (second.red - first.red) * amount,
            first.green + (second.green - first.green) * amount,
            first.blue + (second.blue - first.blue) * amount,
            1
        ], count: 4)
    }

    static func contrast(_ first: NSColor, _ second: NSColor) -> Double {
        func luminance(_ color: NSColor) -> Double {
            guard let rgb = ThemeColor(color) else { return 0 }
            func linear(_ component: CGFloat) -> Double {
                let magnitude = Double(abs(component))
                let linear = magnitude <= 0.04045 ? magnitude / 12.92 : pow((magnitude + 0.055) / 1.055, 2.4)
                return component < 0 ? -linear : linear
            }
            let value = linear(rgb.red) * 0.2126 + linear(rgb.green) * 0.7152 + linear(rgb.blue) * 0.0722
            return min(1, max(0, value))
        }

        let first = luminance(first)
        let second = luminance(second)
        return (max(first, second) + 0.05) / (min(first, second) + 0.05)
    }
}

private func rgb(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> NSColor {
    NSColor(srgbRed: red, green: green, blue: blue, alpha: 1)
}

private extension ThemePalette {
    static let graphiteLight = ThemePalette(
        canvas: rgb(0.9686, 0.9608, 0.9412),
        raisedFill: rgb(0.9373, 0.9294, 0.9098),
        homeCardFill: rgb(1, 1, 1),
        border: rgb(0.8314, 0.8235, 0.8000),
        focus: rgb(0.4000, 0.4000, 0.3843),
        actionPrimaryFill: rgb(0.1412, 0.1412, 0.1373),
        actionPrimaryLabel: rgb(0.9686, 0.9608, 0.9412),
        secondaryText: rgb(0, 0, 0).withAlphaComponent(0.58),
        metadataText: rgb(0, 0, 0).withAlphaComponent(0.57),
        tertiaryText: rgb(0, 0, 0).withAlphaComponent(0.45),
        selectionStroke: rgb(0, 0, 0).withAlphaComponent(0.18),
        searchMark: rgb(0.8118, 0.7882, 0.7294),
        searchMarkContrast: rgb(0.7608, 0.7294, 0.6549)
    )

    static let graphiteDark = ThemePalette(
        canvas: rgb(0.1176, 0.1176, 0.1137),
        raisedFill: rgb(0.1569, 0.1569, 0.1529),
        homeCardFill: rgb(0.1882, 0.1882, 0.1843),
        border: rgb(0.2667, 0.2667, 0.2510),
        focus: rgb(0.6471, 0.6471, 0.6275),
        actionPrimaryFill: rgb(0.9333, 0.9255, 0.9059),
        actionPrimaryLabel: rgb(0.1176, 0.1176, 0.1137),
        secondaryText: rgb(1, 1, 1).withAlphaComponent(0.60),
        metadataText: rgb(1, 1, 1).withAlphaComponent(0.55),
        tertiaryText: rgb(1, 1, 1).withAlphaComponent(0.42),
        selectionStroke: rgb(1, 1, 1).withAlphaComponent(0.26),
        searchMark: rgb(0.2902, 0.2902, 0.2588),
        searchMarkContrast: rgb(0.3098, 0.3098, 0.2784)
    )

    static let slateLight = ThemePalette(
        canvas: rgb(0.9451, 0.9569, 0.9725),
        raisedFill: rgb(0.9137, 0.9294, 0.9529),
        homeCardFill: rgb(1, 1, 1),
        border: rgb(0.7882, 0.8157, 0.8588),
        focus: rgb(0.3686, 0.4078, 0.4588),
        actionPrimaryFill: rgb(0.1059, 0.1294, 0.1686),
        actionPrimaryLabel: rgb(0.9451, 0.9569, 0.9725),
        secondaryText: rgb(0, 0, 0).withAlphaComponent(0.58),
        metadataText: rgb(0, 0, 0).withAlphaComponent(0.57),
        tertiaryText: rgb(0, 0, 0).withAlphaComponent(0.45),
        selectionStroke: rgb(0, 0, 0).withAlphaComponent(0.18),
        searchMark: rgb(0.7961, 0.8235, 0.8706),
        searchMarkContrast: rgb(0.7294, 0.7647, 0.8275)
    )

    static let slateDark = ThemePalette(
        canvas: rgb(0.0824, 0.1020, 0.1294),
        raisedFill: rgb(0.1098, 0.1373, 0.1725),
        homeCardFill: rgb(0.1333, 0.1647, 0.2078),
        border: rgb(0.1804, 0.2275, 0.2824),
        focus: rgb(0.5412, 0.5922, 0.6588),
        actionPrimaryFill: rgb(0.9020, 0.9176, 0.9412),
        actionPrimaryLabel: rgb(0.0824, 0.1020, 0.1294),
        secondaryText: rgb(1, 1, 1).withAlphaComponent(0.60),
        metadataText: rgb(1, 1, 1).withAlphaComponent(0.55),
        tertiaryText: rgb(1, 1, 1).withAlphaComponent(0.42),
        selectionStroke: rgb(1, 1, 1).withAlphaComponent(0.26),
        searchMark: rgb(0.2118, 0.2471, 0.3020),
        searchMarkContrast: rgb(0.2431, 0.2784, 0.3412)
    )

    static let porcelainLight = ThemePalette(
        canvas: rgb(0.9843, 0.9843, 0.9843),
        raisedFill: rgb(0.9373, 0.9373, 0.9373),
        homeCardFill: rgb(1, 1, 1),
        border: rgb(0.8235, 0.8235, 0.8235),
        focus: rgb(0.3098, 0.3098, 0.3098),
        actionPrimaryFill: rgb(0.0667, 0.0667, 0.0667),
        actionPrimaryLabel: rgb(0.9843, 0.9843, 0.9843),
        secondaryText: rgb(0, 0, 0).withAlphaComponent(0.66),
        metadataText: rgb(0, 0, 0).withAlphaComponent(0.64),
        tertiaryText: rgb(0, 0, 0).withAlphaComponent(0.52),
        selectionStroke: rgb(0, 0, 0).withAlphaComponent(0.28),
        searchMark: rgb(0.8392, 0.8392, 0.8392),
        searchMarkContrast: rgb(0.7843, 0.7843, 0.7843)
    )

    static let porcelainDark = ThemePalette(
        canvas: rgb(0.0627, 0.0627, 0.0706),
        raisedFill: rgb(0.1020, 0.1020, 0.1137),
        homeCardFill: rgb(0.1216, 0.1216, 0.1373),
        border: rgb(0.1647, 0.1647, 0.1804),
        focus: rgb(0.6078, 0.6078, 0.6392),
        actionPrimaryFill: rgb(0.9294, 0.9294, 0.9412),
        actionPrimaryLabel: rgb(0.0627, 0.0627, 0.0706),
        secondaryText: rgb(1, 1, 1).withAlphaComponent(0.68),
        metadataText: rgb(1, 1, 1).withAlphaComponent(0.66),
        tertiaryText: rgb(1, 1, 1).withAlphaComponent(0.50),
        selectionStroke: rgb(1, 1, 1).withAlphaComponent(0.34),
        searchMark: rgb(0.2000, 0.2000, 0.2275),
        searchMarkContrast: rgb(0.2235, 0.2235, 0.2549)
    )
}

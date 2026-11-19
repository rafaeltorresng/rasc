import AppKit
import SwiftUI

/// Curated theme presets for Rasc. Every preset keeps graphite-paper DNA:
/// warm-to-true neutral canvases, native semantics, copper reserved for Keep.
enum ThemePreset: String, CaseIterable, Identifiable, Sendable {
    case graphitePaper = "graphitePaper"
    case slate = "slate"
    case porcelain = "porcelain"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .graphitePaper:
            "Graphite Paper"
        case .slate:
            "Slate"
        case .porcelain:
            "Porcelain"
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
        }
    }
}

struct ThemeSettingsStore {
    static let presetKey = "appThemePreset"
    /// Legacy keys from the removed Custom option; ignored, overwritten or cleared by reset().
    static let toneKey = "appThemeCustomTone"
    static let inkKey = "appThemeCustomInk"

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func loadPreset() -> ThemePreset {
        guard let raw = userDefaults.string(forKey: Self.presetKey),
              let preset = ThemePreset(rawValue: raw)
        else {
            // Includes the legacy stored value "custom".
            return .graphitePaper
        }
        return preset
    }

    func savePreset(_ preset: ThemePreset) {
        userDefaults.set(preset.rawValue, forKey: Self.presetKey)
    }

    var isCustomized: Bool {
        loadPreset() != .graphitePaper
    }

    /// Restores the out-of-the-box look: Graphite Paper preset.
    /// The appearance mode (System / Light / Dark) is restored by the caller.
    func reset() {
        userDefaults.removeObject(forKey: Self.presetKey)
        // Drop the legacy Custom keys so a fresh Start is indistinguishable.
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

    static func current(for colorScheme: ColorScheme) -> ThemePalette {
        ThemeCatalog.palette(for: colorScheme)
    }
}

/// Lock-protected, synchronous view of the current theme. `NSColor` dynamic
/// providers and static palette functions resolve through here, so they work
/// from any thread without actor hops. `ThemeStore` publishes into it on change.
enum ThemeCatalog {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var preset: ThemePreset = .graphitePaper

    static func update(preset: ThemePreset) {
        lock.lock()
        defer { lock.unlock() }
        self.preset = preset
    }

    static func palette(for colorScheme: ColorScheme) -> ThemePalette {
        lock.lock()
        let preset = self.preset
        lock.unlock()
        return resolve(preset: preset, scheme: colorScheme)
    }

    static func resolve(preset: ThemePreset, scheme colorScheme: ColorScheme) -> ThemePalette {
        let dark = colorScheme == .dark
        switch preset {
        case .graphitePaper:
            return dark ? .graphiteDark : .graphiteLight
        case .slate:
            return dark ? .slateDark : .slateLight
        case .porcelain:
            return dark ? .porcelainDark : .porcelainLight
        }
    }
}

/// Rebuilds its content with fresh tokens whenever the theme version changes.
/// The themed roots are recreated rather than surgically repainted: every surface
/// always reads the current palette, at the cost of dropping transient view state.
struct ThemeRebuildView<Content: View>: View {
    @ObservedObject private var theme = ThemeStore.shared
    @ViewBuilder let content: () -> Content

    var body: some View {
        content().id(theme.version)
    }
}

@MainActor
final class ThemeStore: ObservableObject {
    static let shared = ThemeStore()

    @Published private(set) var preset: ThemePreset
    /// Bumped on every theme change. Themed roots rebuild behind this identity.
    @Published private(set) var version: UInt64 = 0

    private let store: ThemeSettingsStore

    init(store: ThemeSettingsStore = ThemeSettingsStore()) {
        self.store = store
        self.preset = store.loadPreset()
        ThemeCatalog.update(preset: self.preset)
    }

    var isCustomized: Bool {
        preset != .graphitePaper
    }

    func selectPreset(_ newPreset: ThemePreset) {
        guard newPreset != preset else { return }
        preset = newPreset
        store.savePreset(newPreset)
        ThemeCatalog.update(preset: preset)
        version &+= 1
    }

    func reset() {
        preset = .graphitePaper
        store.reset()
        ThemeCatalog.update(preset: preset)
        version &+= 1
    }

    func palette(for colorScheme: ColorScheme) -> ThemePalette {
        ThemeCatalog.resolve(preset: preset, scheme: colorScheme)
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

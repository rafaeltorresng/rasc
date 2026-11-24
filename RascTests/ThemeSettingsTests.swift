import Foundation
import AppKit
import SwiftUI
import Testing
@testable import Rasc

@MainActor
@Suite
struct ThemeSettingsTests {
    private func makeStore() -> ThemeSettingsStore {
        let suiteName = "ThemeSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return ThemeSettingsStore(userDefaults: defaults)
    }

    @Test
    func defaultsToGraphitePaperWithoutTouchingAppearance() {
        let store = makeStore()
        #expect(store.loadPreset() == .graphitePaper)
        #expect(!store.isCustomized)
    }

    @Test
    func persistsPreset() {
        let store = makeStore()
        store.savePreset(.slate)
        #expect(store.loadPreset() == .slate)
        #expect(store.isCustomized)
    }

    @Test
    func legacyCustomSelectionFallsBackToGraphitePaper() {
        let suiteName = "ThemeSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set("custom", forKey: ThemeSettingsStore.presetKey)
        defaults.set("warm", forKey: ThemeSettingsStore.toneKey)
        defaults.set("standard", forKey: ThemeSettingsStore.inkKey)
        let fresh = ThemeSettingsStore(userDefaults: defaults)
        #expect(fresh.loadPreset() == .graphitePaper)
        #expect(!fresh.isCustomized)
    }

    @Test
    func unknownStoredPresetFallsBackToGraphitePaper() {
        let suiteName = "ThemeSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set("neon", forKey: ThemeSettingsStore.presetKey)
        let fresh = ThemeSettingsStore(userDefaults: defaults)
        #expect(fresh.loadPreset() == .graphitePaper)
    }

    @Test
    func resetClearsPresetAndLegacyCustomKeys() {
        let suiteName = "ThemeSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let store = ThemeSettingsStore(userDefaults: defaults)
        store.savePreset(.porcelain)
        defaults.set("warm", forKey: ThemeSettingsStore.toneKey)
        defaults.set("contrast", forKey: ThemeSettingsStore.inkKey)
        store.reset()
        #expect(store.loadPreset() == .graphitePaper)
        #expect(!store.isCustomized)
        #expect(defaults.string(forKey: ThemeSettingsStore.toneKey) == nil)
        #expect(defaults.string(forKey: ThemeSettingsStore.inkKey) == nil)
    }

    @Test
    func appearanceModePreferenceRemainsIndependent() {
        let suiteName = "ThemeSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let appearance = AppThemeSettingsStore(userDefaults: defaults)
        // The documented default is System; the style layer must not touch it.
        #expect(appearance.load() == .system)
        appearance.save(.rascDark)
        let theme = ThemeSettingsStore(userDefaults: defaults)
        #expect(theme.loadPreset() == .graphitePaper)
        #expect(appearance.load() == .rascDark)
    }

    @Test
    func instanceStoreDrivesInstancePalettes() {
        let store = makeStore()
        let instance = ThemeStore(store: store)

        let graphite = instance.palette(for: .light)
        #expect(ThemeStore.hex(graphite.canvas) == "F7F5F0")

        instance.selectPreset(.slate)
        let slate = instance.palette(for: .light)
        #expect(ThemeStore.hex(slate.canvas) != ThemeStore.hex(graphite.canvas))

        instance.selectPreset(.porcelain)
        let porcelain = instance.palette(for: .dark)
        #expect(ThemeStore.hex(porcelain.canvas) == "101012")

        instance.reset()
        #expect(instance.preset == .graphitePaper)
        #expect(ThemeStore.hex(instance.palette(for: .light).canvas) == "F7F5F0")
    }

    @Test
    func copperTokensSurviveEveryPreset() {
        let store = makeStore()
        let instance = ThemeStore(store: store)
        for preset in ThemePreset.allCases {
            instance.selectPreset(preset)
            for scheme in [ColorScheme.light, .dark] {
                let expectedAccent = scheme == .light ? "9C421F" : "F0A780"
                let expectedFill = scheme == .light ? "F5E5DA" : "382822"
                #expect(ThemeStore.hex(instance.palette.keepAccentNSColor(for: scheme)) == expectedAccent)
                #expect(ThemeStore.hex(instance.palette.keepFillNSColor(for: scheme)) == expectedFill)
            }
        }
    }

    @Test
    func customColorsAreIndependentAndPersistAcrossPresetChanges() throws {
        let store = makeStore()
        let instance = ThemeStore(store: store)
        instance.selectPreset(.custom)
        #expect(store.loadPreset() == .custom)

        var edited = instance.custom
        edited[.dark].background = try #require(ThemeColor(.init(srgbRed: 0.06, green: 0.13, blue: 0.16, alpha: 1)))
        edited[.dark].noteText = try #require(ThemeColor(.init(srgbRed: 0.78, green: 0.96, blue: 0.88, alpha: 1)))
        instance.applyCustomPalette(edited)
        #expect(instance.palette(for: .dark).canvas == edited.dark.background.nsColor)
        #expect(instance.palette(for: .dark).noteText == edited.dark.noteText.nsColor)
        #expect(instance.palette(for: .light).canvas == CustomTheme.standard.light.background.nsColor)

        instance.selectPreset(.porcelain)
        let reloaded = ThemeStore(store: store)
        #expect(reloaded.preset == .porcelain)
        #expect(reloaded.custom == edited)
        reloaded.selectPreset(.custom)
        #expect(reloaded.palette(for: .dark).canvas == edited.dark.background.nsColor)
        reloaded.reset()
        #expect(store.loadPreset() == .graphitePaper)
        #expect(store.savedCustomPalette() == edited)
        reloaded.selectPreset(.custom)
        reloaded.applyCustomPalette(.standard)
        #expect(ThemeStore(store: store).preset == .custom)
        #expect(store.savedCustomPalette() == .standard)
    }

    @Test
    func invalidOrLegacyPalettesDoNotApply() throws {
        let store = makeStore()
        let instance = ThemeStore(store: store)
        instance.selectPreset(.custom)
        var invalid = instance.custom
        invalid[.light].noteText = invalid.light.background
        #expect(invalid.light.issue(for: .light) != nil)
        instance.applyCustomPalette(invalid)
        #expect(store.savedCustomPalette() == .standard)

        invalid[.light].background = try #require(ThemeColor(.black))
        #expect(invalid.light.issue(for: .light) != nil)
        store.saveCustomPalette(invalid)
        #expect(store.loadPreset() == .graphitePaper)
    }

    @Test
    func wideGamutColorRoundTripsThroughPreferences() throws {
        let p3 = NSColor(displayP3Red: 0, green: 0.2, blue: 0, alpha: 1)
        let picked = try #require(ThemeColor(p3))
        #expect(picked.nsColor.redComponent < 0)
        let store = makeStore()
        var custom = CustomTheme.standard
        custom[.light].noteText = picked
        store.saveCustomPalette(custom)
        #expect(store.savedCustomPalette()?.light.noteText == picked)
    }

    @Test(arguments: [ColorScheme.light, .dark])
    func customSurfacesKeepChosenTextReadable(scheme: ColorScheme) throws {
        let dark = scheme == .dark
        // This canvas is near the contrast boundary, where derived fills need to adapt.
        let neutral: CGFloat = dark ? 0.40 : 0.55
        let colors = CustomThemeColors(
            background: NSColor(srgbRed: neutral, green: neutral, blue: neutral, alpha: 1),
            noteText: dark ? .white : .black
        )
        try #require(colors.issue(for: scheme) == nil)
        let palette = colors.palette(for: scheme)
        for surface in [palette.canvas, palette.raisedFill, palette.homeCardFill,
                        palette.searchMark, palette.searchMarkContrast] {
            #expect(ThemeColor.contrast(colors.noteText.nsColor, surface) >= 4.5)
            #expect(ThemeColor.contrast(palette.secondaryText, surface) >= 4.5)
            #expect(ThemeColor.contrast(palette.metadataText, surface) >= 4.5)
            #expect(ThemeColor.contrast(palette.focus, surface) >= 3)
        }
    }

    @Test
    func noteTextSizeRetainsCurrentDefaultAndFallsBackForUnknownPreference() {
        let defaults = UserDefaults(suiteName: "NoteTextSizeTests.\(UUID().uuidString)")!
        func preference() -> AppStorage<NoteTextSize> {
            AppStorage(wrappedValue: .standard, NoteTextSize.preferenceKey, store: defaults)
        }
        #expect(preference().wrappedValue.points(16) == 16)
        preference().wrappedValue = .large
        #expect(defaults.string(forKey: NoteTextSize.preferenceKey) == NoteTextSize.large.rawValue)
        #expect(preference().wrappedValue.points(16) == 19)
        defaults.set("obsolete", forKey: NoteTextSize.preferenceKey)
        #expect(preference().wrappedValue == .standard)
    }
}

private extension ThemeStore {
    static func hex(_ color: NSColor) -> String {
        let srgb = color.usingColorSpace(.sRGB) ?? color
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        srgb.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "%02X%02X%02X", Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
    }
}

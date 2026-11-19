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
                #expect(ThemeStore.hex(RascSurfacePalette.keepAccentNSColor(for: scheme)) == expectedAccent)
                #expect(ThemeStore.hex(RascSurfacePalette.keepFillNSColor(for: scheme)) == expectedFill)
            }
        }
    }

    @Test
    func versionBumpsOnEveryThemeChange() {
        let store = makeStore()
        let instance = ThemeStore(store: store)
        let initial = instance.version
        instance.selectPreset(.slate)
        #expect(instance.version == initial + 1)
        instance.reset()
        #expect(instance.version == initial + 2)
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

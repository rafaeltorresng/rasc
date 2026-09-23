import Foundation
import Testing
@testable import Rasc

@Suite
struct AppThemeSettingsTests {
    private func makeDefaults() -> UserDefaults {
        let suiteName = "AppThemeSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    @Test
    func defaultThemeIsSystem() {
        let store = AppThemeSettingsStore(userDefaults: makeDefaults())
        #expect(store.load() == .system)
    }

    @Test
    func persistsSelectedTheme() {
        let defaults = makeDefaults()
        let store = AppThemeSettingsStore(userDefaults: defaults)

        store.save(.rascDark)
        #expect(store.load() == .rascDark)

        store.save(.rascLight)
        #expect(store.load() == .rascLight)
    }

    @Test
    func unknownStoredValueFallsBackToSystem() {
        let defaults = makeDefaults()
        defaults.set("custom-theme", forKey: AppThemeSettingsStore.preferenceKey)
        let store = AppThemeSettingsStore(userDefaults: defaults)
        #expect(store.load() == .system)
    }

    @Test
    func fixedThemesMapToNativeAppearances() {
        #expect(AppTheme.system.nsAppearance == nil)
        #expect(AppTheme.rascDark.nsAppearance?.name == .darkAqua)
        #expect(AppTheme.rascLight.nsAppearance?.name == .aqua)
    }
}

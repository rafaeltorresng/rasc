import Foundation

struct RefineLanguagePreferenceResolution: Equatable, Sendable {
    let stored: RefineLanguageSettingsStore.StoredPreference
    let effectivePolicy: RefineLanguagePolicy
    let isUsingFallback: Bool
    let unsupportedSavedLocaleIdentifier: String?
}

struct RefineLanguageSettingsStore {
    static let preferenceKey = "refineLanguagePreference"

    enum StoredPreference: Equatable, Sendable {
        case matchNote
        case fixedLocale(identifier: String)
    }

    private let userDefaults: UserDefaults
    private let supportedLocales: any RefineSupportedLocaleDiscovering

    init(
        userDefaults: UserDefaults = .standard,
        supportedLocales: any RefineSupportedLocaleDiscovering = RefineSupportedLocales()
    ) {
        self.userDefaults = userDefaults
        self.supportedLocales = supportedLocales
    }

    func loadStoredPreference() -> StoredPreference {
        guard let raw = userDefaults.string(forKey: Self.preferenceKey) else {
            return .matchNote
        }
        if raw == "matchNote" {
            return .matchNote
        }
        if raw.hasPrefix("fixed:") {
            let identifier = String(raw.dropFirst("fixed:".count))
            guard !identifier.isEmpty else { return .matchNote }
            return .fixedLocale(identifier: identifier)
        }
        return .matchNote
    }

    func save(_ preference: StoredPreference) {
        switch preference {
        case .matchNote:
            userDefaults.set("matchNote", forKey: Self.preferenceKey)
        case let .fixedLocale(identifier):
            userDefaults.set("fixed:\(identifier)", forKey: Self.preferenceKey)
        }
    }

    func resolveEffectivePreference() -> RefineLanguagePreferenceResolution {
        let stored = loadStoredPreference()
        switch stored {
        case .matchNote:
            return RefineLanguagePreferenceResolution(
                stored: stored,
                effectivePolicy: .matchNote,
                isUsingFallback: false,
                unsupportedSavedLocaleIdentifier: nil
            )
        case let .fixedLocale(identifier):
            if supportedLocales.supportsLocaleIdentifier(identifier) {
                return RefineLanguagePreferenceResolution(
                    stored: stored,
                    effectivePolicy: .fixed(Locale(identifier: identifier)),
                    isUsingFallback: false,
                    unsupportedSavedLocaleIdentifier: nil
                )
            }
            return RefineLanguagePreferenceResolution(
                stored: stored,
                effectivePolicy: .matchNote,
                isUsingFallback: true,
                unsupportedSavedLocaleIdentifier: identifier
            )
        }
    }
}

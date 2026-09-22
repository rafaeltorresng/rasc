import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

struct RefineFixedLocaleOption: Equatable, Sendable, Identifiable {
    let localeIdentifier: String
    let displayName: String
    let label: RefineLanguageLabel

    var id: String { localeIdentifier }
}

protocol RefineSupportedLocaleDiscovering: Sendable {
    func supportedFixedLocaleOptions() -> [RefineFixedLocaleOption]
    func supportsLocaleIdentifier(_ identifier: String) -> Bool
}

struct RefineSupportedLocales: RefineSupportedLocaleDiscovering {
    func supportedFixedLocaleOptions() -> [RefineFixedLocaleOption] {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return Self.discoverOnDevice()
        }
        #endif
        return []
    }

    func supportsLocaleIdentifier(_ identifier: String) -> Bool {
        supportedFixedLocaleOptions().contains { $0.localeIdentifier == identifier }
    }

    #if canImport(FoundationModels)
    @available(macOS 26.0, *)
    private static func discoverOnDevice() -> [RefineFixedLocaleOption] {
        let model = SystemLanguageModel.default
        var bestByLabel: [RefineLanguageLabel: RefineFixedLocaleOption] = [:]

        for language in model.supportedLanguages {
            let locale = Locale(identifier: language.maximalIdentifier)
            guard model.supportsLocale(locale),
                  let label = label(for: language)
            else {
                continue
            }

            let option = RefineFixedLocaleOption(
                localeIdentifier: locale.identifier,
                displayName: localizedDisplayName(for: locale),
                label: label
            )

            if let existing = bestByLabel[label] {
                if prefers(option, over: existing) {
                    bestByLabel[label] = option
                }
            } else {
                bestByLabel[label] = option
            }
        }

        return bestByLabel.values.sorted { lhs, rhs in
            sortRank(for: lhs.label) < sortRank(for: rhs.label)
        }
    }
    #endif

    private static func label(for language: Locale.Language) -> RefineLanguageLabel? {
        guard let code = language.languageCode?.identifier.lowercased() else { return nil }
        if code.hasPrefix("pt") { return .portuguese }
        if code.hasPrefix("en") { return .english }
        if code.hasPrefix("es") { return .spanish }
        return nil
    }

    private static func localizedDisplayName(for locale: Locale) -> String {
        let languageCode = locale.language.languageCode?.identifier ?? locale.identifier
        let languageName = Locale.current.localizedString(forLanguageCode: languageCode) ?? languageCode
        if let region = locale.region?.identifier,
           !region.isEmpty,
           region != "001" {
            let regionName = Locale.current.localizedString(forRegionCode: region) ?? region
            return "\(languageName) (\(regionName))"
        }
        return languageName
    }

    private static func prefers(_ candidate: RefineFixedLocaleOption, over incumbent: RefineFixedLocaleOption) -> Bool {
        preferredRegionScore(candidate.localeIdentifier, label: candidate.label)
            > preferredRegionScore(incumbent.localeIdentifier, label: incumbent.label)
    }

    private static func preferredRegionScore(_ identifier: String, label: RefineLanguageLabel) -> Int {
        let normalized = identifier.lowercased()
        switch label {
        case .portuguese:
            if normalized.contains("pt-br") || normalized.contains("pt_br") { return 3 }
            if normalized.hasPrefix("pt") { return 2 }
            return 1
        case .english:
            if normalized.contains("en-us") || normalized.contains("en_us") { return 3 }
            if normalized.hasPrefix("en") { return 2 }
            return 1
        case .spanish:
            if normalized.contains("es-es") || normalized.contains("es_es") { return 3 }
            if normalized.hasPrefix("es") { return 2 }
            return 1
        case .mixed, .ambiguous, .unknown:
            return 0
        }
    }

    private static func sortRank(for label: RefineLanguageLabel) -> Int {
        switch label {
        case .portuguese: 0
        case .english: 1
        case .spanish: 2
        case .mixed, .ambiguous, .unknown: 3
        }
    }
}

struct RefineFallbackSupportedLocales: RefineSupportedLocaleDiscovering {
    let options: [RefineFixedLocaleOption]

    init(options: [RefineFixedLocaleOption] = []) {
        self.options = options
    }

    func supportedFixedLocaleOptions() -> [RefineFixedLocaleOption] {
        options
    }

    func supportsLocaleIdentifier(_ identifier: String) -> Bool {
        options.contains { $0.localeIdentifier == identifier }
    }
}

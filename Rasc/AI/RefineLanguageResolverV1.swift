import Foundation

/// Pre-M12B-007B production resolver retained for eval shadow comparisons.
enum RefineLanguageResolverV1 {
    static func systemFallbackLocale() -> Locale {
        for identifier in Locale.preferredLanguages {
            let normalized = identifier.lowercased()
            if normalized.hasPrefix("pt") {
                return Locale(identifier: "pt-BR")
            }
            if normalized.hasPrefix("es") {
                return Locale(identifier: "es-ES")
            }
            if normalized.hasPrefix("en") {
                return Locale(identifier: "en-US")
            }
        }
        return Locale(identifier: "en-US")
    }

    static func resolve(request: RefinementRequest) -> ResolvedRefineLanguage {
        resolve(
            policy: request.languagePolicy,
            inputText: request.inputText,
            surroundingText: surroundingText(for: request)
        )
    }

    static func resolve(
        policy: RefineLanguagePolicy,
        inputText: String,
        surroundingText: String?
    ) -> ResolvedRefineLanguage {
        switch policy {
        case let .fixed(locale):
            let label = label(for: locale) ?? .english
            return ResolvedRefineLanguage(
                label: label,
                localeIdentifier: locale.identifier,
                confidence: .high,
                usedSystemFallback: false,
                resolverReason: "fixed_locale_policy"
            )
        case .matchNote:
            return resolveMatchNote(inputText: inputText, surroundingText: surroundingText)
        }
    }

    private static func resolveMatchNote(
        inputText: String,
        surroundingText: String?
    ) -> ResolvedRefineLanguage {
        let combined = [surroundingText, inputText]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

        let detectionText = combined.isEmpty ? inputText : combined
        let detected = RefineLanguageDetection.detect(in: detectionText)

        switch detected {
        case .portuguese, .english, .spanish, .mixed:
            let reason = surroundingText?.isEmpty == false ? "detected_from_note_and_context" : "detected_from_note"
            return ResolvedRefineLanguage(
                label: detected,
                localeIdentifier: RefineLanguageDetection.localeIdentifier(for: detected),
                confidence: .high,
                usedSystemFallback: false,
                resolverReason: detected == .mixed ? "mixed_input" : reason
            )
        case .ambiguous, .unknown:
            let fallback = systemFallbackLocale()
            let fallbackLabel = label(for: fallback) ?? .english
            return ResolvedRefineLanguage(
                label: fallbackLabel,
                localeIdentifier: fallback.identifier,
                confidence: .insufficient,
                usedSystemFallback: true,
                resolverReason: "system_locale_fallback_ambiguous_input"
            )
        }
    }

    private static func surroundingText(for request: RefinementRequest) -> String? {
        guard let context = request.selectionContext else { return nil }
        return [context.before, context.after]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func label(for locale: Locale) -> RefineLanguageLabel? {
        let identifier = locale.identifier.lowercased()
        if identifier.hasPrefix("pt") { return .portuguese }
        if identifier.hasPrefix("es") { return .spanish }
        if identifier.hasPrefix("en") { return .english }
        return nil
    }
}

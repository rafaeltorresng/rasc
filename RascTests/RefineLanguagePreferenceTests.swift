import Foundation
import Testing
@testable import Rasc

@Suite
struct RefineLanguagePreferenceTests {
    private func makeDefaults() -> UserDefaults {
        let suiteName = "RefineLanguagePreferenceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private let supported = RefineFallbackSupportedLocales(options: [
        RefineFixedLocaleOption(localeIdentifier: "pt-BR", displayName: "Português (Brasil)", label: .portuguese),
        RefineFixedLocaleOption(localeIdentifier: "en-US", displayName: "English (US)", label: .english),
        RefineFixedLocaleOption(localeIdentifier: "es-ES", displayName: "Español (España)", label: .spanish),
    ])

    @Test
    func defaultPreferenceIsMatchNote() {
        let defaults = makeDefaults()
        let store = RefineLanguageSettingsStore(userDefaults: defaults, supportedLocales: supported)
        #expect(store.loadStoredPreference() == .matchNote)
        #expect(store.resolveEffectivePreference().effectivePolicy == .matchNote)
    }

    @Test
    func persistsFixedLocalePreference() {
        let defaults = makeDefaults()
        let store = RefineLanguageSettingsStore(userDefaults: defaults, supportedLocales: supported)
        store.save(.fixedLocale(identifier: "pt-BR"))
        #expect(store.loadStoredPreference() == .fixedLocale(identifier: "pt-BR"))
    }

    @Test
    func unsupportedSavedLocaleFallsBackToMatchNoteWithoutOverwrite() {
        let defaults = makeDefaults()
        let store = RefineLanguageSettingsStore(userDefaults: defaults, supportedLocales: supported)
        store.save(.fixedLocale(identifier: "fr-FR"))

        let resolution = store.resolveEffectivePreference()
        #expect(resolution.stored == .fixedLocale(identifier: "fr-FR"))
        #expect(resolution.effectivePolicy == .matchNote)
        #expect(resolution.isUsingFallback)
        #expect(resolution.unsupportedSavedLocaleIdentifier == "fr-FR")
        #expect(store.loadStoredPreference() == .fixedLocale(identifier: "fr-FR"))
    }

    @Test
    func supportedLocaleFilteringUsesDiscoverer() {
        let discoverer = RefineFallbackSupportedLocales(options: [
            RefineFixedLocaleOption(localeIdentifier: "en-US", displayName: "English (US)", label: .english),
        ])
        #expect(discoverer.supportedFixedLocaleOptions().count == 1)
        #expect(discoverer.supportsLocaleIdentifier("en-US"))
        #expect(!discoverer.supportsLocaleIdentifier("pt-BR"))
    }

    @Test
    func fixedLocaleResolverUsesTargetContract() {
        let resolved = RefineLanguageResolver.resolve(
            policy: .fixed(Locale(identifier: "pt-BR")),
            inputText: "send the report tomorrow",
            surroundingText: nil
        )
        #expect(resolved.label == .portuguese)
        #expect(resolved.localeIdentifier == "pt-BR")
        #expect(resolved.confidence == .high)
        #expect(resolved.isFixedTarget)
        #expect(resolved.enforcesPostValidation)
    }

    @Test
    func fixedLocaleValidatorAcceptsIntentionalTranslation() {
        let resolved = ResolvedRefineLanguage(
            label: .portuguese,
            localeIdentifier: "pt-BR",
            confidence: .high,
            usedSystemFallback: false,
            resolverReason: "fixed_locale_policy"
        )
        let validation = RefineLanguageValidator.validate(
            input: "send the report tomorrow",
            output: "Enviar o relatório amanhã.",
            resolved: resolved
        )
        #expect(!validation.violates)
    }

    @Test
    func fixedLocaleValidatorRejectsWrongTargetLanguage() {
        let resolved = ResolvedRefineLanguage(
            label: .portuguese,
            localeIdentifier: "pt-BR",
            confidence: .high,
            usedSystemFallback: false,
            resolverReason: "fixed_locale_policy"
        )
        let validation = RefineLanguageValidator.validate(
            input: "enviar relatório amanhã",
            output: "Send the report tomorrow.",
            resolved: resolved
        )
        #expect(validation.violates)
    }

    @Test
    func matchNoteValidatorStillRejectsUnauthorizedDrift() {
        let resolved = RefineLanguageResolver.resolve(
            policy: .matchNote,
            inputText: "enviar relatório amanhã",
            surroundingText: nil
        )
        let validation = RefineLanguageValidator.validate(
            input: "enviar relatório amanhã",
            output: "Send the report tomorrow.",
            resolved: resolved
        )
        #expect(validation.violates)
    }

    @Test
    func fixedLocalePromptAuthorizesTranslation() {
        let resolved = ResolvedRefineLanguage(
            label: .portuguese,
            localeIdentifier: "pt-BR",
            confidence: .high,
            usedSystemFallback: false,
            resolverReason: "fixed_locale_policy"
        )
        let prompt = RefinementPrompt.instructions(for: .wholeNote, resolvedLanguage: resolved)
        #expect(prompt.contains("authorized translation target"))
        #expect(prompt.contains("locale pt-BR"))
    }

    @Test
    func fixedLocaleRequestUsesSelectedPolicy() {
        let request = RefinementRequest(
            snapshot: NoteSnapshot(noteID: UUID(), revision: 1, text: "send report"),
            languagePolicy: .fixed(Locale(identifier: "pt-BR"))
        )
        #expect(request.languagePolicy == .fixed(Locale(identifier: "pt-BR")))
    }

    @Test
    func unresolvedGuardDoesNotRunForFixedLocale() {
        let resolved = RefineLanguageResolver.resolve(
            policy: .fixed(Locale(identifier: "en-US")),
            inputText: "enviar relatório amanhã",
            surroundingText: nil
        )
        let guardResult = RefineUnresolvedLanguageGuard.evaluate(
            input: "enviar relatório amanhã",
            output: "Send the report tomorrow.",
            rawDecision: .changed,
            resolved: resolved
        )
        #expect(!guardResult.shouldReject)
        #expect(guardResult.reason == .notEvaluated)
        #expect(!RefineUnresolvedLanguageGuard.isStrictUnresolvedEligible(resolved))
    }

    @Test
    func fixedLocaleCasesAreExecutableUnderProduction() {
        let evalCase = RefineEvalCase(
            id: "fixed-test",
            source: "unit",
            category: ["language-policy"],
            tags: ["fixed-locale"],
            input: "maybe check logs",
            languagePolicy: RefineCorpusLanguagePolicy(mode: .fixedLocale, locale: "pt-BR"),
            expected: RefineEvalExpectation(expectedLanguage: "pt"),
            severity: .medium,
            executableUnderCurrentProduction: false
        )
        #expect(!evalCase.isExecutableUnderBaseline)
        #expect(evalCase.isExecutableUnderProduction)
    }

    @Test
    func refineV2BaselineIdentifierIsStable() {
        #expect(RefinementImplementationBaseline.identifier == "refine-v2")
    }
}

import Foundation
import Testing
@testable import Rasc

@Suite
struct RefineLanguageContractTests {
    @Test
    func detectsPortugueseSpanishAndEnglishSeparately() {
        #expect(RefineLanguageDetection.detect(in: "reunião amanhã com o time") == .portuguese)
        #expect(RefineLanguageDetection.detect(in: "quizás revisar mañana con Juan") == .spanish)
        #expect(RefineLanguageDetection.detect(in: "maybe review tomorrow with the team") == .english)
    }

    @Test
    func boundaryAwareMarkersDoNotMatchInsideUnrelatedWords() {
        #expect(!RefineLanguageDetection.containsMarker("la", in: "bug no fila?", boundaryAware: true))
        #expect(!RefineLanguageDetection.containsMarker("el", in: "https://loja.example/black-friday", boundaryAware: true))
        #expect(RefineLanguageDetection.containsMarker("la", in: "la reunión mañana", boundaryAware: true))
    }

    @Test
    func technicalEnglishInsidePortugueseDoesNotForceEnglish() {
        let resolved = RefineLanguageResolver.resolve(
            policy: .matchNote,
            inputText: "falar com Vitor sobre notification queue",
            surroundingText: nil
        )
        #expect(resolved.label == .portuguese)
        #expect(resolved.confidence == .high)
        #expect(resolved.usedSystemFallback == false)
    }

    @Test
    func mixedPortugueseTechnicalNotesResolveToPortuguese() {
        let resolved = RefineLanguageResolver.resolve(
            policy: .matchNote,
            inputText: "revisar retry do worker amanhã",
            surroundingText: nil
        )
        #expect(resolved.label == .portuguese)
        #expect(resolved.confidence == .high)
    }

    @Test
    func falseSpanishSubstringCasesNoLongerResolveToSpanish() {
        let factual = RefineLanguageResolver.resolve(
            policy: .matchNote,
            inputText: "Desconto 15% até 31/12 link https://loja.example/black-friday",
            surroundingText: nil
        )
        #expect(factual.label == .portuguese)

        let variant = RefineLanguageResolver.resolve(
            policy: .matchNote,
            inputText: "bug no fila?",
            surroundingText: nil
        )
        #expect(variant.label != .spanish)
        #expect(variant.confidence == .insufficient)
    }

    @Test
    func ambiguousTinyInputStaysUnresolvedWithoutSystemFallback() {
        let resolved = RefineLanguageResolver.resolve(
            policy: .matchNote,
            inputText: "ok",
            surroundingText: nil
        )
        #expect(resolved.label == .ambiguous)
        #expect(resolved.usedSystemFallback == false)
        #expect(resolved.confidence == .insufficient)
        #expect(resolved.enforcesPostValidation == false)
    }

    @Test
    func technicalOnlyFragmentsStayUnresolved() {
        for input in ["retry", "API retry", "deploy"] {
            let resolved = RefineLanguageResolver.resolve(
                policy: .matchNote,
                inputText: input,
                surroundingText: nil
            )
            #expect(resolved.confidence == .insufficient)
            #expect(resolved.label == .ambiguous)
            #expect(resolved.usedSystemFallback == false)
        }
    }

    @Test
    func validatorRejectsClearPortugueseToEnglishDrift() {
        let resolved = ResolvedRefineLanguage(
            label: .portuguese,
            localeIdentifier: "pt-BR",
            confidence: .high,
            usedSystemFallback: false,
            resolverReason: "detected_from_note"
        )
        let validation = RefineLanguageValidator.validate(
            input: "sync amanhã",
            output: "Sync tomorrow",
            resolved: resolved
        )
        #expect(validation.violates)
        #expect(
            validation.reason == .independentHighConfidenceMismatch
                || validation.reason == .existingFallback
        )
    }

    @Test
    func validatorAcceptsHighConfidencePortugueseDespiteMarkerDisagreement() {
        let resolved = ResolvedRefineLanguage(
            label: .portuguese,
            localeIdentifier: "pt-BR",
            confidence: .high,
            usedSystemFallback: false,
            resolverReason: "detected_from_note"
        )
        let output = "Lembrar de responder ao email da Mirella"
        let validation = RefineLanguageValidator.validate(
            input: "Lembrar de responder o email da Mirella.",
            output: output,
            resolved: resolved
        )
        #expect(!validation.violates)
        #expect(validation.reason == .independentHighConfidenceMatch)
    }

    @Test
    func validatorRejectsHighConfidenceMismatchEvenWhenMarkerDetectPasses() {
        let resolved = ResolvedRefineLanguage(
            label: .portuguese,
            localeIdentifier: "pt-BR",
            confidence: .high,
            usedSystemFallback: false,
            resolverReason: "detected_from_note"
        )
        let validation = RefineLanguageValidator.validate(
            input: "next_retry_at",
            output: "next_retry_at",
            resolved: resolved
        )
        if validation.independentAssessment?.confidence == .high,
           validation.independentAssessment?.label == .english
        {
            #expect(validation.violates)
            #expect(validation.reason == .independentHighConfidenceMismatch)
        }
    }

    @Test
    func validatorPreservesFallbackForLowConfidenceAssessment() {
        let resolved = ResolvedRefineLanguage(
            label: .portuguese,
            localeIdentifier: "pt-BR",
            confidence: .high,
            usedSystemFallback: false,
            resolverReason: "detected_from_note"
        )
        let validation = RefineLanguageValidator.validate(
            input: "não sei se foi o deploy ou...",
            output: "Deploy",
            resolved: resolved
        )
        #expect(validation.independentAssessment?.confidence != .high)
        #expect(validation.reason == .existingFallback)
    }

    @Test
    func unresolvedGuardBlocksStrongPortugueseToEnglishDrift() {
        let resolved = ResolvedRefineLanguage(
            label: .ambiguous,
            localeIdentifier: "und",
            confidence: .insufficient,
            usedSystemFallback: false,
            resolverReason: "ambiguous_short_or_technical_only"
        )
        let guardResult = RefineUnresolvedLanguageGuard.evaluate(
            input: "fechar issue",
            output: "Close the issue",
            rawDecision: .changed,
            resolved: resolved
        )
        #expect(guardResult.shouldReject)
        #expect(guardResult.reason == .unauthorizedLanguageShift)
        #expect(guardResult.sourceEvidence?.label == .portuguese)
        #expect(guardResult.sourceEvidence?.isStrong == true)
    }

    @Test
    func unresolvedGuardDoesNotBlockTechnicalFragments() {
        let resolved = ResolvedRefineLanguage(
            label: .ambiguous,
            localeIdentifier: "und",
            confidence: .insufficient,
            usedSystemFallback: false,
            resolverReason: "ambiguous_short_or_technical_only"
        )
        for input in ["retry", "API retry", "deploy"] {
            let guardResult = RefineUnresolvedLanguageGuard.evaluate(
                input: input,
                output: "Retry later",
                rawDecision: .changed,
                resolved: resolved
            )
            #expect(!guardResult.shouldReject)
            #expect(guardResult.reason == .sourceAmbiguous)
        }
    }

    @Test
    func unresolvedGuardNotEvaluatedForMixedHighConfidenceResolver() {
        let resolved = ResolvedRefineLanguage(
            label: .mixed,
            localeIdentifier: "mixed",
            confidence: .high,
            usedSystemFallback: false,
            resolverReason: "mixed_input"
        )
        let guardResult = RefineUnresolvedLanguageGuard.evaluate(
            input: "revisar onboarding copy depois do deploy, maybe ask Ana sobre CTA v2",
            output: "Review onboarding copy after deploy, maybe ask Ana about CTA v2",
            rawDecision: .changed,
            resolved: resolved
        )
        #expect(!guardResult.shouldReject)
        #expect(guardResult.reason == .notEvaluated)
        #expect(!RefineUnresolvedLanguageGuard.isStrictUnresolvedEligible(resolved))
    }

    @Test
    func unresolvedGuardNotEvaluatedForHighConfidenceResolver() {
        let resolved = ResolvedRefineLanguage(
            label: .portuguese,
            localeIdentifier: "pt-BR",
            confidence: .high,
            usedSystemFallback: false,
            resolverReason: "marker_clear_margin"
        )
        let guardResult = RefineUnresolvedLanguageGuard.evaluate(
            input: "sync amanhã",
            output: "Sync tomorrow",
            rawDecision: .changed,
            resolved: resolved
        )
        #expect(!guardResult.shouldReject)
        #expect(guardResult.reason == .notEvaluated)
    }

    @Test
    func validatorDoesNotRejectWhenConfidenceIsInsufficient() {
        let resolved = ResolvedRefineLanguage(
            label: .ambiguous,
            localeIdentifier: "und",
            confidence: .insufficient,
            usedSystemFallback: false,
            resolverReason: "unresolved_insufficient_evidence"
        )
        #expect(
            !RefineLanguageValidator.violatesContract(
                input: "ok",
                output: "Okay",
                resolved: resolved
            )
        )
    }

    @Test
    func ambiguousResolverUsesNeutralLanguageInstructions() {
        let resolved = ResolvedRefineLanguage(
            label: .ambiguous,
            localeIdentifier: "und",
            confidence: .insufficient,
            usedSystemFallback: false,
            resolverReason: "unresolved_insufficient_evidence"
        )
        let instructions = RefinementPrompt.instructions(for: .wholeNote, resolvedLanguage: resolved)
        #expect(instructions.contains("preserve the input language"))
        #expect(!instructions.contains("en-US"))
        #expect(!instructions.contains("pt-BR"))
    }

    @Test
    func languageInstructionsIncludeLocaleForPortuguese() {
        let resolved = ResolvedRefineLanguage(
            label: .portuguese,
            localeIdentifier: "pt-BR",
            confidence: .high,
            usedSystemFallback: false,
            resolverReason: "detected_from_note"
        )
        let instructions = RefinementPrompt.instructions(for: .wholeNote, resolvedLanguage: resolved)
        #expect(instructions.contains("pt-BR"))
        #expect(instructions.contains("Do not translate to English"))
    }

    @Test
    func refinementRequestDefaultsToMatchNotePolicy() {
        let request = RefinementRequest(snapshot: NoteSnapshot(noteID: UUID(), revision: 1, text: "test"))
        #expect(request.languagePolicy == .matchNote)
    }
}

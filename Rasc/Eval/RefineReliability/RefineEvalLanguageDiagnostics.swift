import Foundation

enum RefineEvalLanguageRootCause: String, Codable, Sendable {
    case resolverFailure
    case generationIgnoredContract
    case validatorFalseNegative
    case validatorFalsePositive
    case lowConfidenceUnclassifiable
    case evaluatorDisagreement
    case validatorCatch
    case other
}

struct RefineEvalLanguageDiagnostics: Codable, Equatable, Sendable {
    var expectedLanguage: String?
    var languagePolicy: String
    var resolvedLocale: String?
    var resolvedLabel: String?
    var resolverConfidence: String?
    var resolverReason: String?
    var legacyResolvedLocale: String?
    var legacyResolvedLabel: String?
    var legacyResolverConfidence: String?
    var legacyResolverReason: String?
    var legacyUsedSystemFallback: Bool?
    var rawGeneratedText: String?
    var rawGeneratedDecision: String?
    var generatedLanguageAssessment: RefineEvalIndependentLanguageAssessment?
    var generationLanguageCorrect: Bool?
    var userVisibleLanguageSafe: Bool?
    var postValidatorEvaluated: Bool?
    var postValidatorRejected: Bool?
    var markerAssessmentLabel: String?
    var independentAssessmentLabel: String?
    var independentAssessmentConfidence: String?
    var validatorDecisionReason: String?
    var unresolvedGuardEvaluated: Bool?
    var unresolvedGuardRejected: Bool?
    var sourceEvidenceLabel: String?
    var sourceEvidenceStrong: Bool?
    var unresolvedGuardDecisionReason: String?
    var unresolvedGuardOutputAssessmentLabel: String?
    var unresolvedGuardOutputAssessmentConfidence: String?
    var finalDecision: String?
    var rejectedIntoNoChange: Bool
    var decisionReason: String?
    var rootCause: RefineEvalLanguageRootCause?
    var rootCauseExplanation: String?
}

enum RefineEvalLanguageDiagnosticsBuilder {
    static func build(
        evalCase: RefineEvalCase,
        record: RefineEvalRunRecord,
        trace: RefinementLanguageTrace?
    ) -> RefineEvalLanguageDiagnostics {
        let expected = evalCase.expected.expectedLanguage
        let policy = evalCase.languagePolicy.mode.rawValue
        let rawText = trace?.rawText ?? record.output
        let rawDecision = trace?.rawDecision ?? record.decision

        let generationAssessment = rawText.map {
            RefineEvalIndependentLanguageAssessor.assess(
                text: $0,
                authoritativeExpectedTag: expected
            )
        }

        let drift = RefineEvalIndependentLanguageAssessor.isUnauthorizedDrift(
            input: evalCase.input,
            output: rawText ?? evalCase.input,
            expectedTag: expected
        )

        let generationCorrect = rawDecision == .noChange || !drift.generationDrift
        let userVisibleSafe = !(record.decision == .changed && drift.drift)
        let rejected = trace?.validatorRejected == true
            || trace?.unresolvedGuardRejected == true
            || record.decision == .noChange && rawDecision == .changed

        var diagnostics = RefineEvalLanguageDiagnostics(
            expectedLanguage: expected,
            languagePolicy: policy,
            resolvedLocale: trace?.resolvedLocale,
            resolvedLabel: trace?.resolvedLabel,
            resolverConfidence: trace?.resolverConfidence,
            resolverReason: trace?.resolverReason,
            legacyResolvedLocale: trace?.legacyResolvedLocale,
            legacyResolvedLabel: trace?.legacyResolvedLabel,
            legacyResolverConfidence: trace?.legacyResolverConfidence,
            legacyResolverReason: trace?.legacyResolverReason,
            legacyUsedSystemFallback: trace?.legacyUsedSystemFallback,
            rawGeneratedText: rawText,
            rawGeneratedDecision: rawDecision?.rawValue,
            generatedLanguageAssessment: generationAssessment,
            generationLanguageCorrect: generationCorrect,
            userVisibleLanguageSafe: userVisibleSafe,
            postValidatorEvaluated: trace?.validatorEvaluated,
            postValidatorRejected: trace?.validatorRejected,
            markerAssessmentLabel: trace?.markerAssessmentLabel,
            independentAssessmentLabel: trace?.independentAssessmentLabel,
            independentAssessmentConfidence: trace?.independentAssessmentConfidence,
            validatorDecisionReason: trace?.validatorDecisionReason,
            unresolvedGuardEvaluated: trace?.unresolvedGuardEvaluated,
            unresolvedGuardRejected: trace?.unresolvedGuardRejected,
            sourceEvidenceLabel: trace?.sourceEvidenceLabel,
            sourceEvidenceStrong: trace?.sourceEvidenceStrong,
            unresolvedGuardDecisionReason: trace?.unresolvedGuardDecisionReason,
            unresolvedGuardOutputAssessmentLabel: trace?.unresolvedGuardOutputAssessmentLabel,
            unresolvedGuardOutputAssessmentConfidence: trace?.unresolvedGuardOutputAssessmentConfidence,
            finalDecision: record.decision?.rawValue,
            rejectedIntoNoChange: rejected,
            decisionReason: trace?.decisionReason
        )

        let (rootCause, explanation) = classify(
            evalCase: evalCase,
            diagnostics: diagnostics,
            drift: drift,
            trace: trace
        )
        diagnostics.rootCause = rootCause
        diagnostics.rootCauseExplanation = explanation
        return diagnostics
    }

    private static func classify(
        evalCase: RefineEvalCase,
        diagnostics: RefineEvalLanguageDiagnostics,
        drift: (drift: Bool, assessment: RefineEvalIndependentLanguageAssessment, generationDrift: Bool),
        trace: RefinementLanguageTrace?
    ) -> (RefineEvalLanguageRootCause, String) {
        let expected = evalCase.expected.expectedLanguage

        if diagnostics.generatedLanguageAssessment?.disagreesWithMarkers == true {
            return (.evaluatorDisagreement, "Independent NaturalLanguage/marker assessment disagrees on output language.")
        }

        if trace?.resolverConfidence == "insufficient" && drift.generationDrift {
            if trace?.legacyUsedSystemFallback == true {
                return (.lowConfidenceUnclassifiable, "Legacy resolver used system fallback; generation drift cannot be attributed confidently.")
            }
            return (.lowConfidenceUnclassifiable, "Resolver left language unresolved; generation drift cannot be attributed confidently.")
        }

        if let expected,
           let resolved = trace?.resolvedLabel,
           normalize(resolved) != normalize(expected),
           trace?.resolverConfidence == "high"
        {
            return (.resolverFailure, "Resolver chose \(resolved) but dataset expects \(expected).")
        }

        if trace?.validatorRejected == true && drift.generationDrift {
            return (.validatorCatch, "Generation violated language contract; validator rejected to noChange.")
        }

        if trace?.validatorRejected == true && !drift.generationDrift {
            return (.validatorFalsePositive, "Validator rejected output that independent assessment considers acceptable.")
        }

        if trace?.unresolvedGuardRejected == true && drift.generationDrift {
            return (.validatorCatch, "Unresolved-language guard blocked unauthorized translation before user-visible output.")
        }

        if trace?.unresolvedGuardRejected == true && !drift.generationDrift {
            return (.validatorFalsePositive, "Unresolved-language guard rejected acceptable output.")
        }

        if drift.generationDrift && diagnostics.finalDecision == "changed" {
            if trace?.validatorEvaluated == true {
                return (.validatorFalseNegative, "Unauthorized translation reached user-visible changed output.")
            }
            return (.generationIgnoredContract, "Model produced translated output; validation was not enforced.")
        }

        if drift.generationDrift && diagnostics.rejectedIntoNoChange {
            return (.validatorCatch, "Unauthorized translation blocked before user-visible output.")
        }

        if drift.drift {
            return (.generationIgnoredContract, "Independent assessment detected unauthorized translation.")
        }

        return (.other, "No language failure or not language-related.")
    }

    private static func normalize(_ tag: String) -> String {
        switch tag.lowercased() {
        case "portuguese", "pt", "pt-br": "pt"
        case "english", "en", "en-us": "en"
        case "spanish", "es", "es-es": "es"
        case "mixed": "mixed"
        default: tag.lowercased()
        }
    }
}


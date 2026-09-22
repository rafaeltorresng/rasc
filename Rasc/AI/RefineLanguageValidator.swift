import Foundation

enum RefineLanguageValidatorDecisionReason: String, Codable, Sendable, Equatable {
    case independentHighConfidenceMatch
    case independentHighConfidenceMismatch
    case existingFallback
    case notEvaluated
}

struct RefineLanguageValidationResult: Equatable, Sendable {
    var violates: Bool
    var reason: RefineLanguageValidatorDecisionReason
    var markerAssessment: RefineLanguageLabel?
    var independentAssessment: RefineIndependentLanguageAssessment?
}

enum RefineLanguageValidator {
    /// Returns true when output clearly violates the resolved language contract.
    /// Only enforced when resolution confidence is high.
    static func violatesContract(
        input: String,
        output: String,
        resolved: ResolvedRefineLanguage
    ) -> Bool {
        validate(input: input, output: output, resolved: resolved).violates
    }

    static func validate(
        input: String,
        output: String,
        resolved: ResolvedRefineLanguage
    ) -> RefineLanguageValidationResult {
        guard resolved.enforcesPostValidation else {
            return RefineLanguageValidationResult(
                violates: false,
                reason: .notEvaluated,
                markerAssessment: nil,
                independentAssessment: nil
            )
        }

        let independent = RefineIndependentLanguageAssessor.assess(text: output)
        let markerLanguage = independent.markerLabel

        if independent.confidence == .high {
            if labelsMatch(independent.label, resolved.label) {
                return RefineLanguageValidationResult(
                    violates: false,
                    reason: .independentHighConfidenceMatch,
                    markerAssessment: markerLanguage,
                    independentAssessment: independent
                )
            }

            if isConfidentMismatch(independent.label, against: resolved.label) {
                return RefineLanguageValidationResult(
                    violates: true,
                    reason: .independentHighConfidenceMismatch,
                    markerAssessment: markerLanguage,
                    independentAssessment: independent
                )
            }
        }

        let fallbackViolates = markerFallbackViolates(
            input: input,
            markerLanguage: markerLanguage,
            resolved: resolved
        )
        return RefineLanguageValidationResult(
            violates: fallbackViolates,
            reason: .existingFallback,
            markerAssessment: markerLanguage,
            independentAssessment: independent
        )
    }

    private static func markerFallbackViolates(
        input: String,
        markerLanguage: RefineLanguageLabel,
        resolved: ResolvedRefineLanguage
    ) -> Bool {
        if markerLanguage == .ambiguous {
            return false
        }

        switch resolved.label {
        case .mixed:
            if markerLanguage == .english {
                let inputLanguage = RefineLanguageDetection.detect(in: input, ignoreTechnicalEnglishBoost: true)
                if inputLanguage == .portuguese || inputLanguage == .spanish {
                    return true
                }
            }
            return false
        case .portuguese, .spanish, .english:
            if markerLanguage == .mixed {
                return false
            }
            return markerLanguage != resolved.label
        case .ambiguous, .unknown:
            return false
        }
    }

    private static func labelsMatch(_ independent: RefineLanguageLabel, _ resolved: RefineLanguageLabel) -> Bool {
        independent == resolved
    }

    private static func isConfidentMismatch(
        _ independent: RefineLanguageLabel,
        against resolved: RefineLanguageLabel
    ) -> Bool {
        switch independent {
        case .mixed, .ambiguous, .unknown:
            false
        case .portuguese, .spanish, .english:
            independent != resolved
        }
    }
}

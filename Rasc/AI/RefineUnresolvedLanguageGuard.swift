import Foundation

enum RefineUnresolvedLanguageGuardDecisionReason: String, Codable, Sendable, Equatable {
    case notEvaluated
    case rawNoChange
    case sourceAmbiguous
    case outputNotStrong
    case unauthorizedLanguageShift
    case passed
}

struct RefineUnresolvedLanguageGuardResult: Equatable, Sendable {
    var shouldReject: Bool
    var reason: RefineUnresolvedLanguageGuardDecisionReason
    var sourceEvidence: RefineLanguageSourceEvidence?
    var outputAssessment: RefineIndependentLanguageAssessment?
}

enum RefineUnresolvedLanguageGuard {
    /// M12B-007G: guard runs only for genuinely unresolved resolver output.
    static func isStrictUnresolvedEligible(_ resolved: ResolvedRefineLanguage) -> Bool {
        guard resolved.confidence == .insufficient else { return false }
        guard !resolved.enforcesPostValidation else { return false }
        switch resolved.label {
        case .ambiguous, .unknown:
            return true
        case .mixed, .portuguese, .english, .spanish:
            return false
        }
    }

    /// Safety guard for strict-unresolved inputs only. Does not upgrade resolution confidence.
    static func evaluate(
        input: String,
        output: String,
        rawDecision: RefinementDecision,
        resolved: ResolvedRefineLanguage
    ) -> RefineUnresolvedLanguageGuardResult {
        guard isStrictUnresolvedEligible(resolved) else {
            return RefineUnresolvedLanguageGuardResult(
                shouldReject: false,
                reason: .notEvaluated,
                sourceEvidence: nil,
                outputAssessment: nil
            )
        }

        guard rawDecision == .changed else {
            return RefineUnresolvedLanguageGuardResult(
                shouldReject: false,
                reason: .rawNoChange,
                sourceEvidence: RefineLanguageSourceEvidenceAssessor.assess(in: input),
                outputAssessment: RefineIndependentLanguageAssessor.assess(text: output)
            )
        }

        let sourceEvidence = RefineLanguageSourceEvidenceAssessor.assess(in: input)
        let outputAssessment = RefineIndependentLanguageAssessor.assess(text: output)

        if sourceEvidence.label == .ambiguous || sourceEvidence.label == .mixed || !sourceEvidence.isStrong {
            return RefineUnresolvedLanguageGuardResult(
                shouldReject: false,
                reason: .sourceAmbiguous,
                sourceEvidence: sourceEvidence,
                outputAssessment: outputAssessment
            )
        }

        guard outputAssessment.confidence == .high else {
            return RefineUnresolvedLanguageGuardResult(
                shouldReject: false,
                reason: .outputNotStrong,
                sourceEvidence: sourceEvidence,
                outputAssessment: outputAssessment
            )
        }

        guard isRomanceOrEnglish(outputAssessment.label) else {
            return RefineUnresolvedLanguageGuardResult(
                shouldReject: false,
                reason: .outputNotStrong,
                sourceEvidence: sourceEvidence,
                outputAssessment: outputAssessment
            )
        }

        if outputAssessment.label == sourceEvidence.label {
            return RefineUnresolvedLanguageGuardResult(
                shouldReject: false,
                reason: .passed,
                sourceEvidence: sourceEvidence,
                outputAssessment: outputAssessment
            )
        }

        return RefineUnresolvedLanguageGuardResult(
            shouldReject: true,
            reason: .unauthorizedLanguageShift,
            sourceEvidence: sourceEvidence,
            outputAssessment: outputAssessment
        )
    }

    private static func isRomanceOrEnglish(_ label: RefineLanguageLabel) -> Bool {
        switch label {
        case .portuguese, .english, .spanish:
            true
        case .mixed, .ambiguous, .unknown:
            false
        }
    }
}

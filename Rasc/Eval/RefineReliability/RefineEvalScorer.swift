import Foundation

enum RefineEvalScorer {
    static func score(
        case evalCase: RefineEvalCase,
        runIndex: Int,
        record: RefineEvalRunRecord
    ) -> RefineEvalCaseScore {
        var failures: [RefineObjectiveFailure] = []
        var semanticReasons: [String] = []

        if let skipped = record.skippedReason {
            failures.append(
                RefineObjectiveFailure(
                    kind: .skippedNotExecutable,
                    message: skipped,
                    severity: .low
                )
            )
            return RefineEvalCaseScore(
                caseID: evalCase.id,
                runIndex: runIndex,
                objectiveFailures: failures,
                requiresSemanticReview: false,
                semanticReviewReasons: [],
                requiresHumanReview: false,
                evaluatorDisagreement: false,
                languageBehavior: nil,
                passedObjectively: false,
                inputLanguage: evalCase.primaryLanguageTag,
                outputLanguage: nil,
                expansionRatio: nil,
                latencyMs: record.latencyMs,
                decision: record.decision
            )
        }

        if let providerError = record.providerError {
            failures.append(
                RefineObjectiveFailure(
                    kind: .providerError,
                    message: providerError,
                    severity: evalCase.severity
                )
            )
        }

        if let rejection = record.productionRejection {
            failures.append(
                RefineObjectiveFailure(
                    kind: .productionGuardRejection,
                    message: rejection,
                    severity: evalCase.severity
                )
            )
        }

        guard let output = record.output, let decision = record.decision else {
            return RefineEvalCaseScore(
                caseID: evalCase.id,
                runIndex: runIndex,
                objectiveFailures: failures,
                requiresSemanticReview: false,
                semanticReviewReasons: [],
                requiresHumanReview: false,
                evaluatorDisagreement: false,
                languageBehavior: nil,
                passedObjectively: failures.isEmpty,
                inputLanguage: evalCase.primaryLanguageTag,
                outputLanguage: nil,
                expansionRatio: nil,
                latencyMs: record.latencyMs,
                decision: record.decision
            )
        }

        let input = evalCase.input
        let inputCount = max(1, input.count)
        let expansionRatio = Double(output.count) / Double(inputCount)
        let outputLanguage = RefineEvalLanguageAnalyzer.detectLanguage(in: output).rawValue

        if output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            failures.append(
                RefineObjectiveFailure(
                    kind: .emptyOutput,
                    message: "Output was empty.",
                    severity: .critical
                )
            )
        }

        if let expectsNoChange = evalCase.expected.expectsNoChange, expectsNoChange {
            if decision != .noChange || normalize(output) != normalize(input) {
                failures.append(
                    RefineObjectiveFailure(
                        kind: .unexpectedChange,
                        message: "Expected strict noChange.",
                        severity: evalCase.severity
                    )
                )
            }
        }

        if let exact = evalCase.expected.exactOutput {
            if normalize(output) != normalize(exact) {
                failures.append(
                    RefineObjectiveFailure(
                        kind: .exactOutputMismatch,
                        message: "Output did not match exact expected string.",
                        severity: evalCase.severity
                    )
                )
            }
        }

        if let maxRatio = evalCase.expected.maxExpansionRatio, decision == .changed {
            if expansionRatio > maxRatio {
                failures.append(
                    RefineObjectiveFailure(
                        kind: .expansionExceeded,
                        message: String(format: "Expansion ratio %.2f exceeded %.2f.", expansionRatio, maxRatio),
                        severity: evalCase.severity
                    )
                )
            }
        }

        let driftAssessment = RefineEvalIndependentLanguageAssessor.isUnauthorizedDrift(
            input: input,
            output: output,
            expectedTag: evalCase.expected.expectedLanguage
        )
        let evaluatorDisagreement = record.languageDiagnostics?.generatedLanguageAssessment?.disagreesWithMarkers == true
        let requiresHumanReview = driftAssessment.assessment.confidence == .requiresReview
            || driftAssessment.assessment.confidence == .insufficient
            || evaluatorDisagreement

        if driftAssessment.drift && !requiresHumanReview {
            failures.append(
                RefineObjectiveFailure(
                    kind: .languageDrift,
                    message: "Output language drifted from expected/input language.",
                    severity: .critical
                )
            )
        } else if driftAssessment.drift && requiresHumanReview {
            semanticReasons.append("Language drift suspected but confidence insufficient; requires human review.")
        }
        if evaluatorDisagreement {
            semanticReasons.append("Independent evaluator disagrees with marker heuristic.")
        }

        let requiredTokens = evalCase.expected.mustPreserveTokens ?? []
        let missing = ProtectedTokenExtractor.missingTokens(input: input, output: output, required: requiredTokens)
        if !missing.isEmpty {
            failures.append(
                RefineObjectiveFailure(
                    kind: .protectedTokenMutation,
                    message: "Missing required tokens: \(missing.joined(separator: ", "))",
                    severity: .critical
                )
            )
        }

        let mutated = ProtectedTokenExtractor.mutatedInputTokens(input: input, output: output)
        if !mutated.isEmpty && decision == .changed {
            let critical = mutated.filter { $0.category != .number }
            if !critical.isEmpty {
                failures.append(
                    RefineObjectiveFailure(
                        kind: .protectedTokenMutation,
                        message: "Mutated protected tokens: \(critical.map(\.value).joined(separator: ", "))",
                        severity: .critical
                    )
                )
            }
        }

        if evalCase.scope == .selection {
            let request = evalCase.makeRefinementRequest()
            if decision == .changed && !request.isReplacementOnly(output) {
                failures.append(
                    RefineObjectiveFailure(
                        kind: .contextLeakage,
                        message: "Selection output appears to include surrounding context.",
                        severity: .critical
                    )
                )
            }
            if decision == .changed && !request.allowsChangedText(output) {
                failures.append(
                    RefineObjectiveFailure(
                        kind: .selectionScopeViolation,
                        message: "Selection replacement exceeded production size guard.",
                        severity: .high
                    )
                )
            }
        }

        if evalCase.expected.mustNotIntroduceInformation == true,
           decision == .changed,
           input.count <= 12,
           expansionRatio > 2.5
        {
            failures.append(
                RefineObjectiveFailure(
                    kind: .forbiddenContentIntroduced,
                    message: "Tiny/ambiguous input expanded substantially.",
                    severity: .critical
                )
            )
        }

        if let preferred = evalCase.expected.preferredAction {
            let actual: RefineEvalAction = decision == .noChange ? .noChange : .cleanup
            if preferred == .noChange && actual != .noChange {
                semanticReasons.append("Preferred action was noChange.")
            }
        }

        if evalCase.expected.semanticNotes != nil {
            semanticReasons.append(evalCase.expected.semanticNotes!)
        }

        if decision == .changed && evalCase.category.contains("already-good") {
            semanticReasons.append("Changed output on already-good note.")
        }

        if decision == .changed && (evalCase.category.contains("incomplete") || evalCase.category.contains("ambiguous")) {
            semanticReasons.append("Changed output on incomplete/ambiguous input.")
        }

        let requiresSemanticReview = !semanticReasons.isEmpty
            || failures.contains { $0.kind == .forbiddenContentIntroduced }
            || (evalCase.severity == .critical && decision == .changed && input.count <= 8)

        let languageBehavior = RefineEvalLanguageBehaviorMetrics.snapshot(evalCase: evalCase, record: record)

        return RefineEvalCaseScore(
            caseID: evalCase.id,
            runIndex: runIndex,
            objectiveFailures: failures,
            requiresSemanticReview: requiresSemanticReview,
            semanticReviewReasons: semanticReasons,
            requiresHumanReview: requiresHumanReview,
            evaluatorDisagreement: evaluatorDisagreement,
            languageBehavior: languageBehavior,
            passedObjectively: failures.isEmpty,
            inputLanguage: evalCase.primaryLanguageTag,
            outputLanguage: outputLanguage,
            expansionRatio: expansionRatio,
            latencyMs: record.latencyMs,
            decision: decision
        )
    }

    private static func normalize(_ text: String) -> String {
        ProtectedTokenExtractor.normalize(text)
    }
}

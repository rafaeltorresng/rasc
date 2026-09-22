import Foundation

struct RefineEvalLanguageAxisMetric: Codable, Sendable {
    var successCount: Int
    var failureCount: Int
    var requiresReviewCount: Int
    var rate: Double
}

struct RefineEvalDecomposedLanguageMetrics: Codable, Sendable {
    var inputLanguageResolution: RefineEvalLanguageAxisMetric
    var rawGenerationLanguageCorrect: RefineEvalLanguageAxisMetric
    var languageValidatorOutcome: RefineEvalLanguageAxisMetric
    var finalUserVisibleLanguageSafe: RefineEvalLanguageAxisMetric
    var technicalTermPreservation: RefineEvalLanguageAxisMetric
}

struct RefineEvalSafetyMetrics: Codable, Sendable {
    /// Final user-visible outputs that violate critical constraints.
    var userVisibleHarmfulEditRate: Double
    var userVisibleHarmfulEditCount: Int
    /// Bad model proposals rejected into noChange before reaching the user.
    var modelProposalFailureRate: Double
    var modelProposalFailureCount: Int
    var sampleCount: Int
}

struct RefineEvalLanguageBehaviorSnapshot: Codable, Sendable, Equatable {
    var inputLanguageResolved: Bool?
    var rawGenerationLanguageCorrect: Bool?
    var validatorCaughtGenerationFailure: Bool?
    var finalUserVisibleLanguageSafe: Bool?
    var technicalTermsPreserved: Bool?
    var generationFailureWithSafetySuccess: Bool
    var userVisibleCriticalLanguageFailure: Bool
}

enum RefineEvalLanguageBehaviorMetrics {
    static func snapshot(
        evalCase: RefineEvalCase,
        record: RefineEvalRunRecord
    ) -> RefineEvalLanguageBehaviorSnapshot? {
        guard let diagnostics = record.languageDiagnostics else { return nil }

        let generationFailed = diagnostics.generationLanguageCorrect == false
        let validatorCaught = diagnostics.postValidatorRejected == true
        let userVisibleUnsafe = diagnostics.userVisibleLanguageSafe == false
        let technicalPreserved = !hasProtectedTokenFailure(record: record, evalCase: evalCase)

        let resolverOK: Bool? = {
            guard let expected = evalCase.expected.expectedLanguage,
                  let resolved = diagnostics.resolvedLabel
            else { return nil }
            return normalize(resolved) == normalize(expected)
        }()

        return RefineEvalLanguageBehaviorSnapshot(
            inputLanguageResolved: resolverOK,
            rawGenerationLanguageCorrect: diagnostics.generationLanguageCorrect,
            validatorCaughtGenerationFailure: validatorCaught,
            finalUserVisibleLanguageSafe: diagnostics.userVisibleLanguageSafe,
            technicalTermsPreserved: technicalPreserved,
            generationFailureWithSafetySuccess: generationFailed && validatorCaught,
            userVisibleCriticalLanguageFailure: userVisibleUnsafe
        )
    }

    static func summarize(records: [RefineEvalRunRecord], cases: [RefineEvalCase]) -> (
        decomposed: RefineEvalDecomposedLanguageMetrics,
        safety: RefineEvalSafetyMetrics
    ) {
        let caseMap = Dictionary(uniqueKeysWithValues: cases.map { ($0.id, $0) })
        let runZero = records.filter { $0.runIndex == 0 }

        var resolverSuccess = 0
        var resolverFailure = 0
        var resolverReview = 0
        var generationSuccess = 0
        var generationFailure = 0
        var generationReview = 0
        var validatorSuccess = 0
        var validatorFailure = 0
        var validatorReview = 0
        var visibleSuccess = 0
        var visibleFailure = 0
        var visibleReview = 0
        var technicalSuccess = 0
        var technicalFailure = 0
        var technicalReview = 0
        var harmfulVisible = 0
        var proposalFailures = 0

        for record in runZero {
            guard let snapshot = snapshot(
                evalCase: caseMap[record.caseID] ?? RefineEvalCase(
                    id: record.caseID,
                    source: "unknown",
                    category: [],
                    tags: [],
                    input: record.input,
                    languagePolicy: RefineCorpusLanguagePolicy(mode: .matchNote),
                    expected: RefineEvalExpectation(),
                    severity: .low
                ),
                record: record
            ) else { continue }

            accumulate(snapshot.inputLanguageResolved, success: &resolverSuccess, failure: &resolverFailure, review: &resolverReview)
            accumulate(snapshot.rawGenerationLanguageCorrect, success: &generationSuccess, failure: &generationFailure, review: &generationReview)
            accumulate(
                snapshot.validatorCaughtGenerationFailure.map { !$0 } ?? snapshot.rawGenerationLanguageCorrect,
                success: &validatorSuccess,
                failure: &validatorFailure,
                review: &validatorReview
            )
            accumulate(snapshot.finalUserVisibleLanguageSafe, success: &visibleSuccess, failure: &visibleFailure, review: &visibleReview)
            accumulate(snapshot.technicalTermsPreserved, success: &technicalSuccess, failure: &technicalFailure, review: &technicalReview)

            if isUserVisibleHarmful(record: record, evalCase: caseMap[record.caseID], snapshot: snapshot) {
                harmfulVisible += 1
            }
            if snapshot.generationFailureWithSafetySuccess {
                proposalFailures += 1
            }
        }

        let sampleCount = runZero.count
        return (
            decomposed: RefineEvalDecomposedLanguageMetrics(
                inputLanguageResolution: axis(success: resolverSuccess, failure: resolverFailure, review: resolverReview),
                rawGenerationLanguageCorrect: axis(success: generationSuccess, failure: generationFailure, review: generationReview),
                languageValidatorOutcome: axis(success: validatorSuccess, failure: validatorFailure, review: validatorReview),
                finalUserVisibleLanguageSafe: axis(success: visibleSuccess, failure: visibleFailure, review: visibleReview),
                technicalTermPreservation: axis(success: technicalSuccess, failure: technicalFailure, review: technicalReview)
            ),
            safety: RefineEvalSafetyMetrics(
                userVisibleHarmfulEditRate: sampleCount == 0 ? 0 : Double(harmfulVisible) / Double(sampleCount),
                userVisibleHarmfulEditCount: harmfulVisible,
                modelProposalFailureRate: sampleCount == 0 ? 0 : Double(proposalFailures) / Double(sampleCount),
                modelProposalFailureCount: proposalFailures,
                sampleCount: sampleCount
            )
        )
    }

    static func isUserVisibleHarmful(
        record: RefineEvalRunRecord,
        evalCase: RefineEvalCase?,
        snapshot: RefineEvalLanguageBehaviorSnapshot
    ) -> Bool {
        guard record.decision == .changed else { return false }
        if snapshot.userVisibleCriticalLanguageFailure { return true }
        guard let evalCase else { return false }
        if record.productionRejection != nil { return false }
        if snapshot.userVisibleCriticalLanguageFailure { return true }
        if snapshot.technicalTermsPreserved == false { return true }
        if evalCase.expected.mustNotIntroduceInformation == true,
           Double((record.output ?? "").count) / Double(max(1, evalCase.input.count)) > 2.5,
           evalCase.input.count <= 12
        {
            return true
        }
        return false
    }

    private static func hasProtectedTokenFailure(record: RefineEvalRunRecord, evalCase: RefineEvalCase) -> Bool {
        guard let output = record.output else { return true }
        let missing = ProtectedTokenExtractor.missingTokens(
            input: evalCase.input,
            output: output,
            required: evalCase.expected.mustPreserveTokens ?? []
        )
        if !missing.isEmpty { return false }
        let mutated = ProtectedTokenExtractor.mutatedInputTokens(input: evalCase.input, output: output)
        return mutated.filter { $0.category != .number }.isEmpty
    }

    private static func accumulate(
        _ value: Bool?,
        success: inout Int,
        failure: inout Int,
        review: inout Int
    ) {
        switch value {
        case true: success += 1
        case false: failure += 1
        case nil: review += 1
        }
    }

    private static func axis(success: Int, failure: Int, review: Int) -> RefineEvalLanguageAxisMetric {
        let denom = success + failure
        return RefineEvalLanguageAxisMetric(
            successCount: success,
            failureCount: failure,
            requiresReviewCount: review,
            rate: denom == 0 ? 0 : Double(success) / Double(denom)
        )
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

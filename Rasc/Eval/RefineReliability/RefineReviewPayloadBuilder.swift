import Foundation

enum RefineProductJudgment: String, Codable, Sendable, CaseIterable {
    case outputAcceptable
    case productFailure
    case languageAmbiguous
    case `defer`
}

enum RefineBenchmarkJudgment: String, Codable, Sendable, CaseIterable {
    case benchmarkCorrect
    case benchmarkExpectationWrong
    case needsConstraintEdit
    case deferBenchmarkReview
}

struct RefineReviewCaseStatus: Codable, Equatable, Sendable {
    var productReviewed: Bool
    var benchmarkReviewed: Bool
    var fullyReviewed: Bool
    var deferred: Bool
    var productNotApplicable: Bool
}

struct RefineReviewStage1Payload: Codable, Equatable, Sendable {
    var input: String
    var selection: String?
    var surroundingContext: RefineSurroundingContext?
    var finalOutput: String?
    var finalDecision: String?
}

struct RefineReviewStage2Payload: Codable, Equatable, Sendable {
    var caseID: String
    var source: String
    var split: String?
    var categories: [String]
    var tags: [String]
    var severity: String
    var expectedLanguage: String?
    var languagePolicy: String?
    var preferredAction: String?
    var allowedActions: [String]
    var mustPreserveTokens: [String]
    var maxExpansionRatio: Double?
    var semanticNotes: String?
    var m12b001Output: String?
    var m12b001Decision: String?
    var resolvedLabel: String?
    var resolvedLocale: String?
    var resolverConfidence: String?
    var resolverReason: String?
    var independentAssessmentLabel: String?
    var independentAssessmentConfidence: String?
    var validatorRejected: Bool?
    var finalDecision: String?
    var rootCause: String?
    var rootCauseExplanation: String?
    var queueSources: [String]
}

struct RefineReviewCaseItem: Codable, Equatable, Sendable {
    var reviewOrder: Int
    var hasRefineOutput: Bool
    var stage1: RefineReviewStage1Payload?
    var stage2: RefineReviewStage2Payload
    var reviewStatus: RefineReviewCaseStatus
}

struct RefineReviewPayload: Codable, Equatable, Sendable {
    var schemaVersion: Int
    var queueMode: String
    var includeHoldout: Bool
    var shuffleSeed: String
    var items: [RefineReviewCaseItem]
    var adjudicationCount: Int
}

struct RefineReviewRunContext: Equatable, Sendable {
    var finalOutput: String?
    var finalDecision: String?
    var languageDiagnostics: RefineEvalLanguageDiagnostics?
}

enum RefineReviewPayloadBuilder {
    static let defaultShuffleSeed = "refine-priority-review-v1"

    static func stableShuffle(_ caseIDs: [String], seed: String = defaultShuffleSeed) -> [String] {
        caseIDs.sorted { hashScore(caseID: $0, seed: seed) < hashScore(caseID: $1, seed: seed) }
    }

    static func hasRefineOutput(context: RefineReviewRunContext) -> Bool {
        guard let output = context.finalOutput?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return false
        }
        return !output.isEmpty
    }

    static func buildStage1(
        evalCase: RefineEvalCase,
        context: RefineReviewRunContext
    ) -> RefineReviewStage1Payload? {
        guard hasRefineOutput(context: context) else { return nil }
        return RefineReviewStage1Payload(
            input: evalCase.input,
            selection: evalCase.selection,
            surroundingContext: evalCase.surroundingContext,
            finalOutput: context.finalOutput,
            finalDecision: context.finalDecision
        )
    }

    static func buildStage2(
        evalCase: RefineEvalCase,
        split: String?,
        context: RefineReviewRunContext,
        queueSources: [String]
    ) -> RefineReviewStage2Payload {
        let expected = evalCase.expected
        let diagnostics = context.languageDiagnostics
        let assessment = diagnostics?.generatedLanguageAssessment
        return RefineReviewStage2Payload(
            caseID: evalCase.id,
            source: evalCase.source,
            split: split,
            categories: evalCase.category,
            tags: evalCase.tags,
            severity: evalCase.severity.rawValue,
            expectedLanguage: expected.expectedLanguage,
            languagePolicy: evalCase.languagePolicy.mode.rawValue,
            preferredAction: expected.preferredAction?.rawValue,
            allowedActions: expected.allowedActions?.map(\.rawValue) ?? [],
            mustPreserveTokens: expected.mustPreserveTokens ?? [],
            maxExpansionRatio: expected.maxExpansionRatio,
            semanticNotes: expected.semanticNotes,
            m12b001Output: context.finalOutput,
            m12b001Decision: context.finalDecision,
            resolvedLabel: diagnostics?.resolvedLabel,
            resolvedLocale: diagnostics?.resolvedLocale,
            resolverConfidence: diagnostics?.resolverConfidence,
            resolverReason: diagnostics?.resolverReason,
            independentAssessmentLabel: assessment?.label,
            independentAssessmentConfidence: assessment?.confidence.rawValue,
            validatorRejected: diagnostics?.postValidatorRejected,
            finalDecision: diagnostics?.finalDecision ?? context.finalDecision,
            rootCause: diagnostics?.rootCause?.rawValue,
            rootCauseExplanation: diagnostics?.rootCauseExplanation,
            queueSources: queueSources.sorted()
        )
    }

    static func reviewStatus(
        hasRefineOutput: Bool,
        adjudication: RefineAdjudicationRecordV2?
    ) -> RefineReviewCaseStatus {
        guard let adjudication else {
            return RefineReviewCaseStatus(
                productReviewed: false,
                benchmarkReviewed: false,
                fullyReviewed: false,
                deferred: false,
                productNotApplicable: !hasRefineOutput
            )
        }
        let productReviewed = adjudication.productReviewedAt != nil
        let benchmarkReviewed = adjudication.benchmarkReviewedAt != nil
        let deferred = adjudication.productJudgment == .defer
            || adjudication.benchmarkJudgment == .deferBenchmarkReview
        let fullyReviewed = (hasRefineOutput ? productReviewed : true) && benchmarkReviewed
        return RefineReviewCaseStatus(
            productReviewed: productReviewed,
            benchmarkReviewed: benchmarkReviewed,
            fullyReviewed: fullyReviewed,
            deferred: deferred,
            productNotApplicable: !hasRefineOutput
        )
    }

    static func hashScore(caseID: String, seed: String) -> UInt64 {
        var hash: UInt64 = 5381
        for byte in (seed + ":" + caseID).utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt64(byte)
        }
        return hash
    }
}

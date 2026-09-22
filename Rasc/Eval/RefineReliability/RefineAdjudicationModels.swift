import Foundation

enum RefineAdjudicationVerdict: String, Codable, Sendable, CaseIterable {
    case productFailure
    case outputAcceptable
    case benchmarkExpectationWrong
    case languageAmbiguous
    case needsConstraintEdit
    case `defer`
}

enum RefineProductFailureLabel: String, Codable, Sendable, CaseIterable {
    case wrongLanguage
    case inventedInformation
    case unnecessaryEdit
    case meaningChanged
    case excessiveExpansion
    case protectedTokenMutation
    case selectionLeak
    case styleVoiceDamage
    case other
}

enum RefineMaintainerReviewStatus: String, Codable, Sendable, CaseIterable {
    case unreviewed
    case approved
    case corrected
    case deferred
}

struct RefineConstraintCorrection: Codable, Equatable, Sendable {
    var expectedLanguage: String?
    var preferredAction: String?
    var allowedActions: [String]?
    var mustPreserveTokens: [String]?
    var maxExpansionRatio: Double?
    var semanticNotes: String?
    var severity: String?
}

struct RefineAdjudicationRecordV2: Codable, Equatable, Sendable, Identifiable {
    var id: String { "\(caseID)-\(reviewedAt)" }
    var schemaVersion: Int
    var caseID: String
    var reviewedAt: String
    var productJudgment: RefineProductJudgment?
    var productFailureLabels: [RefineProductFailureLabel]?
    var productNote: String?
    var productReviewedAt: String?
    var benchmarkJudgment: RefineBenchmarkJudgment?
    var benchmarkNote: String?
    var constraintCorrection: RefineConstraintCorrection?
    var benchmarkReviewedAt: String?
    var queueSource: String?
    var reviewer: String

    init(
        schemaVersion: Int = 2,
        caseID: String,
        reviewedAt: String = ISO8601DateFormatter().string(from: Date()),
        productJudgment: RefineProductJudgment? = nil,
        productFailureLabels: [RefineProductFailureLabel]? = nil,
        productNote: String? = nil,
        productReviewedAt: String? = nil,
        benchmarkJudgment: RefineBenchmarkJudgment? = nil,
        benchmarkNote: String? = nil,
        constraintCorrection: RefineConstraintCorrection? = nil,
        benchmarkReviewedAt: String? = nil,
        queueSource: String? = nil,
        reviewer: String = "maintainer"
    ) {
        self.schemaVersion = schemaVersion
        self.caseID = caseID
        self.reviewedAt = reviewedAt
        self.productJudgment = productJudgment
        self.productFailureLabels = productFailureLabels
        self.productNote = productNote
        self.productReviewedAt = productReviewedAt
        self.benchmarkJudgment = benchmarkJudgment
        self.benchmarkNote = benchmarkNote
        self.constraintCorrection = constraintCorrection
        self.benchmarkReviewedAt = benchmarkReviewedAt
        self.queueSource = queueSource
        self.reviewer = reviewer
    }
}

struct RefineAdjudicationRecord: Codable, Equatable, Sendable, Identifiable {
    var id: String { "\(caseID)-\(reviewedAt)" }
    var caseID: String
    var reviewedAt: String
    var verdict: RefineAdjudicationVerdict
    var productFailureLabels: [RefineProductFailureLabel]?
    var note: String?
    var constraintCorrection: RefineConstraintCorrection?
    var queueSource: String?
    var reviewer: String

    init(
        caseID: String,
        reviewedAt: String = ISO8601DateFormatter().string(from: Date()),
        verdict: RefineAdjudicationVerdict,
        productFailureLabels: [RefineProductFailureLabel]? = nil,
        note: String? = nil,
        constraintCorrection: RefineConstraintCorrection? = nil,
        queueSource: String? = nil,
        reviewer: String = "maintainer"
    ) {
        self.caseID = caseID
        self.reviewedAt = reviewedAt
        self.verdict = verdict
        self.productFailureLabels = productFailureLabels
        self.note = note
        self.constraintCorrection = constraintCorrection
        self.queueSource = queueSource
        self.reviewer = reviewer
    }
}

struct RefinePriorityQueueManifest: Codable, Sendable {
    var version: Int
    var generatedAt: String
    var excludesHoldout: Bool
    var caseIDs: [String]
    var sourcesByCaseID: [String: [String]]
    var overlapStats: RefinePriorityQueueOverlapStats
    var reviewQueue75Status: RefineReviewQueueStatusSummary
}

struct RefinePriorityQueueOverlapStats: Codable, Sendable {
    var totalUniqueCases: Int
    var sourceCounts: [String: Int]
    var multiSourceCases: Int
}

struct RefineReviewQueueStatusSummary: Codable, Sendable {
    var totalCases: Int
    var unreviewed: Int
    var approved: Int
    var corrected: Int
    var deferred: Int
    var productReviewed: Int
    var benchmarkReviewed: Int
    var fullyReviewed: Int
    var agentGeneratedMaintainerUnapproved: Bool
}

struct RefineCorpusChangelogEntry: Codable, Sendable {
    var caseID: String
    var adjudicationReviewedAt: String
    var verdict: String
    var note: String?
    var changes: [String]
}

struct RefineCorpusApplyResult: Codable, Sendable {
    var sourceCorpusVersion: String
    var targetCorpusVersion: String
    var appliedCaseCount: Int
    var changelog: [RefineCorpusChangelogEntry]
    var outputPath: String
}

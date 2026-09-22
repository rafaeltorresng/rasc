import Foundation

enum RefineSemanticDimension: String, Codable, Sendable, CaseIterable {
    case semanticFidelity
    case inventedInformation
    case minimality
    case usefulness
    case voicePreservation
    case appropriateNoChange
}

struct RefineSemanticScore: Codable, Sendable {
    var dimension: RefineSemanticDimension
    var score: Double
    var rationale: String
}

struct RefineSemanticJudgement: Codable, Sendable {
    var caseID: String
    var scores: [RefineSemanticScore]
    var overallPass: Bool?
    var judgeIdentifier: String
}

/// Development-only abstraction for optional semantic judging in M12B+.
/// M12A ships with a no-op judge so the harness works offline with zero cloud dependency.
protocol RefineSemanticJudge: Sendable {
    var identifier: String { get }

    func judge(
        evalCase: RefineEvalCase,
        input: String,
        output: String,
        decision: RefinementDecision
    ) async -> RefineSemanticJudgement?
}

struct NoOpRefineSemanticJudge: RefineSemanticJudge {
    let identifier = "noop"

    func judge(
        evalCase _: RefineEvalCase,
        input _: String,
        output _: String,
        decision _: RefinementDecision
    ) async -> RefineSemanticJudgement? {
        nil
    }
}

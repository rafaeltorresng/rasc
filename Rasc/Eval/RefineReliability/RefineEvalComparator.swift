import Foundation

struct RefineEvalComparisonCaseDelta: Codable, Sendable {
    var caseID: String
    var baselinePassed: Bool
    var candidatePassed: Bool
    var baselineFailures: [RefineObjectiveFailureKind]
    var candidateFailures: [RefineObjectiveFailureKind]
    var classification: RefineEvalComparisonClassification
}

enum RefineEvalComparisonClassification: String, Codable, Sendable {
    case improvement
    case regression
    case criticalRegression
    case unchanged
}

struct RefineEvalComparisonReport: Codable, Sendable {
    var baselineSummaryPath: String
    var candidateSummaryPath: String
    var improvements: [String]
    var regressions: [String]
    var criticalRegressions: [String]
    var unchanged: [String]
    var categoryChanges: [String: RefineEvalBucketDelta]
    var languageChanges: [String: RefineEvalBucketDelta]
    var latencyDeltaMsP50: Double
    var latencyDeltaMsP95: Double
    var caseDeltas: [RefineEvalComparisonCaseDelta]
}

struct RefineEvalBucketDelta: Codable, Sendable {
    var baselinePassRate: Double
    var candidatePassRate: Double
    var delta: Double
}

enum RefineEvalComparator {
    static func compare(
        baseline: RefineEvalAggregateReport,
        candidate: RefineEvalAggregateReport,
        baselineSummaryPath: String,
        candidateSummaryPath: String
    ) -> RefineEvalComparisonReport {
        let baselineScores = casePassMap(from: baseline)
        let candidateScores = casePassMap(from: candidate)
        let allCaseIDs = Set(baselineScores.keys).union(candidateScores.keys).sorted()

        var improvements: [String] = []
        var regressions: [String] = []
        var criticalRegressions: [String] = []
        var unchanged: [String] = []
        var deltas: [RefineEvalComparisonCaseDelta] = []

        for caseID in allCaseIDs {
            let base = baselineScores[caseID] ?? (false, [])
            let cand = candidateScores[caseID] ?? (false, [])
            let classification: RefineEvalComparisonClassification
            if base.0 == cand.0 {
                classification = .unchanged
                unchanged.append(caseID)
            } else if cand.0 && !base.0 {
                classification = .improvement
                improvements.append(caseID)
            } else {
                let critical = cand.1.contains { failure in
                    [.languageDrift, .protectedTokenMutation, .contextLeakage, .forbiddenContentIntroduced].contains(failure)
                }
                classification = critical ? .criticalRegression : .regression
                if critical {
                    criticalRegressions.append(caseID)
                } else {
                    regressions.append(caseID)
                }
            }
            deltas.append(
                RefineEvalComparisonCaseDelta(
                    caseID: caseID,
                    baselinePassed: base.0,
                    candidatePassed: cand.0,
                    baselineFailures: base.1,
                    candidateFailures: cand.1,
                    classification: classification
                )
            )
        }

        return RefineEvalComparisonReport(
            baselineSummaryPath: baselineSummaryPath,
            candidateSummaryPath: candidateSummaryPath,
            improvements: improvements,
            regressions: regressions,
            criticalRegressions: criticalRegressions,
            unchanged: unchanged,
            categoryChanges: bucketDelta(
                baseline.breakdowns.byCategory,
                candidate.breakdowns.byCategory
            ),
            languageChanges: bucketDelta(
                baseline.breakdowns.byLanguage,
                candidate.breakdowns.byLanguage
            ),
            latencyDeltaMsP50: candidate.latency.p50Ms - baseline.latency.p50Ms,
            latencyDeltaMsP95: candidate.latency.p95Ms - baseline.latency.p95Ms,
            caseDeltas: deltas
        )
    }

    static func writeComparison(_ report: RefineEvalComparisonReport, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(report).write(to: url)
        var md = """
        # Refine Eval Comparison

        - Improvements: \(report.improvements.count)
        - Regressions: \(report.regressions.count)
        - Critical regressions: \(report.criticalRegressions.count)
        - Unchanged: \(report.unchanged.count)
        - Δ latency p50: \(String(format: "%.0f", report.latencyDeltaMsP50)) ms
        - Δ latency p95: \(String(format: "%.0f", report.latencyDeltaMsP95)) ms

        ## Critical regressions
        """
        if report.criticalRegressions.isEmpty {
            md += "\n- None\n"
        } else {
            for id in report.criticalRegressions {
                md += "\n- \(id)"
            }
        }
        try md.write(to: url.deletingPathExtension().appendingPathExtension("md"), atomically: true, encoding: .utf8)
    }

    static func compareBundles(
        baseline: RefineEvalRunBundle,
        candidate: RefineEvalRunBundle,
        baselinePath: String,
        candidatePath: String
    ) -> RefineEvalComparisonReport {
        let baselineAggregate = RefineEvalReportGenerator.generate(bundle: baseline, cases: [])
        let candidateAggregate = RefineEvalReportGenerator.generate(bundle: candidate, cases: [])
        var report = compare(
            baseline: baselineAggregate,
            candidate: candidateAggregate,
            baselineSummaryPath: baselinePath,
            candidateSummaryPath: candidatePath
        )
        report = mergeCaseDeltas(
            report: report,
            baselineScores: baseline.scores,
            candidateScores: candidate.scores
        )
        return report
    }

    private static func mergeCaseDeltas(
        report: RefineEvalComparisonReport,
        baselineScores: [RefineEvalCaseScore],
        candidateScores: [RefineEvalCaseScore]
    ) -> RefineEvalComparisonReport {
        let baselineMap = perCasePassMap(baselineScores)
        let candidateMap = perCasePassMap(candidateScores)
        let allIDs = Set(baselineMap.keys).union(candidateMap.keys).sorted()

        var improvements: [String] = []
        var regressions: [String] = []
        var criticalRegressions: [String] = []
        var unchanged: [String] = []
        var deltas: [RefineEvalComparisonCaseDelta] = []

        for caseID in allIDs {
            let base = baselineMap[caseID] ?? (false, [])
            let cand = candidateMap[caseID] ?? (false, [])
            let classification: RefineEvalComparisonClassification
            if base.0 == cand.0 {
                classification = .unchanged
                unchanged.append(caseID)
            } else if cand.0 && !base.0 {
                classification = .improvement
                improvements.append(caseID)
            } else {
                let critical = cand.1.contains { failure in
                    [.languageDrift, .protectedTokenMutation, .contextLeakage, .forbiddenContentIntroduced].contains(failure)
                }
                classification = critical ? .criticalRegression : .regression
                if critical {
                    criticalRegressions.append(caseID)
                } else {
                    regressions.append(caseID)
                }
            }
            deltas.append(
                RefineEvalComparisonCaseDelta(
                    caseID: caseID,
                    baselinePassed: base.0,
                    candidatePassed: cand.0,
                    baselineFailures: base.1,
                    candidateFailures: cand.1,
                    classification: classification
                )
            )
        }

        return RefineEvalComparisonReport(
            baselineSummaryPath: report.baselineSummaryPath,
            candidateSummaryPath: report.candidateSummaryPath,
            improvements: improvements,
            regressions: regressions,
            criticalRegressions: criticalRegressions,
            unchanged: unchanged,
            categoryChanges: report.categoryChanges,
            languageChanges: report.languageChanges,
            latencyDeltaMsP50: report.latencyDeltaMsP50,
            latencyDeltaMsP95: report.latencyDeltaMsP95,
            caseDeltas: deltas
        )
    }

    private static func perCasePassMap(
        _ scores: [RefineEvalCaseScore]
    ) -> [String: (Bool, [RefineObjectiveFailureKind])] {
        var map: [String: (Bool, [RefineObjectiveFailureKind])] = [:]
        for score in scores where score.runIndex == 0 {
            map[score.caseID] = (score.passedObjectively, score.objectiveFailures.map(\.kind))
        }
        return map
    }

    private static func casePassMap(
        from report: RefineEvalAggregateReport
    ) -> [String: (Bool, [RefineObjectiveFailureKind])] {
        var map: [String: (Bool, [RefineObjectiveFailureKind])] = [:]
        for failure in report.criticalFailures {
            let kinds = failure.failures.map(\.kind)
            map[failure.caseID] = (false, kinds)
        }
        return map
    }

    private static func bucketDelta(
        _ baseline: [String: RefineEvalBucketSummary],
        _ candidate: [String: RefineEvalBucketSummary]
    ) -> [String: RefineEvalBucketDelta] {
        let keys = Set(baseline.keys).union(candidate.keys)
        var result: [String: RefineEvalBucketDelta] = [:]
        for key in keys {
            let b = baseline[key]?.objectivePassRate ?? 0
            let c = candidate[key]?.objectivePassRate ?? 0
            result[key] = RefineEvalBucketDelta(baselinePassRate: b, candidatePassRate: c, delta: c - b)
        }
        return result
    }
}

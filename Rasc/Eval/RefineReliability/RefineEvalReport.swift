import Foundation

struct RefineEvalAggregateReport: Codable, Sendable {
    var environment: RefineEvalEnvironment
    var configuration: RefineEvalRunConfigurationSnapshot
    var overallPassRate: Double
    var objectivePassRate: Double
    var totalRuns: Int
    var totalCases: Int
    var criticalFailures: [RefineEvalFailureSummary]
    var behavior: RefineEvalBehaviorSummary
    var breakdowns: RefineEvalBreakdowns
    var latency: RefineEvalLatencySummary
    var limitations: [String]
    var languageMetrics: RefineEvalLanguageMetricsSummary?
    var decomposedLanguageMetrics: RefineEvalDecomposedLanguageMetrics?
    var safetyMetrics: RefineEvalSafetyMetrics?
    var stabilityDecomposition: RefineEvalStabilityDecomposition?
    var decisionMetrics: RefineEvalDecisionMetricsSummary?
    var protectedLiteralMetrics: RefineEvalProtectedLiteralMetrics?
    var reviewQueueStatus: String?
}

struct RefineEvalProtectedLiteralMetrics: Codable, Sendable {
    var coveredRuns: Int
    var rawProposalCorruptionCount: Int
    var guardRejectionCount: Int
    var proposalFailureWithSafetySuccessCount: Int
    var userVisibleProtectedLiteralCorruptionCount: Int
    var rejectionsByClass: [String: Int]
}

struct RefineEvalLanguageMetricsSummary: Codable, Sendable {
    var ptToEnDriftCases: Int
    var esToEnDriftCases: Int
    var enDriftCases: Int
    var mixedLanguageFailures: Int
    var resolverMistakes: Int
    var generationContractViolations: Int
    var validatorCatches: Int
    var validatorMisses: Int
    var falseRejections: Int
    var languageSafetyRejections: Int
    var generationLanguageCorrectRate: Double
    var userVisibleLanguageSafeRate: Double
    var rootCauseCounts: [String: Int]
}

struct RefineEvalStabilityDecomposition: Codable, Sendable {
    var exactOutputInstability: RefineEvalStabilityAxis
    var actionInstability: RefineEvalStabilityAxis
    var passFailInstability: RefineEvalStabilityAxis
    var languageResolutionInstability: RefineEvalStabilityAxis
    var languageOutputInstability: RefineEvalStabilityAxis
    var noChangeChangedFlapping: RefineEvalStabilityAxis?
}

struct RefineEvalStabilityAxis: Codable, Sendable {
    var unstableCases: Int
    var casesWithMultipleRuns: Int
    var unstableCaseIDs: [String]
}

struct RefineEvalFailureSummary: Codable, Sendable {
    var caseID: String
    var input: String
    var output: String?
    var failures: [RefineObjectiveFailure]
}

struct RefineEvalBehaviorSummary: Codable, Sendable {
    var unnecessaryEditCount: Int
    var excessiveExpansionCount: Int
    var noChangeCorrectCount: Int
    var noChangeIncorrectCount: Int
    var noChangeSpecifiedCount: Int
}

struct RefineEvalBreakdowns: Codable, Sendable {
    var byCategory: [String: RefineEvalBucketSummary]
    var byLanguage: [String: RefineEvalBucketSummary]
    var byInputLength: [String: RefineEvalBucketSummary]
    var byScope: [String: RefineEvalBucketSummary]
    var stability: RefineEvalStabilitySummary?
}

struct RefineEvalBucketSummary: Codable, Sendable {
    var runs: Int
    var objectivePassRate: Double
    var criticalFailures: Int
}

struct RefineEvalStabilitySummary: Codable, Sendable {
    var casesWithMultipleRuns: Int
    var stableCases: Int
    var unstableCases: Int
    var unstableCaseIDs: [String]
}

struct RefineEvalLatencySummary: Codable, Sendable {
    var p50Ms: Double
    var p95Ms: Double
    var sampleCount: Int
}

struct RefineEvalDecisionMetricsSummary: Codable, Sendable {
    var overall: RefineEvalDecisionBucketMetrics
    var byInputLength: [String: RefineEvalDecisionBucketMetrics]
    var tinyAmbiguous: RefineEvalDecisionBucketMetrics
    var alreadyGood: RefineEvalDecisionBucketMetrics
    var clearlyRefinableTelegraphic: RefineEvalDecisionBucketMetrics
    var structuralList: RefineEvalDecisionBucketMetrics
}

struct RefineEvalDecisionBucketMetrics: Codable, Sendable {
    var runCount: Int
    var caseCount: Int
    var changedCount: Int
    var changedRate: Double
    var noChangeCount: Int
    var noChangeRate: Double
    var objectivePassCount: Int
    var objectivePassRate: Double
    var harmfulEditCount: Int
    var harmfulEditRate: Double
    var excessiveExpansionCount: Int
    var inventedInformationIndicatorCount: Int
    var wrongLanguageChangedCount: Int
    var appropriateNoChangeCount: Int
    var appropriateNoChangeRate: Double
    var usefulChangedCount: Int
    var usefulChangedRate: Double
    var unnecessaryEditCount: Int
    var overAbstentionEligibleCount: Int
    var overAbstentionCount: Int
    var overAbstentionRate: Double
    var casesWithMultipleRuns: Int
    var actionFlappingCaseCount: Int
    var passFailFlappingCaseCount: Int
}

enum RefineEvalReportGenerator {
    static func generate(bundle: RefineEvalRunBundle, cases: [RefineEvalCase]) -> RefineEvalAggregateReport {
        let caseMap = Dictionary(uniqueKeysWithValues: cases.map { ($0.id, $0) })
        let totalRuns = bundle.scores.count
        let objectivePasses = bundle.scores.filter(\.passedObjectively).count
        let overallPasses = bundle.scores.filter { $0.passedObjectively && !$0.requiresSemanticReview }.count

        let criticalFailures = bundle.scores.compactMap { score -> RefineEvalFailureSummary? in
            let critical = score.objectiveFailures.filter { $0.severity == .critical }
            guard !critical.isEmpty else { return nil }
            let record = bundle.records.first { $0.caseID == score.caseID && $0.runIndex == score.runIndex }
            return RefineEvalFailureSummary(
                caseID: score.caseID,
                input: caseMap[score.caseID]?.input ?? record?.input ?? "",
                output: record?.output,
                failures: critical
            )
        }
        .sorted { $0.caseID < $1.caseID }

        let behavior = summarizeBehavior(bundle: bundle, caseMap: caseMap)
        let breakdowns = summarizeBreakdowns(bundle: bundle, caseMap: caseMap)
        let latency = summarizeLatency(bundle.records)
        let languageBehavior = RefineEvalLanguageBehaviorMetrics.summarize(
            records: bundle.records,
            cases: Array(caseMap.values)
        )
        let decisionMetrics = summarizeDecisionMetrics(bundle: bundle, caseMap: caseMap)
        let protectedLiteralMetrics = summarizeProtectedLiteralMetrics(records: bundle.records)

        return RefineEvalAggregateReport(
            environment: bundle.environment,
            configuration: bundle.configuration,
            overallPassRate: totalRuns == 0 ? 0 : Double(overallPasses) / Double(totalRuns),
            objectivePassRate: totalRuns == 0 ? 0 : Double(objectivePasses) / Double(totalRuns),
            totalRuns: totalRuns,
            totalCases: Set(bundle.scores.map(\.caseID)).count,
            criticalFailures: criticalFailures,
            behavior: behavior,
            breakdowns: breakdowns,
            latency: latency,
            limitations: defaultLimitations(),
            languageMetrics: summarizeLanguageMetrics(bundle: bundle, caseMap: caseMap),
            decomposedLanguageMetrics: languageBehavior.decomposed,
            safetyMetrics: languageBehavior.safety,
            stabilityDecomposition: summarizeStabilityDecomposition(bundle: bundle, records: bundle.records),
            decisionMetrics: decisionMetrics,
            protectedLiteralMetrics: protectedLiteralMetrics,
            reviewQueueStatus: "75-case review queue remains maintainer-unapproved; see Evals/Refine/review-queue.md"
        )
    }

    static func writeReports(
        bundle: RefineEvalRunBundle,
        aggregate: RefineEvalAggregateReport,
        to directory: URL
    ) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(bundle).write(to: directory.appendingPathComponent("results.json"))
        try encoder.encode(aggregate).write(to: directory.appendingPathComponent("summary.json"))
        try writeLanguageDiagnostics(bundle.records, to: directory.appendingPathComponent("language-diagnostics.jsonl"))
        try markdownSummary(aggregate, bundle: bundle).write(
            to: directory.appendingPathComponent("summary.md"),
            atomically: true,
            encoding: .utf8
        )
    }

    private static func writeLanguageDiagnostics(_ records: [RefineEvalRunRecord], to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var lines: [String] = []
        for record in records {
            guard let diagnostics = record.languageDiagnostics else { continue }
            struct Row: Codable {
                var caseID: String
                var runIndex: Int
                var diagnostics: RefineEvalLanguageDiagnostics
            }
            let row = Row(caseID: record.caseID, runIndex: record.runIndex, diagnostics: diagnostics)
            let data = try encoder.encode(row)
            lines.append(String(decoding: data, as: UTF8.self))
        }
        try lines.joined(separator: "\n").appending("\n").write(to: url, atomically: true, encoding: .utf8)
    }

    private static func summarizeBehavior(
        bundle: RefineEvalRunBundle,
        caseMap: [String: RefineEvalCase]
    ) -> RefineEvalBehaviorSummary {
        var unnecessary = 0
        var excessive = 0
        var noChangeCorrect = 0
        var noChangeIncorrect = 0
        var noChangeSpecified = 0

        for score in bundle.scores {
            guard let evalCase = caseMap[score.caseID] else { continue }
            if evalCase.expected.expectsNoChange == true {
                noChangeSpecified += 1
                if score.decision == .noChange {
                    noChangeCorrect += 1
                } else {
                    noChangeIncorrect += 1
                }
            }
            if evalCase.category.contains("already-good"), score.decision == .changed {
                unnecessary += 1
            }
            if score.objectiveFailures.contains(where: { $0.kind == .expansionExceeded }) {
                excessive += 1
            }
        }

        return RefineEvalBehaviorSummary(
            unnecessaryEditCount: unnecessary,
            excessiveExpansionCount: excessive,
            noChangeCorrectCount: noChangeCorrect,
            noChangeIncorrectCount: noChangeIncorrect,
            noChangeSpecifiedCount: noChangeSpecified
        )
    }

    private static func summarizeBreakdowns(
        bundle: RefineEvalRunBundle,
        caseMap: [String: RefineEvalCase]
    ) -> RefineEvalBreakdowns {
        var byCategory: [String: [RefineEvalCaseScore]] = [:]
        var byLanguage: [String: [RefineEvalCaseScore]] = [:]
        var byLength: [String: [RefineEvalCaseScore]] = [:]
        var byScope: [String: [RefineEvalCaseScore]] = [:]

        for score in bundle.scores {
            guard let evalCase = caseMap[score.caseID] else { continue }
            for category in evalCase.category {
                byCategory[category, default: []].append(score)
            }
            byLanguage[evalCase.primaryLanguageTag, default: []].append(score)
            byLength[evalCase.inputLengthBucket, default: []].append(score)
            byScope[evalCase.scope.rawValue, default: []].append(score)
        }

        let stability = summarizeStability(bundle.scores)

        return RefineEvalBreakdowns(
            byCategory: byCategory.mapValues(bucketSummary),
            byLanguage: byLanguage.mapValues(bucketSummary),
            byInputLength: byLength.mapValues(bucketSummary),
            byScope: byScope.mapValues(bucketSummary),
            stability: stability
        )
    }

    private static func bucketSummary(_ scores: [RefineEvalCaseScore]) -> RefineEvalBucketSummary {
        let passes = scores.filter(\.passedObjectively).count
        let critical = scores.reduce(0) { partial, score in
            partial + score.objectiveFailures.filter { $0.severity == .critical }.count
        }
        return RefineEvalBucketSummary(
            runs: scores.count,
            objectivePassRate: scores.isEmpty ? 0 : Double(passes) / Double(scores.count),
            criticalFailures: critical
        )
    }

    private static func summarizeLanguageMetrics(
        bundle: RefineEvalRunBundle,
        caseMap: [String: RefineEvalCase]
    ) -> RefineEvalLanguageMetricsSummary {
        var ptToEn = 0
        var esToEn = 0
        var enDrift = 0
        var mixedFailures = 0
        var resolverMistakes = 0
        var generationViolations = 0
        var validatorCatches = 0
        var validatorMisses = 0
        var falseRejections = 0
        var safetyRejections = 0
        var generationCorrect = 0
        var userVisibleSafe = 0
        var rootCauseCounts: [String: Int] = [:]
        var considered = 0

        for record in bundle.records where record.runIndex == 0 {
            guard let diagnostics = record.languageDiagnostics else { continue }
            considered += 1
            if diagnostics.generationLanguageCorrect == true { generationCorrect += 1 }
            if diagnostics.userVisibleLanguageSafe == true { userVisibleSafe += 1 }
            if diagnostics.rejectedIntoNoChange == true { safetyRejections += 1 }

            if let cause = diagnostics.rootCause {
                rootCauseCounts[cause.rawValue, default: 0] += 1
                switch cause {
                case .resolverFailure: resolverMistakes += 1
                case .generationIgnoredContract: generationViolations += 1
                case .validatorFalseNegative: validatorMisses += 1
                case .validatorFalsePositive: falseRejections += 1
                case .validatorCatch: validatorCatches += 1
                default: break
                }
            }

            let evalCase = caseMap[record.caseID]
            let expected = evalCase?.expected.expectedLanguage
            let drift = bundle.scores.contains {
                $0.caseID == record.caseID
                    && $0.runIndex == record.runIndex
                    && $0.objectiveFailures.contains { $0.kind == .languageDrift }
            }
            if drift {
                switch expected {
                case "pt": ptToEn += 1
                case "es": esToEn += 1
                case "en": enDrift += 1
                case "mixed": mixedFailures += 1
                default: break
                }
            }
        }

        return RefineEvalLanguageMetricsSummary(
            ptToEnDriftCases: ptToEn,
            esToEnDriftCases: esToEn,
            enDriftCases: enDrift,
            mixedLanguageFailures: mixedFailures,
            resolverMistakes: resolverMistakes,
            generationContractViolations: generationViolations,
            validatorCatches: validatorCatches,
            validatorMisses: validatorMisses,
            falseRejections: falseRejections,
            languageSafetyRejections: safetyRejections,
            generationLanguageCorrectRate: considered == 0 ? 0 : Double(generationCorrect) / Double(considered),
            userVisibleLanguageSafeRate: considered == 0 ? 0 : Double(userVisibleSafe) / Double(considered),
            rootCauseCounts: rootCauseCounts
        )
    }

    private static func summarizeStabilityDecomposition(
        bundle: RefineEvalRunBundle,
        records: [RefineEvalRunRecord]
    ) -> RefineEvalStabilityDecomposition? {
        let groupedRecords = Dictionary(grouping: records, by: \.caseID)
        let groupedScores = Dictionary(grouping: bundle.scores, by: \.caseID)
        let multiIDs = groupedRecords.filter { $0.value.count > 1 }.map(\.key).sorted()
        guard !multiIDs.isEmpty else { return nil }

        func axis(_ unstable: [String]) -> RefineEvalStabilityAxis {
            RefineEvalStabilityAxis(
                unstableCases: unstable.count,
                casesWithMultipleRuns: multiIDs.count,
                unstableCaseIDs: unstable.sorted()
            )
        }

        var exactOutput: [String] = []
        var action: [String] = []
        var passFail: [String] = []
        var resolution: [String] = []
        var languageOutput: [String] = []

        for caseID in multiIDs {
            let caseRecords = groupedRecords[caseID] ?? []
            let caseScores = groupedScores[caseID] ?? []

            if Set(caseRecords.map(\.output)).count > 1 {
                exactOutput.append(caseID)
            }
            if Set(caseRecords.compactMap(\.decision)).count > 1 {
                action.append(caseID)
            }
            if Set(caseScores.map(\.passedObjectively)).count > 1 {
                passFail.append(caseID)
            }
            if Set(caseRecords.compactMap { $0.languageDiagnostics?.resolvedLocale }).count > 1 {
                resolution.append(caseID)
            }
            if Set(caseRecords.compactMap { $0.languageDiagnostics?.generatedLanguageAssessment?.label }).count > 1 {
                languageOutput.append(caseID)
            }
        }

        return RefineEvalStabilityDecomposition(
            exactOutputInstability: axis(exactOutput),
            actionInstability: axis(action),
            passFailInstability: axis(passFail),
            languageResolutionInstability: axis(resolution),
            languageOutputInstability: axis(languageOutput),
            noChangeChangedFlapping: axis(action)
        )
    }

    private static func summarizeDecisionMetrics(
        bundle: RefineEvalRunBundle,
        caseMap: [String: RefineEvalCase]
    ) -> RefineEvalDecisionMetricsSummary {
        let allCaseIDs = Set(bundle.scores.map(\.caseID))
        let tinyAmbiguousIDs = Set(caseMap.values.filter(isTinyOrAmbiguous).map(\.id)).intersection(allCaseIDs)
        let alreadyGoodIDs = Set(caseMap.values.filter(isAlreadyGood).map(\.id)).intersection(allCaseIDs)
        let telegraphicIDs = Set(caseMap.values.filter { evalCase in
            hasCategory(evalCase, "telegraphic")
        }.map(\.id)).intersection(allCaseIDs)
        let structuralIDs = Set(caseMap.values.filter { evalCase in
            hasCategory(evalCase, "structural-cleanup")
                || hasCategory(evalCase, "tasks")
                || hasCategory(evalCase, "list")
                || hasCategory(evalCase, "structural")
        }.map(\.id)).intersection(allCaseIDs)

        var byLength: [String: RefineEvalDecisionBucketMetrics] = [:]
        for bucket in ["1", "2-3", "4-8", "9+"] {
            let ids = Set(caseMap.values.filter { $0.inputLengthBucket == bucket }.map(\.id)).intersection(allCaseIDs)
            byLength[bucket] = decisionBucketMetrics(bundle: bundle, caseMap: caseMap, caseIDs: ids)
        }

        return RefineEvalDecisionMetricsSummary(
            overall: decisionBucketMetrics(bundle: bundle, caseMap: caseMap, caseIDs: allCaseIDs),
            byInputLength: byLength,
            tinyAmbiguous: decisionBucketMetrics(bundle: bundle, caseMap: caseMap, caseIDs: tinyAmbiguousIDs),
            alreadyGood: decisionBucketMetrics(bundle: bundle, caseMap: caseMap, caseIDs: alreadyGoodIDs),
            clearlyRefinableTelegraphic: decisionBucketMetrics(bundle: bundle, caseMap: caseMap, caseIDs: telegraphicIDs),
            structuralList: decisionBucketMetrics(bundle: bundle, caseMap: caseMap, caseIDs: structuralIDs)
        )
    }

    private static func decisionBucketMetrics(
        bundle: RefineEvalRunBundle,
        caseMap: [String: RefineEvalCase],
        caseIDs: Set<String>
    ) -> RefineEvalDecisionBucketMetrics {
        let scores = bundle.scores.filter { caseIDs.contains($0.caseID) }
        let records = bundle.records.filter { caseIDs.contains($0.caseID) }
        let recordMap = Dictionary(uniqueKeysWithValues: records.map { ("\($0.caseID)#\($0.runIndex)", $0) })
        let changed = scores.filter { $0.decision == .changed }
        let noChange = scores.filter { $0.decision == .noChange }
        let objectivePasses = scores.filter(\.passedObjectively)
        let harmfulKinds: Set<RefineObjectiveFailureKind> = [
            .languageDrift,
            .protectedTokenMutation,
            .expansionExceeded,
            .selectionScopeViolation,
            .contextLeakage,
            .forbiddenContentIntroduced,
        ]

        var harmfulEditCount = 0
        var excessiveExpansionCount = 0
        var inventedInformationIndicatorCount = 0
        var wrongLanguageChangedCount = 0
        var appropriateNoChangeCount = 0
        var usefulChangedCount = 0
        var unnecessaryEditCount = 0
        var overAbstentionEligibleCount = 0
        var overAbstentionCount = 0

        for score in scores {
            guard let evalCase = caseMap[score.caseID] else { continue }
            let record = recordMap["\(score.caseID)#\(score.runIndex)"]
            let failureKinds = Set(score.objectiveFailures.map(\.kind))
            if score.decision == .changed {
                if !failureKinds.isDisjoint(with: harmfulKinds), record?.productionRejection == nil {
                    harmfulEditCount += 1
                }
                if failureKinds.contains(.expansionExceeded) {
                    excessiveExpansionCount += 1
                }
                if failureKinds.contains(.forbiddenContentIntroduced) {
                    inventedInformationIndicatorCount += 1
                }
                if failureKinds.contains(.languageDrift) {
                    wrongLanguageChangedCount += 1
                }
                if score.passedObjectively, record?.productionRejection == nil {
                    usefulChangedCount += 1
                }
                if isAlreadyGood(evalCase) {
                    unnecessaryEditCount += 1
                }
            }

            if score.decision == .noChange, allowsNoChange(evalCase.expected) {
                appropriateNoChangeCount += 1
            }

            if requiresUsefulChange(evalCase.expected) {
                overAbstentionEligibleCount += 1
                if score.decision == .noChange {
                    overAbstentionCount += 1
                }
            }
        }

        let groupedScores = Dictionary(grouping: scores, by: \.caseID)
        let multi = groupedScores.filter { $0.value.count > 1 }
        let actionFlapping = multi.values.filter { Set($0.compactMap(\.decision)).count > 1 }.count
        let passFailFlapping = multi.values.filter { Set($0.map(\.passedObjectively)).count > 1 }.count
        let runCount = scores.count
        let changedCount = changed.count
        let noChangeCount = noChange.count

        return RefineEvalDecisionBucketMetrics(
            runCount: runCount,
            caseCount: Set(scores.map(\.caseID)).count,
            changedCount: changedCount,
            changedRate: rate(changedCount, runCount),
            noChangeCount: noChangeCount,
            noChangeRate: rate(noChangeCount, runCount),
            objectivePassCount: objectivePasses.count,
            objectivePassRate: rate(objectivePasses.count, runCount),
            harmfulEditCount: harmfulEditCount,
            harmfulEditRate: rate(harmfulEditCount, runCount),
            excessiveExpansionCount: excessiveExpansionCount,
            inventedInformationIndicatorCount: inventedInformationIndicatorCount,
            wrongLanguageChangedCount: wrongLanguageChangedCount,
            appropriateNoChangeCount: appropriateNoChangeCount,
            appropriateNoChangeRate: rate(appropriateNoChangeCount, noChangeCount),
            usefulChangedCount: usefulChangedCount,
            usefulChangedRate: rate(usefulChangedCount, changedCount),
            unnecessaryEditCount: unnecessaryEditCount,
            overAbstentionEligibleCount: overAbstentionEligibleCount,
            overAbstentionCount: overAbstentionCount,
            overAbstentionRate: rate(overAbstentionCount, overAbstentionEligibleCount),
            casesWithMultipleRuns: multi.count,
            actionFlappingCaseCount: actionFlapping,
            passFailFlappingCaseCount: passFailFlapping
        )
    }

    private static func rate(_ numerator: Int, _ denominator: Int) -> Double {
        denominator == 0 ? 0 : Double(numerator) / Double(denominator)
    }

    private static func hasCategory(_ evalCase: RefineEvalCase, _ category: String) -> Bool {
        evalCase.category.contains { $0.caseInsensitiveCompare(category) == .orderedSame }
    }

    private static func isTinyOrAmbiguous(_ evalCase: RefineEvalCase) -> Bool {
        hasCategory(evalCase, "tiny")
            || hasCategory(evalCase, "ambiguous")
            || evalCase.tags.contains("tiny")
            || evalCase.tags.contains("ambiguous")
    }

    private static func isAlreadyGood(_ evalCase: RefineEvalCase) -> Bool {
        hasCategory(evalCase, "already-good") || hasCategory(evalCase, "alreadyGood")
    }

    private static func allowsNoChange(_ expectation: RefineEvalExpectation) -> Bool {
        expectation.expectsNoChange == true
            || expectation.preferredAction == .noChange
            || expectation.allowedActions?.contains(.noChange) == true
    }

    private static func requiresUsefulChange(_ expectation: RefineEvalExpectation) -> Bool {
        if expectation.allowedActions?.contains(.noChange) == true {
            return false
        }
        if let allowed = expectation.allowedActions {
            return allowed.contains(.cleanup) || allowed.contains(.structure)
        }
        return expectation.preferredAction == .cleanup || expectation.preferredAction == .structure
    }

    private static func summarizeStability(_ scores: [RefineEvalCaseScore]) -> RefineEvalStabilitySummary? {
        let grouped = Dictionary(grouping: scores, by: \.caseID)
        let multi = grouped.filter { $0.value.count > 1 }
        guard !multi.isEmpty else { return nil }

        var unstable: [String] = []
        for (caseID, caseScores) in multi {
            let passStates = Set(caseScores.map(\.passedObjectively))
            if passStates.count > 1 {
                unstable.append(caseID)
            }
        }

        return RefineEvalStabilitySummary(
            casesWithMultipleRuns: multi.count,
            stableCases: multi.count - unstable.count,
            unstableCases: unstable.count,
            unstableCaseIDs: unstable.sorted()
        )
    }

    private static func summarizeLatency(_ records: [RefineEvalRunRecord]) -> RefineEvalLatencySummary {
        let samples = records.filter { $0.skippedReason == nil }.map(\.latencyMs).sorted()
        guard !samples.isEmpty else {
            return RefineEvalLatencySummary(p50Ms: 0, p95Ms: 0, sampleCount: 0)
        }
        let p50 = percentile(samples, 0.5)
        let p95 = percentile(samples, 0.95)
        return RefineEvalLatencySummary(p50Ms: p50, p95Ms: p95, sampleCount: samples.count)
    }

    private static func summarizeProtectedLiteralMetrics(
        records: [RefineEvalRunRecord]
    ) -> RefineEvalProtectedLiteralMetrics {
        let covered = records.filter {
            !RefineProtectedLiteralValidator.extract(from: $0.input).isEmpty
                || !RefineMoneyLiteralValidator.extract(from: $0.input).isEmpty
                || !RefinePercentageLiteralValidator.extract(from: $0.input).isEmpty
                || !RefineTimeLiteralValidator.extract(from: $0.input).isEmpty
        }
        let rejections = records.filter {
            $0.protectedLiteralDiagnostics?.validatorRejected == true
        }
        let visibleCorruptions = records.filter { record in
            guard record.decision == .changed, let output = record.output else { return false }
            let exactViolation = RefineProtectedLiteralValidator.validate(
                source: record.input,
                proposal: output
            ).violation != nil
            let moneyViolation = RefineMoneyLiteralValidator.validate(
                source: record.input,
                proposal: output
            ).violation != nil
            let percentageViolation = RefinePercentageLiteralValidator.validate(
                source: record.input,
                proposal: output
            ).violation != nil
            let timeViolation = RefineTimeLiteralValidator.validate(
                source: record.input,
                proposal: output
            ).violation != nil
            return exactViolation || moneyViolation || percentageViolation || timeViolation
        }
        var byClass: [String: Int] = [:]
        for record in rejections {
            guard let literalClass = record.protectedLiteralDiagnostics?.literalClass else { continue }
            byClass[literalClass.rawValue, default: 0] += 1
        }
        return RefineEvalProtectedLiteralMetrics(
            coveredRuns: covered.count,
            rawProposalCorruptionCount: rejections.count,
            guardRejectionCount: rejections.count,
            proposalFailureWithSafetySuccessCount: rejections.filter { $0.decision == .noChange }.count,
            userVisibleProtectedLiteralCorruptionCount: visibleCorruptions.count,
            rejectionsByClass: byClass
        )
    }

    private static func percentile(_ sorted: [Double], _ p: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let index = Int((Double(sorted.count - 1) * p).rounded())
        return sorted[max(0, min(sorted.count - 1, index))]
    }

    private static func formatLanguageAxisMetric(_ title: String, metric: RefineEvalLanguageAxisMetric) -> String {
        String(
            format: "- %@: %.1f%% pass (%d ok / %d fail, %d requires review)",
            title,
            metric.rate * 100,
            metric.successCount,
            metric.failureCount,
            metric.requiresReviewCount
        )
    }

    private static func defaultLimitations() -> [String] {
        [
            "Deterministic scorers cannot fully judge semantic faithfulness or subtle invented context.",
            "Language detection is heuristic and may mislabel tiny/ambiguous inputs.",
            "Foundation Models availability and sampling are environment-dependent.",
            "Holdout cases should not inform M12B tuning decisions.",
        ]
    }

    private static func markdownSummary(
        _ aggregate: RefineEvalAggregateReport,
        bundle: RefineEvalRunBundle
    ) -> String {
        var lines: [String] = []
        lines.append("# Refine Reliability Baseline Report")
        lines.append("")
        lines.append("## Environment")
        lines.append("- Prompt: `\(aggregate.environment.promptVersion)`")
        lines.append("- Model: `\(aggregate.environment.modelIdentifier)`")
        lines.append("- Provider: `\(aggregate.environment.provider)`")
        lines.append("- macOS: `\(aggregate.environment.osVersion)`")
        lines.append("- Availability: `\(aggregate.environment.modelAvailability)`")
        lines.append("- Sampling: \(aggregate.environment.samplingConfiguration)")
        lines.append("")
        lines.append("## Summary")
        lines.append(String(format: "- Objective pass rate: **%.1f%%**", aggregate.objectivePassRate * 100))
        lines.append(String(format: "- Overall pass rate (objective + no semantic flags): **%.1f%%**", aggregate.overallPassRate * 100))
        lines.append("- Total runs: \(aggregate.totalRuns)")
        lines.append("- Cases: \(aggregate.totalCases)")
        lines.append("")
        lines.append("## Latency")
        lines.append(String(format: "- p50: %.0f ms", aggregate.latency.p50Ms))
        lines.append(String(format: "- p95: %.0f ms", aggregate.latency.p95Ms))
        lines.append("")
        lines.append("## Behavior")
        lines.append("- Unnecessary edits (already-good changed): \(aggregate.behavior.unnecessaryEditCount)")
        lines.append("- Excessive expansion failures: \(aggregate.behavior.excessiveExpansionCount)")
        lines.append("- Strict noChange correct: \(aggregate.behavior.noChangeCorrectCount)/\(aggregate.behavior.noChangeSpecifiedCount)")
        lines.append("")
        if let decision = aggregate.decisionMetrics {
            lines.append("## noChange and utility calibration")
            lines.append(decisionMetricLine("Overall", decision.overall))
            lines.append(decisionMetricLine("Tiny/ambiguous", decision.tinyAmbiguous))
            lines.append(decisionMetricLine("Already-good", decision.alreadyGood))
            lines.append(decisionMetricLine("Clearly-refinable telegraphic", decision.clearlyRefinableTelegraphic))
            lines.append(decisionMetricLine("Structural/list", decision.structuralList))
            lines.append("")
            lines.append("### Input length (whitespace-delimited tokens)")
            for bucket in ["1", "2-3", "4-8", "9+"] {
                if let metric = decision.byInputLength[bucket] {
                    lines.append(decisionMetricLine("\(bucket) tokens", metric))
                }
            }
            lines.append("")
            lines.append("overAbstentionRate counts noChange only where allowedActions excludes noChange and cleanup/structure is allowed, or where cleanup/structure is preferred without contrary allowedActions.")
            lines.append("")
        }
        if let stability = aggregate.breakdowns.stability {
            lines.append("## Stability (pass/fail flapping)")
            lines.append("- Cases with multiple runs: \(stability.casesWithMultipleRuns)")
            lines.append("- Stable: \(stability.stableCases)")
            lines.append("- Unstable: \(stability.unstableCases)")
            if !stability.unstableCaseIDs.isEmpty {
                lines.append("- Unstable case IDs: \(stability.unstableCaseIDs.joined(separator: ", "))")
            }
            lines.append("")
        }
        if let decomposition = aggregate.stabilityDecomposition {
            lines.append("## Stability decomposition")
            lines.append("- Exact-output instability: \(decomposition.exactOutputInstability.unstableCases)")
            lines.append("- Action instability (changed vs noChange): \(decomposition.actionInstability.unstableCases)")
            lines.append("- Pass/fail instability: \(decomposition.passFailInstability.unstableCases)")
            lines.append("- Language-resolution instability: \(decomposition.languageResolutionInstability.unstableCases)")
            lines.append("- Language-output instability: \(decomposition.languageOutputInstability.unstableCases)")
            if let flapping = decomposition.noChangeChangedFlapping {
                lines.append("- **noChange/changed flapping: \(flapping.unstableCases)/\(flapping.casesWithMultipleRuns)**")
                if !flapping.unstableCaseIDs.isEmpty {
                    lines.append("- Flapping case IDs: \(flapping.unstableCaseIDs.joined(separator: ", "))")
                }
            }
            lines.append("")
        }
        if let language = aggregate.languageMetrics {
            lines.append("## Language metrics")
            lines.append("- PT→EN drift cases: \(language.ptToEnDriftCases)")
            lines.append("- ES→EN drift cases: \(language.esToEnDriftCases)")
            lines.append("- EN drift cases: \(language.enDriftCases)")
            lines.append("- Mixed-language failures: \(language.mixedLanguageFailures)")
            lines.append("- Generation language correct rate: \(String(format: "%.1f%%", language.generationLanguageCorrectRate * 100))")
            lines.append("- User-visible language safe rate: \(String(format: "%.1f%%", language.userVisibleLanguageSafeRate * 100))")
            lines.append("- Validator catches: \(language.validatorCatches)")
            lines.append("- Validator misses: \(language.validatorMisses)")
            lines.append("- False rejections: \(language.falseRejections)")
            lines.append("- Language safety rejections (changed→noChange): \(language.languageSafetyRejections)")
            lines.append("")
        }
        if let decomposed = aggregate.decomposedLanguageMetrics {
            lines.append("## Decomposed language behavior")
            lines.append(formatLanguageAxisMetric("A. Input language resolution", metric: decomposed.inputLanguageResolution))
            lines.append(formatLanguageAxisMetric("B. Raw generation language correct", metric: decomposed.rawGenerationLanguageCorrect))
            lines.append(formatLanguageAxisMetric("C. Language validator outcome", metric: decomposed.languageValidatorOutcome))
            lines.append(formatLanguageAxisMetric("D. Final user-visible language safe", metric: decomposed.finalUserVisibleLanguageSafe))
            lines.append(formatLanguageAxisMetric("E. Technical/foreign-term preservation", metric: decomposed.technicalTermPreservation))
            lines.append("")
            lines.append("A wrong raw generation rejected into noChange counts as generation failure + safety success (not user-visible harm).")
            lines.append("")
        }
        if let safety = aggregate.safetyMetrics {
            lines.append("## Safety metrics")
            lines.append(String(format: "- User-visible harmful edit rate: **%.1f%%** (%d/%d)", safety.userVisibleHarmfulEditRate * 100, safety.userVisibleHarmfulEditCount, safety.sampleCount))
            lines.append(String(format: "- Model proposal failure rate (rejected to noChange): **%.1f%%** (%d/%d)", safety.modelProposalFailureRate * 100, safety.modelProposalFailureCount, safety.sampleCount))
            lines.append("- Harmful edits include unauthorized language change, invented information, meaning change, protected-token corruption, and selection leakage in final changed outputs.")
            lines.append("")
        }
        if let protected = aggregate.protectedLiteralMetrics {
            lines.append("## Exact protected-literal safety")
            lines.append("- Covered runs: \(protected.coveredRuns)")
            lines.append("- Raw proposal corruptions: \(protected.rawProposalCorruptionCount)")
            lines.append("- Guard rejections: \(protected.guardRejectionCount)")
            lines.append("- Proposal failure + final safety success: \(protected.proposalFailureWithSafetySuccessCount)")
            lines.append("- **userVisibleProtectedLiteralCorruptionCount: \(protected.userVisibleProtectedLiteralCorruptionCount)**")
            lines.append("- Rejections by class: \(protected.rejectionsByClass)")
            lines.append("")
        }
        if let review = aggregate.reviewQueueStatus {
            lines.append("## Review queue")
            lines.append("- \(review)")
            lines.append("")
        }
        lines.append("## Critical failures (top)")
        for failure in aggregate.criticalFailures.prefix(25) {
            lines.append("### \(failure.caseID)")
            lines.append("**Input:** \(failure.input)")
            if let output = failure.output {
                lines.append("**Output:** \(output)")
            }
            for item in failure.failures {
                lines.append("- [\(item.kind.rawValue)] \(item.message)")
            }
            lines.append("")
        }
        lines.append("## Limitations")
        for limitation in aggregate.limitations {
            lines.append("- \(limitation)")
        }
        lines.append("")
        lines.append("## Records")
        lines.append("- Full machine-readable output: `results.json`")
        lines.append("- Case scores included: \(bundle.scores.count)")
        return lines.joined(separator: "\n")
    }

    private static func decisionMetricLine(
        _ title: String,
        _ metric: RefineEvalDecisionBucketMetrics
    ) -> String {
        String(
            format: "- %@: %d runs; changed %d (%.1f%%); noChange %d (%.1f%%); objective pass %d (%.1f%%); harmful edits %d; expansion %d; invented-information indicators %d; wrong-language changed %d; appropriate noChange %d; useful changed %d; unnecessary edits %d; over-abstention %d/%d (%.1f%%); action flapping %d/%d cases",
            title,
            metric.runCount,
            metric.changedCount,
            metric.changedRate * 100,
            metric.noChangeCount,
            metric.noChangeRate * 100,
            metric.objectivePassCount,
            metric.objectivePassRate * 100,
            metric.harmfulEditCount,
            metric.excessiveExpansionCount,
            metric.inventedInformationIndicatorCount,
            metric.wrongLanguageChangedCount,
            metric.appropriateNoChangeCount,
            metric.usefulChangedCount,
            metric.unnecessaryEditCount,
            metric.overAbstentionCount,
            metric.overAbstentionEligibleCount,
            metric.overAbstentionRate * 100,
            metric.actionFlappingCaseCount,
            metric.casesWithMultipleRuns
        )
    }
}

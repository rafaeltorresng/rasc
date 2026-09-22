import Foundation
import Testing
@testable import Rasc

@Suite
struct RefineAdjudicationTests {
    private var corpusRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Evals/Refine", isDirectory: true)
    }

    @Test
    func adjudicationRecordRoundTripsThroughJSON() throws {
        let record = RefineAdjudicationRecord(
            caseID: "tiny-pt-001",
            reviewedAt: "2026-09-20T12:00:00Z",
            verdict: .productFailure,
            productFailureLabels: [.wrongLanguage],
            note: "PT became EN",
            queueSource: "priority"
        )
        let data = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(RefineAdjudicationRecord.self, from: data)
        #expect(decoded.caseID == "tiny-pt-001")
        #expect(decoded.verdict == .productFailure)
        #expect(decoded.productFailureLabels == [.wrongLanguage])
    }

    @Test
    func latestByCaseIDKeepsMostRecentAdjudication() {
        let records = [
            RefineAdjudicationRecord(caseID: "a", reviewedAt: "2026-01-01T00:00:00Z", verdict: .`defer`),
            RefineAdjudicationRecord(caseID: "a", reviewedAt: "2026-02-01T00:00:00Z", verdict: .outputAcceptable),
        ]
        let latest = RefineAdjudicationStore.latestByCaseID(records)
        #expect(latest["a"]?.verdict == .outputAcceptable)
    }

    @Test
    func priorityQueueDeduplicatesAndExcludesHoldoutByDefault() throws {
        let manifest = try RefinePriorityQueueBuilder.build(
            input: RefinePriorityQueueBuilder.BuildInput(
                corpusRoot: corpusRoot,
                m12b001DevResults: corpusRoot
                    .appendingPathComponent("experiments/M12B-001-language-contract/reports/dev/results.json"),
                rootCauseTableMarkdown: corpusRoot
                    .appendingPathComponent("experiments/M12B-002-language-diagnostics/m12b-001-root-cause-table.md"),
                includeHoldout: false
            )
        )
        #expect(manifest.excludesHoldout)
        #expect(manifest.caseIDs.count == Set(manifest.caseIDs).count)
        #expect(!manifest.caseIDs.isEmpty)

        let splits = try RefineEvalDatasetLoader.loadSplits(from: corpusRoot)
        for caseID in manifest.caseIDs {
            let split = splits.assignments[caseID]
            #expect(split != .holdout)
        }
    }

    @Test
    func holdoutCanBeIncludedWhenExplicitlyRequested() throws {
        let without = try RefinePriorityQueueBuilder.build(
            input: RefinePriorityQueueBuilder.BuildInput(
                corpusRoot: corpusRoot,
                m12b001DevResults: nil,
                rootCauseTableMarkdown: nil,
                includeHoldout: false
            )
        )
        let withHoldout = try RefinePriorityQueueBuilder.build(
            input: RefinePriorityQueueBuilder.BuildInput(
                corpusRoot: corpusRoot,
                m12b001DevResults: nil,
                rootCauseTableMarkdown: nil,
                includeHoldout: true
            )
        )
        #expect(withHoldout.caseIDs.count >= without.caseIDs.count)
    }

    @Test
    func corpusCorrectorWritesV2WithoutTouchingV1() throws {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("refine-adjudication-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        let source = corpusRoot.appendingPathComponent("corpus.v1.jsonl")
        let target = temp.appendingPathComponent("corpus.v1.jsonl")
        try FileManager.default.copyItem(at: source, to: target)

        let record = RefineAdjudicationRecordV2(
            caseID: "already-good-001",
            reviewedAt: "2026-09-20T12:00:00Z",
            benchmarkJudgment: .benchmarkExpectationWrong,
            constraintCorrection: RefineConstraintCorrection(expectedLanguage: "pt"),
            benchmarkReviewedAt: "2026-09-20T12:00:00Z"
        )
        try RefineAdjudicationStore.appendV2(record, to: temp)

        let result = try RefineCorpusCorrector.applyAcceptedCorrections(corpusRoot: temp)
        #expect(result.targetCorpusVersion == "v2")
        #expect(result.appliedCaseCount == 1)
        #expect(FileManager.default.fileExists(atPath: temp.appendingPathComponent("corpus.v2.jsonl").path))
        #expect(FileManager.default.fileExists(atPath: temp.appendingPathComponent("corpus.v2.changelog.json").path))

        let v1Before = try RefineEvalDatasetLoader.loadJSONL(target)
        let v1After = try RefineEvalDatasetLoader.loadJSONL(target)
        #expect(v1Before.first { $0.id == "already-good-001" }?.expected.expectedLanguage == "pt")
        #expect(v1After.first { $0.id == "already-good-001" }?.expected.expectedLanguage == "pt")
        let v2Cases = try RefineEvalDatasetLoader.loadJSONL(temp.appendingPathComponent("corpus.v2.jsonl"))
        let corrected = v2Cases.first { $0.id == "already-good-001" }
        #expect(corrected?.expected.expectedLanguage == "pt")
    }

    @Test
    func languageBehaviorSeparatesGenerationFailureFromSafetySuccess() {
        let evalCase = RefineEvalCase(
            id: "lang-test",
            source: "unit",
            category: [],
            tags: ["pt"],
            input: "sync amanhã",
            languagePolicy: RefineCorpusLanguagePolicy(mode: .matchNote),
            expected: RefineEvalExpectation(expectedLanguage: "pt"),
            severity: .critical
        )
        let record = RefineEvalRunRecord(
            caseID: "lang-test",
            runIndex: 0,
            input: "sync amanhã",
            output: "sync amanhã",
            decision: .noChange,
            kind: .alreadyGood,
            latencyMs: 1,
            providerError: nil,
            productionRejection: nil,
            skippedReason: nil,
            promptVersion: "refine-v2-language",
            modelIdentifier: "test",
            availability: "available",
            languageDiagnostics: RefineEvalLanguageDiagnostics(
                expectedLanguage: "pt",
                languagePolicy: "matchNote",
                resolvedLocale: "pt-BR",
                resolvedLabel: "portuguese",
                resolverConfidence: "high",
                resolverReason: "detected_from_note",
                rawGeneratedText: "Sync tomorrow",
                rawGeneratedDecision: "changed",
                generatedLanguageAssessment: nil,
                generationLanguageCorrect: false,
                userVisibleLanguageSafe: true,
                postValidatorEvaluated: true,
                postValidatorRejected: true,
                finalDecision: "noChange",
                rejectedIntoNoChange: true,
                decisionReason: "language_contract_violation_rejected_to_noChange",
                rootCause: .validatorCatch,
                rootCauseExplanation: "test"
            )
        )
        let snapshot = RefineEvalLanguageBehaviorMetrics.snapshot(evalCase: evalCase, record: record)
        #expect(snapshot?.generationFailureWithSafetySuccess == true)
        #expect(snapshot?.userVisibleCriticalLanguageFailure == false)
        #expect(RefineEvalLanguageBehaviorMetrics.isUserVisibleHarmful(record: record, evalCase: evalCase, snapshot: snapshot!) == false)
    }

    @Test
    func harmfulEditRateCountsVisibleChangedOutputsOnly() {
        let evalCase = RefineEvalCase(
            id: "harmful",
            source: "unit",
            category: [],
            tags: ["pt"],
            input: "reunião amanhã",
            languagePolicy: RefineCorpusLanguagePolicy(mode: .matchNote),
            expected: RefineEvalExpectation(expectedLanguage: "pt"),
            severity: .critical
        )
        let harmfulRecord = RefineEvalRunRecord(
            caseID: "harmful",
            runIndex: 0,
            input: evalCase.input,
            output: "Meeting tomorrow",
            decision: .changed,
            kind: .messyText,
            latencyMs: 1,
            providerError: nil,
            productionRejection: nil,
            skippedReason: nil,
            promptVersion: "refine-v2-language",
            modelIdentifier: "test",
            availability: "available",
            languageDiagnostics: RefineEvalLanguageDiagnostics(
                expectedLanguage: "pt",
                languagePolicy: "matchNote",
                resolvedLocale: "pt-BR",
                resolvedLabel: "portuguese",
                resolverConfidence: "high",
                resolverReason: "detected_from_note",
                rawGeneratedText: "Meeting tomorrow",
                rawGeneratedDecision: "changed",
                generatedLanguageAssessment: nil,
                generationLanguageCorrect: false,
                userVisibleLanguageSafe: false,
                postValidatorEvaluated: true,
                postValidatorRejected: false,
                finalDecision: "changed",
                rejectedIntoNoChange: false,
                decisionReason: "changed_passed_language_validation",
                rootCause: .validatorFalseNegative,
                rootCauseExplanation: "test"
            )
        )
        let summary = RefineEvalLanguageBehaviorMetrics.summarize(
            records: [harmfulRecord],
            cases: [evalCase]
        )
        #expect(summary.safety.userVisibleHarmfulEditCount == 1)
        #expect(summary.safety.userVisibleHarmfulEditRate == 1.0)
    }

    @Test
    func reviewQueue75StatusTracksUnreviewedByDefault() throws {
        let reviewQueue = try RefineEvalDatasetLoader.loadReviewQueue(from: corpusRoot)
        let summary = RefineAdjudicationStore.summarizeReviewQueue75(
            reviewQueueCaseIDs: reviewQueue.map(\.id),
            adjudications: [:]
        )
        #expect(summary.totalCases == 75)
        #expect(summary.unreviewed == 75)
        #expect(summary.productReviewed == 0)
        #expect(summary.benchmarkReviewed == 0)
        #expect(summary.agentGeneratedMaintainerUnapproved)
    }

    @Test
    func stage1PayloadOmitsExpectationAndDiagnosticFields() {
        let evalCase = RefineEvalCase(
            id: "blind-case",
            source: "unit",
            category: ["tiny"],
            tags: ["pt"],
            input: "sync amanhã",
            languagePolicy: RefineCorpusLanguagePolicy(mode: .matchNote),
            expected: RefineEvalExpectation(
                preferredAction: .noChange,
                expectedLanguage: "pt",
                mustPreserveTokens: ["sync"]
            ),
            severity: .critical
        )
        let context = RefineReviewRunContext(
            finalOutput: "Sync tomorrow",
            finalDecision: "changed",
            languageDiagnostics: RefineEvalLanguageDiagnostics(
                expectedLanguage: "pt",
                languagePolicy: "matchNote",
                resolvedLocale: "pt-BR",
                resolvedLabel: "portuguese",
                resolverConfidence: "high",
                resolverReason: "detected",
                rawGeneratedText: "Sync tomorrow",
                rawGeneratedDecision: "changed",
                generatedLanguageAssessment: nil,
                generationLanguageCorrect: false,
                userVisibleLanguageSafe: false,
                postValidatorEvaluated: true,
                postValidatorRejected: false,
                finalDecision: "changed",
                rejectedIntoNoChange: false,
                decisionReason: "changed",
                rootCause: .validatorFalseNegative,
                rootCauseExplanation: "secret"
            )
        )
        let stage1 = RefineReviewPayloadBuilder.buildStage1(evalCase: evalCase, context: context)
        let stage2 = RefineReviewPayloadBuilder.buildStage2(
            evalCase: evalCase,
            split: "dev",
            context: context,
            queueSources: ["validator_false_negative"]
        )
        let encoder = JSONEncoder()
        let stage1JSON = String(decoding: try! encoder.encode(stage1), as: UTF8.self)
        #expect(stage1JSON.contains("sync amanhã"))
        #expect(stage1JSON.contains("Sync tomorrow"))
        #expect(!stage1JSON.contains("expectedLanguage"))
        #expect(!stage1JSON.contains("validator_false_negative"))
        #expect(!stage1JSON.contains("resolverReason"))
        #expect(stage2.expectedLanguage == "pt")
        #expect(stage2.rootCause == "validatorFalseNegative")
        #expect(stage2.queueSources == ["validator_false_negative"])
    }

    @Test
    func stableShuffleIsDeterministicAndChangesPriorityOrder() {
        let ids = ["already-good-001", "tiny-pt-001", "es-003", "variant-pt-002"]
        let first = RefineReviewPayloadBuilder.stableShuffle(ids)
        let second = RefineReviewPayloadBuilder.stableShuffle(ids)
        let sorted = ids.sorted()
        #expect(first == second)
        #expect(first != sorted)
    }

    @Test
    func adjudicationV2RoundTripsAndMergesDimensionsIndependently() throws {
        let product = RefineAdjudicationRecordV2(
            caseID: "case-a",
            reviewedAt: "2026-09-20T10:00:00Z",
            productJudgment: .productFailure,
            productFailureLabels: [.wrongLanguage],
            productNote: "bad output",
            productReviewedAt: "2026-09-20T10:00:00Z"
        )
        let benchmark = RefineAdjudicationRecordV2(
            caseID: "case-a",
            reviewedAt: "2026-09-20T11:00:00Z",
            benchmarkJudgment: .benchmarkCorrect,
            benchmarkReviewedAt: "2026-09-20T11:00:00Z"
        )
        let merged = RefineAdjudicationStore.merge(existing: product, update: benchmark)
        let data = try JSONEncoder().encode(merged)
        let decoded = try JSONDecoder().decode(RefineAdjudicationRecordV2.self, from: data)
        #expect(decoded.productJudgment == .productFailure)
        #expect(decoded.benchmarkJudgment == .benchmarkCorrect)
        #expect(decoded.productFailureLabels == [.wrongLanguage])
    }

    @Test
    func corpusCorrectorAppliesV2BenchmarkCorrectionsOnly() throws {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("refine-adjudication-v2-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        let source = corpusRoot.appendingPathComponent("corpus.v1.jsonl")
        let target = temp.appendingPathComponent("corpus.v1.jsonl")
        try FileManager.default.copyItem(at: source, to: target)

        let record = RefineAdjudicationRecordV2(
            caseID: "already-good-001",
            reviewedAt: "2026-09-20T12:00:00Z",
            benchmarkJudgment: .benchmarkExpectationWrong,
            constraintCorrection: RefineConstraintCorrection(expectedLanguage: "mixed"),
            benchmarkReviewedAt: "2026-09-20T12:00:00Z"
        )
        try RefineAdjudicationStore.appendV2(record, to: temp)

        let result = try RefineCorpusCorrector.applyAcceptedCorrections(corpusRoot: temp)
        #expect(result.targetCorpusVersion == "v2")
        #expect(result.appliedCaseCount == 1)
        let v2Cases = try RefineEvalDatasetLoader.loadJSONL(temp.appendingPathComponent("corpus.v2.jsonl"))
        #expect(v2Cases.first { $0.id == "already-good-001" }?.expected.expectedLanguage == "mixed")
    }

    @Test
    func reviewStatusTracksProductAndBenchmarkIndependently() {
        let withProductOnly = RefineAdjudicationRecordV2(
            caseID: "x",
            reviewedAt: "2026-01-01T00:00:00Z",
            productJudgment: .outputAcceptable,
            productReviewedAt: "2026-01-01T00:00:00Z"
        )
        let status = RefineReviewPayloadBuilder.reviewStatus(hasRefineOutput: true, adjudication: withProductOnly)
        #expect(status.productReviewed)
        #expect(!status.benchmarkReviewed)
        #expect(!status.fullyReviewed)

        let corpusOnly = RefineReviewPayloadBuilder.reviewStatus(hasRefineOutput: false, adjudication: nil)
        #expect(corpusOnly.productNotApplicable)
    }

    @Test
    func casesWithoutRefineOutputSkipStage1() {
        let evalCase = RefineEvalCase(
            id: "corpus-only",
            source: "unit",
            category: [],
            tags: ["pt"],
            input: "draft",
            languagePolicy: RefineCorpusLanguagePolicy(mode: .matchNote),
            expected: RefineEvalExpectation(expectedLanguage: "pt"),
            severity: .low
        )
        let context = RefineReviewRunContext(finalOutput: nil, finalDecision: nil, languageDiagnostics: nil)
        #expect(RefineReviewPayloadBuilder.buildStage1(evalCase: evalCase, context: context) == nil)
        #expect(!RefineReviewPayloadBuilder.hasRefineOutput(context: context))
    }
}

import Foundation
import Testing
@testable import Rasc

@Suite
struct RefineReliabilityTests {
    private var corpusRoot: URL {
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let direct = cwd.appendingPathComponent("Evals/Refine", isDirectory: true)
        if FileManager.default.fileExists(atPath: direct.path) {
            return direct
        }
        // When tests run from DerivedData, locate repo root via SOURCE_ROOT env fallback.
        let sourceRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return sourceRoot.appendingPathComponent("Evals/Refine", isDirectory: true)
    }

    @Test
    func loadsVersionedJSONLCorpus() throws {
        let cases = try RefineEvalDatasetLoader.loadCorpus(from: corpusRoot)
        #expect(cases.count >= 280)
        #expect(cases.count <= 350)
        #expect(Set(cases.map(\.id)).count == cases.count)
    }

    @Test
    func splitAssignmentsAreStable() throws {
        let cases = try RefineEvalDatasetLoader.loadCorpus(from: corpusRoot)
        let manifest = try RefineEvalDatasetLoader.loadSplits(from: corpusRoot)
        for caseID in cases.map(\.id) {
            let fromCase = cases.first { $0.id == caseID }?.split
            let fromManifest = manifest.assignments[caseID]
            #expect(fromCase == fromManifest)
        }
    }

    @Test
    func reviewQueueIsCuratedNotFullCorpus() throws {
        let corpus = try RefineEvalDatasetLoader.loadCorpus(from: corpusRoot)
        let review = try RefineEvalDatasetLoader.loadReviewQueue(from: corpusRoot)
        #expect(review.count >= 50)
        #expect(review.count <= 75)
        #expect(review.count < corpus.count)
        #expect(review.allSatisfy { $0.inReviewQueue == true })
    }

    @Test
    func regressionCorpusIsPermanentAndSeparate() throws {
        let regression = try RefineEvalDatasetLoader.loadRegression(from: corpusRoot)
        #expect(!regression.isEmpty)
        #expect(regression.allSatisfy { $0.source == "product-regression" })
    }

    @Test
    func protectedTokenExtractorFindsURLsEmailsHandlesAndMoney() {
        let text = "Contact ana@acme.com @raf https://rasc.app R$ 12,50"
        let tokens = ProtectedTokenExtractor.extract(from: text)
        let values = Set(tokens.map(\.value))
        #expect(values.contains("ana@acme.com"))
        #expect(values.contains("@raf"))
        #expect(values.contains(where: { $0.contains("rasc.app") }))
        #expect(values.contains(where: { $0.contains("R$") }))
    }

    @Test
    func protectedTokenExtractorClassifiesHighConfidenceLiteralClassesWithoutOverlap() {
        let text = """
        https://rasc.app/a?x=1 ana@acme.com @rafa R$ 300 31/12/2026 15h30 42 50% \
        next_retry_at retryCount URLSession worker-retry-v2 abc123def v2.1.0 45ms worker.retry() \
        \"release-42\" 550e8400-e29b-41d4-a716-446655440000 a3f4c9d2
        """
        let tokens = ProtectedTokenExtractor.extract(from: text)
        let valuesByCategory = Dictionary(grouping: tokens, by: \.category)
            .mapValues { Set($0.map(\.value)) }

        #expect(valuesByCategory[.url] == ["https://rasc.app/a?x=1"])
        #expect(valuesByCategory[.email] == ["ana@acme.com"])
        #expect(valuesByCategory[.handle] == ["@rafa"])
        #expect(valuesByCategory[.money] == ["R$ 300"])
        #expect(valuesByCategory[.date] == ["31/12/2026"])
        #expect(valuesByCategory[.time] == ["15h30"])
        #expect(valuesByCategory[.number] == ["42"])
        #expect(valuesByCategory[.percentage] == ["50%"])
        #expect(valuesByCategory[.identifier] == [
            "next_retry_at", "retryCount", "URLSession", "worker-retry-v2", "v2.1.0", "45ms",
        ])
        #expect(valuesByCategory[.codeLike] == ["worker.retry()"])
        #expect(valuesByCategory[.quotedLiteral] == ["\"release-42\""])
        #expect(valuesByCategory[.opaqueID] == [
            "550e8400-e29b-41d4-a716-446655440000", "abc123def", "a3f4c9d2",
        ])
    }

    @Test(arguments: [
        "reunião amanhã com Ana sobre orçamento",
        "maybe retry?",
        "hello, world!",
        "falar com João sexta",
        "well-being matters",
    ])
    func protectedTokenExtractorDoesNotOverclassifyOrdinaryLanguage(input: String) {
        #expect(ProtectedTokenExtractor.extract(from: input).isEmpty)
    }

    @Test
    func protectedTokenPoliciesDistinguishExactAndSafeSemanticNormalization() {
        #expect(ProtectedTokenExtractor.preservationPolicy(for: .url) == .exact)
        #expect(ProtectedTokenExtractor.preservationPolicy(for: .identifier) == .exact)
        #expect(ProtectedTokenExtractor.preservationPolicy(for: .opaqueID) == .exact)
        #expect(ProtectedTokenExtractor.preservationPolicy(for: .money) == .semantic)
        #expect(ProtectedTokenExtractor.preservationPolicy(for: .time) == .semantic)
        #expect(ProtectedTokenExtractor.preservationPolicy(for: .percentage) == .semantic)

        let money = ProtectedToken(value: "R$ 300", category: .money, normalized: "r$ 300")
        let time = ProtectedToken(value: "15h", category: .time, normalized: "15h")
        let percentage = ProtectedToken(value: "50%", category: .percentage, normalized: "50%")
        let url = ProtectedToken(value: "https://rasc.app/a", category: .url, normalized: "https://rasc.app/a")
        let currencyMarker = ProtectedToken(value: "R$", category: .money, normalized: "r$")

        #expect(ProtectedTokenExtractor.preservationStatus(of: money, in: "Pagar R$300 amanhã") == .safelyNormalized)
        #expect(ProtectedTokenExtractor.preservationStatus(of: time, in: "Reunião às 15:00") == .safelyNormalized)
        #expect(ProtectedTokenExtractor.preservationStatus(of: percentage, in: "Concluído: 50 %") == .safelyNormalized)
        #expect(ProtectedTokenExtractor.preservationStatus(of: url, in: "Ver https://rasc.app/a.") == .preserved)
        #expect(ProtectedTokenExtractor.preservationStatus(of: url, in: "Ver https://rasc.app/b") == .notPreserved)
        #expect(ProtectedTokenExtractor.preservationStatus(of: currencyMarker, in: "$") == .notPreserved)
    }

    @Test
    func protectedTokenExtractorTreatsRepeatedIdenticalLiteralsAsOneRequirement() {
        let tokens = ProtectedTokenExtractor.extract(from: "R$ 49 depois R$ 49")
        #expect(tokens.filter { $0.category == .money }.map(\.value) == ["R$ 49"])
    }

    @Test
    func protectedLiteralGuardDiagnosticsReportRawFailureAndFinalSafetySuccess() throws {
        let evalCase = RefineEvalCase(
            id: "protected-guard-test",
            source: "unit",
            category: ["protected-tokens"],
            tags: ["technical"],
            input: "check next_retry_at tomorrow",
            languagePolicy: RefineCorpusLanguagePolicy(mode: .matchNote),
            expected: RefineEvalExpectation(
                allowedActions: [.noChange, .cleanup],
                mustNotIntroduceInformation: true
            ),
            severity: .critical
        )
        let record = RefineEvalRunRecord(
            caseID: evalCase.id,
            runIndex: 0,
            input: evalCase.input,
            output: evalCase.input,
            decision: .noChange,
            kind: .alreadyGood,
            latencyMs: 10,
            providerError: nil,
            productionRejection: nil,
            skippedReason: nil,
            promptVersion: "refine-v2-language",
            modelIdentifier: "test",
            availability: "available",
            languageDiagnostics: nil,
            protectedLiteralDiagnostics: RefineEvalProtectedLiteralDiagnostics(
                validatorEvaluated: true,
                validatorRejected: true,
                violationReason: .dropped,
                literalClass: .identifier
            )
        )
        let score = RefineEvalScorer.score(case: evalCase, runIndex: 0, record: record)
        let report = RefineEvalReportGenerator.generate(
            bundle: metricBundle(records: [record], scores: [score]),
            cases: [evalCase]
        )

        #expect(score.passedObjectively)
        #expect(report.protectedLiteralMetrics?.coveredRuns == 1)
        #expect(report.protectedLiteralMetrics?.rawProposalCorruptionCount == 1)
        #expect(report.protectedLiteralMetrics?.guardRejectionCount == 1)
        #expect(report.protectedLiteralMetrics?.userVisibleProtectedLiteralCorruptionCount == 0)
        #expect(report.protectedLiteralMetrics?.rejectionsByClass["identifier"] == 1)
    }

    @Test
    func expansionRatioScoringFlagsExcessiveGrowth() {
        let evalCase = RefineEvalCase(
            id: "test",
            source: "unit",
            category: ["tiny"],
            tags: ["pt"],
            input: "deploy?",
            languagePolicy: RefineCorpusLanguagePolicy(mode: .matchNote),
            expected: RefineEvalExpectation(mustNotIntroduceInformation: true, maxExpansionRatio: 1.2),
            severity: .critical
        )
        let record = RefineEvalRunRecord(
            caseID: "test",
            runIndex: 0,
            input: "deploy?",
            output: "Please review the deployment pipeline and confirm rollback steps.",
            decision: .changed,
            kind: .unknown,
            latencyMs: 10,
            providerError: nil,
            productionRejection: nil,
            skippedReason: nil,
            promptVersion: "refine-v1",
            modelIdentifier: "test",
            availability: "available",
            languageDiagnostics: nil
        )
        let score = RefineEvalScorer.score(case: evalCase, runIndex: 0, record: record)
        #expect(score.objectiveFailures.contains { $0.kind == .expansionExceeded })
    }

    @Test
    func selectionContextLeakageIsDetected() throws {
        let fullNote = "ola tudobem como vc ta?"
        let evalCase = RefineEvalCase(
            id: "selection-test",
            source: "unit",
            category: ["selection"],
            tags: ["pt"],
            input: "ola tudobem",
            scope: .selection,
            selection: "ola tudobem",
            surroundingContext: RefineSurroundingContext(
                before: "",
                after: " como vc ta?",
                fullNote: fullNote
            ),
            languagePolicy: RefineCorpusLanguagePolicy(mode: .matchNote),
            expected: RefineEvalExpectation(expectedLanguage: "pt"),
            severity: .critical
        )
        let record = RefineEvalRunRecord(
            caseID: "selection-test",
            runIndex: 0,
            input: "ola tudobem",
            output: fullNote,
            decision: .changed,
            kind: .message,
            latencyMs: 5,
            providerError: nil,
            productionRejection: "context_leak",
            skippedReason: nil,
            promptVersion: "refine-v1",
            modelIdentifier: "test",
            availability: "available",
            languageDiagnostics: nil
        )
        let score = RefineEvalScorer.score(case: evalCase, runIndex: 0, record: record)
        #expect(score.objectiveFailures.contains { $0.kind == .contextLeakage || $0.kind == .productionGuardRejection })
    }

    @Test
    func languageAnalyzerDetectsPortugueseEnglishAndMixed() {
        #expect(RefineEvalLanguageAnalyzer.detectLanguage(in: "falar com João amanhã") == .portuguese)
        #expect(RefineEvalLanguageAnalyzer.detectLanguage(in: "check deploy logs tomorrow") == .english)
        #expect(RefineEvalLanguageAnalyzer.detectLanguage(in: "mañana hablar con Juan") == .spanish)
        #expect(RefineEvalLanguageAnalyzer.detectLanguage(in: "revisar onboarding copy maybe ask Ana") == .mixed)
        #expect(
            RefineEvalLanguageAnalyzer.detectLanguage(in: "hola equipo todo bien?") == .spanish
        )
    }

    @Test
    func reportGeneratorComputesLatencyPercentiles() {
        let records = (1...20).map { i in
            RefineEvalRunRecord(
                caseID: "c\(i)",
                runIndex: 0,
                input: "x",
                output: "y",
                decision: .noChange,
                kind: .alreadyGood,
                latencyMs: Double(i * 10),
                providerError: nil,
                productionRejection: nil,
                skippedReason: nil,
                promptVersion: "refine-v1",
                modelIdentifier: "test",
                availability: "available",
                languageDiagnostics: nil
            )
        }
        let bundle = RefineEvalRunBundle(
            environment: RefineEvalEnvironment(
                promptVersion: "refine-v1",
                modelIdentifier: "test",
                provider: "test",
                osVersion: "test",
                appVersion: "test",
                modelAvailability: "available",
                samplingConfiguration: "test",
                runStartedAt: "now",
                runFinishedAt: "now"
            ),
            configuration: RefineEvalRunConfigurationSnapshot(
                split: .dev,
                filterTags: [],
                filterCategories: [],
                repetitions: 1,
                criticalStabilityOnly: false,
                caseCount: 20
            ),
            records: records,
            scores: []
        )
        let report = RefineEvalReportGenerator.generate(bundle: bundle, cases: [])
        #expect(report.latency.sampleCount == 20)
        #expect(report.latency.p50Ms > 0)
        #expect(report.latency.p95Ms >= report.latency.p50Ms)
    }

    @Test
    func comparatorFindsImprovementsAndRegressions() {
        let baselineScore = RefineEvalCaseScore(
            caseID: "a",
            runIndex: 0,
            objectiveFailures: [RefineObjectiveFailure(kind: .languageDrift, message: "drift", severity: .critical)],
            requiresSemanticReview: false,
            semanticReviewReasons: [],
            requiresHumanReview: false,
            evaluatorDisagreement: false,
            languageBehavior: nil,
            passedObjectively: false,
            inputLanguage: "pt",
            outputLanguage: "english",
            expansionRatio: 2,
            latencyMs: 100,
            decision: .changed
        )
        let candidateScore = RefineEvalCaseScore(
            caseID: "a",
            runIndex: 0,
            objectiveFailures: [],
            requiresSemanticReview: false,
            semanticReviewReasons: [],
            requiresHumanReview: false,
            evaluatorDisagreement: false,
            languageBehavior: nil,
            passedObjectively: true,
            inputLanguage: "pt",
            outputLanguage: "portuguese",
            expansionRatio: 1,
            latencyMs: 90,
            decision: .noChange
        )
        let baselineBundle = makeBundle(scores: [baselineScore], p50: 100, p95: 200)
        let candidateBundle = makeBundle(scores: [candidateScore], p50: 90, p95: 180)
        let comparison = RefineEvalComparator.compareBundles(
            baseline: baselineBundle,
            candidate: candidateBundle,
            baselinePath: "/tmp/base",
            candidatePath: "/tmp/cand"
        )
        #expect(comparison.improvements == ["a"])
        #expect(comparison.regressions.isEmpty)
        #expect(comparison.criticalRegressions.isEmpty)
    }

    @Test
    func fixedLocaleCasesAreMarkedNotExecutableInBaseline() throws {
        let cases = try RefineEvalDatasetLoader.loadCorpus(from: corpusRoot)
        let fixed = cases.filter { $0.languagePolicy.mode == .fixedLocale }
        #expect(!fixed.isEmpty)
        #expect(fixed.allSatisfy { $0.executableUnderCurrentProduction == false })
        #expect(fixed.allSatisfy { !$0.isExecutableUnderBaseline })
    }

    @Test
    func inputLengthBucketsUseWhitespaceDelimitedTokens() {
        func evalCase(_ input: String) -> RefineEvalCase {
            RefineEvalCase(
                id: input,
                source: "unit",
                category: ["test"],
                tags: ["en"],
                input: input,
                languagePolicy: RefineCorpusLanguagePolicy(mode: .matchNote),
                expected: RefineEvalExpectation(),
                severity: .high
            )
        }

        #expect(evalCase("deploy").inputLengthBucket == "1")
        #expect(evalCase("API retry").inputLengthBucket == "2-3")
        #expect(evalCase("falar ana sexta orçamento").inputLengthBucket == "4-8")
        #expect(evalCase("one two three four five six seven eight nine").inputLengthBucket == "9+")
    }

    @Test
    func decisionMetricsRespectAllowedActionsForOverAbstention() {
        let requiredCleanup = metricCase(
            id: "required-cleanup",
            input: "send msg ana tomorrow",
            categories: ["telegraphic"],
            expectation: RefineEvalExpectation(
                preferredAction: .cleanup,
                allowedActions: [.cleanup],
                expectedLanguage: "en"
            )
        )
        let flexible = metricCase(
            id: "flexible",
            input: "API retry",
            categories: ["tiny", "ambiguous"],
            expectation: RefineEvalExpectation(
                preferredAction: .noChange,
                allowedActions: [.noChange, .cleanup],
                expectedLanguage: "en",
                expectsNoChange: true
            )
        )
        let cases = [requiredCleanup, flexible]
        let records = cases.map { metricRecord(caseID: $0.id, input: $0.input, runIndex: 0, decision: .noChange) }
        let scores = zip(cases, records).map { RefineEvalScorer.score(case: $0.0, runIndex: 0, record: $0.1) }
        let report = RefineEvalReportGenerator.generate(
            bundle: metricBundle(records: records, scores: scores),
            cases: cases
        )

        #expect(report.decisionMetrics?.overall.overAbstentionEligibleCount == 1)
        #expect(report.decisionMetrics?.overall.overAbstentionCount == 1)
        #expect(report.decisionMetrics?.overall.appropriateNoChangeCount == 1)
        #expect(report.decisionMetrics?.clearlyRefinableTelegraphic.overAbstentionRate == 1)
        #expect(report.decisionMetrics?.tinyAmbiguous.overAbstentionEligibleCount == 0)
    }

    @Test
    func decisionMetricsExposeLengthSafetyAndNoChangeFlapping() {
        let evalCase = metricCase(
            id: "flapping",
            input: "ver logs",
            categories: ["tiny", "technical"],
            expectation: RefineEvalExpectation(
                preferredAction: .noChange,
                allowedActions: [.noChange, .cleanup],
                expectedLanguage: "pt",
                mustNotIntroduceInformation: true,
                maxExpansionRatio: 1.2,
                expectsNoChange: true
            )
        )
        let changed = metricRecord(
            caseID: evalCase.id,
            input: evalCase.input,
            runIndex: 0,
            decision: .changed,
            output: "Verificar os logs de erro da aplicação antes do deploy."
        )
        let noChange = metricRecord(
            caseID: evalCase.id,
            input: evalCase.input,
            runIndex: 1,
            decision: .noChange
        )
        let records = [changed, noChange]
        let scores = records.map { RefineEvalScorer.score(case: evalCase, runIndex: $0.runIndex, record: $0) }
        let report = RefineEvalReportGenerator.generate(
            bundle: metricBundle(records: records, scores: scores),
            cases: [evalCase]
        )

        let length = report.decisionMetrics?.byInputLength["2-3"]
        #expect(length?.changedCount == 1)
        #expect(length?.noChangeCount == 1)
        #expect(length?.harmfulEditCount == 1)
        #expect(length?.excessiveExpansionCount == 1)
        #expect(length?.inventedInformationIndicatorCount == 1)
        #expect(length?.actionFlappingCaseCount == 1)
        #expect(report.stabilityDecomposition?.noChangeChangedFlapping?.unstableCases == 1)
    }

    @Test
    func aggregateReportStillDecodesPreM12B003Summaries() throws {
        let url = corpusRoot
            .appendingPathComponent("experiments/M12B-001-language-contract/reports/dev/summary.json")
        let data = try Data(contentsOf: url)
        let report = try JSONDecoder().decode(RefineEvalAggregateReport.self, from: data)
        #expect(report.decisionMetrics == nil)
    }

    private func metricCase(
        id: String,
        input: String,
        categories: [String],
        expectation: RefineEvalExpectation
    ) -> RefineEvalCase {
        RefineEvalCase(
            id: id,
            source: "unit",
            category: categories,
            tags: ["test"],
            input: input,
            languagePolicy: RefineCorpusLanguagePolicy(mode: .matchNote),
            expected: expectation,
            severity: .critical
        )
    }

    private func metricRecord(
        caseID: String,
        input: String,
        runIndex: Int,
        decision: RefinementDecision,
        output: String? = nil
    ) -> RefineEvalRunRecord {
        RefineEvalRunRecord(
            caseID: caseID,
            runIndex: runIndex,
            input: input,
            output: output ?? input,
            decision: decision,
            kind: .unknown,
            latencyMs: 10,
            providerError: nil,
            productionRejection: nil,
            skippedReason: nil,
            promptVersion: "refine-v3-nochange-ambiguity",
            modelIdentifier: "test",
            availability: "available",
            languageDiagnostics: nil
        )
    }

    private func metricBundle(
        records: [RefineEvalRunRecord],
        scores: [RefineEvalCaseScore]
    ) -> RefineEvalRunBundle {
        let bundle = makeBundle(scores: scores, p50: 10, p95: 10)
        return RefineEvalRunBundle(
            environment: bundle.environment,
            configuration: bundle.configuration,
            records: records,
            scores: scores
        )
    }

    private func makeBundle(scores: [RefineEvalCaseScore], p50: Double, p95: Double) -> RefineEvalRunBundle {
        let env = RefineEvalEnvironment(
            promptVersion: "refine-v1",
            modelIdentifier: "test",
            provider: "test",
            osVersion: "test",
            appVersion: "test",
            modelAvailability: "available",
            samplingConfiguration: "test",
            runStartedAt: "now",
            runFinishedAt: "now"
        )
        return RefineEvalRunBundle(
            environment: env,
            configuration: RefineEvalRunConfigurationSnapshot(
                split: .dev,
                filterTags: [],
                filterCategories: [],
                repetitions: 1,
                criticalStabilityOnly: false,
                caseCount: scores.count
            ),
            records: [],
            scores: scores
        )
    }
}

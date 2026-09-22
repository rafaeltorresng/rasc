import Foundation

struct RefineEvalEnvironment: Codable, Sendable {
    var promptVersion: String
    var modelIdentifier: String
    var provider: String
    var osVersion: String
    var appVersion: String
    var modelAvailability: String
    var samplingConfiguration: String
    var runStartedAt: String
    var runFinishedAt: String?
}

struct RefineEvalRunBundle: Codable, Sendable {
    var environment: RefineEvalEnvironment
    var configuration: RefineEvalRunConfigurationSnapshot
    var records: [RefineEvalRunRecord]
    var scores: [RefineEvalCaseScore]
}

struct RefineEvalRunConfigurationSnapshot: Codable, Sendable {
    var split: RefineEvalSplit
    var filterTags: [String]
    var filterCategories: [String]
    var repetitions: Int
    var criticalStabilityOnly: Bool
    var caseCount: Int
}

enum RefineEvalRunner {
    static func run(
        configuration: RefineEvalRunConfiguration,
        provider: any RefinementProvider = FoundationModelsRefinementProvider(),
        semanticJudge: any RefineSemanticJudge = NoOpRefineSemanticJudge()
    ) async throws -> RefineEvalRunBundle {
        let corpus = try RefineEvalDatasetLoader.loadCorpus(from: configuration.corpusRoot)
        let shouldLoadRegression = configuration.includeRegression || configuration.split == .regression
        let regression = shouldLoadRegression
            ? try RefineEvalDatasetLoader.loadRegression(from: configuration.corpusRoot)
            : []
        let splits = try RefineEvalDatasetLoader.loadSplits(from: configuration.corpusRoot)

        var cases: [RefineEvalCase]
        switch configuration.split {
        case .regression:
            cases = regression
        case .all:
            cases = corpus + regression
            cases = RefineEvalDatasetLoader.filter(
                cases: cases,
                split: .all,
                tags: configuration.filterTags,
                categories: configuration.filterCategories,
                criticalStabilityOnly: configuration.criticalStabilityOnly,
                splitsManifest: splits
            )
        default:
            cases = corpus
            if configuration.includeRegression {
                cases += regression
            }
            cases = RefineEvalDatasetLoader.filter(
                cases: cases,
                split: configuration.split,
                tags: configuration.filterTags,
                categories: configuration.filterCategories,
                criticalStabilityOnly: configuration.criticalStabilityOnly,
                splitsManifest: splits
            )
        }

        let startedAt = ISO8601DateFormatter().string(from: Date())
        var records: [RefineEvalRunRecord] = []
        var scores: [RefineEvalCaseScore] = []

        let probeRequest = RefineEvalCase(
            id: "probe",
            source: "probe",
            category: [],
            tags: [],
            input: "probe",
            scope: .wholeNote,
            selection: nil,
            surroundingContext: nil,
            languagePolicy: RefineCorpusLanguagePolicy(mode: .matchNote),
            expected: RefineEvalExpectation(),
            severity: .low,
            executableUnderCurrentProduction: true,
            executionNote: nil,
            reviewStatus: nil,
            inReviewQueue: nil,
            split: nil
        ).makeRefinementRequest()
        let availability = await provider.availability(for: probeRequest)

        for evalCase in cases {
            let repetitions = configuration.repetitions
            for runIndex in 0..<repetitions {
                let record = await executeCase(
                    evalCase: evalCase,
                    runIndex: runIndex,
                    provider: provider,
                    availability: availability,
                    metadata: provider.metadata
                )
                records.append(record)
                scores.append(RefineEvalScorer.score(case: evalCase, runIndex: runIndex, record: record))

                if let output = record.output, let decision = record.decision {
                    _ = await semanticJudge.judge(
                        evalCase: evalCase,
                        input: evalCase.input,
                        output: output,
                        decision: decision
                    )
                }
            }
        }

        let environment = RefineEvalEnvironment(
            promptVersion: provider.metadata.promptVersion,
            modelIdentifier: provider.metadata.modelIdentifier,
            provider: provider.metadata.provider,
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            modelAvailability: availability.diagnosticLabel,
            samplingConfiguration: "production FoundationModelsRefinementProvider (unchanged in M12A)",
            runStartedAt: startedAt,
            runFinishedAt: ISO8601DateFormatter().string(from: Date())
        )

        return RefineEvalRunBundle(
            environment: environment,
            configuration: RefineEvalRunConfigurationSnapshot(
                split: configuration.split,
                filterTags: Array(configuration.filterTags).sorted(),
                filterCategories: Array(configuration.filterCategories).sorted(),
                repetitions: configuration.repetitions,
                criticalStabilityOnly: configuration.criticalStabilityOnly,
                caseCount: cases.count
            ),
            records: records,
            scores: scores
        )
    }

    private static func executeCase(
        evalCase: RefineEvalCase,
        runIndex: Int,
        provider: any RefinementProvider,
        availability: RefinementAvailability,
        metadata: RefinementMetadata
    ) async -> RefineEvalRunRecord {
        let started = Date()

        guard evalCase.isExecutableUnderProduction else {
            return RefineEvalRunRecord(
                caseID: evalCase.id,
                runIndex: runIndex,
                input: evalCase.input,
                output: nil,
                decision: nil,
                kind: nil,
                latencyMs: 0,
                providerError: nil,
                productionRejection: nil,
                skippedReason: evalCase.executionNote ?? "Not executable under current production language policy.",
                promptVersion: metadata.promptVersion,
                modelIdentifier: metadata.modelIdentifier,
                availability: availability.diagnosticLabel,
                languageDiagnostics: nil
            )
        }

        let request = evalCase.makeRefinementRequest()

        if case let .noChange(reason) = RefinementPreflightPolicy.evaluate(request) {
            return RefineEvalRunRecord(
                caseID: evalCase.id,
                runIndex: runIndex,
                input: evalCase.input,
                output: request.inputText,
                decision: .noChange,
                kind: .alreadyGood,
                latencyMs: elapsedMs(since: started),
                providerError: nil,
                productionRejection: nil,
                skippedReason: nil,
                promptVersion: metadata.promptVersion,
                modelIdentifier: metadata.modelIdentifier,
                availability: availability.diagnosticLabel,
                languageDiagnostics: nil,
                preflightReason: reason.rawValue
            )
        }

        guard case .available = availability else {
            return RefineEvalRunRecord(
                caseID: evalCase.id,
                runIndex: runIndex,
                input: evalCase.input,
                output: nil,
                decision: nil,
                kind: nil,
                latencyMs: elapsedMs(since: started),
                providerError: "Model unavailable: \(availability.diagnosticLabel)",
                productionRejection: nil,
                skippedReason: nil,
                promptVersion: metadata.promptVersion,
                modelIdentifier: metadata.modelIdentifier,
                availability: availability.diagnosticLabel,
                languageDiagnostics: nil
            )
        }

        do {
            let providerResult = try await provider.refine(request)
            let exactLiteralResult = RefineProtectedLiteralValidator.finalize(providerResult, for: request)
            let moneyResult = RefineMoneyLiteralValidator.finalize(exactLiteralResult, for: request)
            let percentageResult = RefinePercentageLiteralValidator.finalize(moneyResult, for: request)
            let result = RefineTimeLiteralValidator.finalize(percentageResult, for: request)
            let latency = elapsedMs(since: started)
            var rejection: String?

            switch result.decision {
            case .noChange:
                break
            case .changed:
                if result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    rejection = "invalid_replacement"
                } else if !request.allowsChangedText(result.text) {
                    rejection = "runaway_expansion"
                } else if !request.isReplacementOnly(result.text) {
                    rejection = "context_leak"
                } else if request.hasDuplicateContextLeak(result.text) {
                    rejection = "selectionDuplicateContextLeak"
                } else if result.text == request.inputText {
                    rejection = "no_change"
                }
            }

            let baseRecord = RefineEvalRunRecord(
                caseID: evalCase.id,
                runIndex: runIndex,
                input: evalCase.input,
                output: result.text,
                decision: result.decision,
                kind: result.kind,
                latencyMs: latency,
                providerError: nil,
                productionRejection: rejection,
                skippedReason: nil,
                promptVersion: metadata.promptVersion,
                modelIdentifier: metadata.modelIdentifier,
                availability: availability.diagnosticLabel,
                languageDiagnostics: nil,
                protectedLiteralDiagnostics: result.protectedLiteralTrace.map {
                    RefineEvalProtectedLiteralDiagnostics(
                        validatorEvaluated: $0.validatorEvaluated,
                        validatorRejected: $0.validatorRejected,
                        violationReason: $0.violationReason,
                        literalClass: $0.literalClass
                    )
                }
            )
            return RefineEvalRunRecord(
                caseID: baseRecord.caseID,
                runIndex: baseRecord.runIndex,
                input: baseRecord.input,
                output: baseRecord.output,
                decision: baseRecord.decision,
                kind: baseRecord.kind,
                latencyMs: baseRecord.latencyMs,
                providerError: baseRecord.providerError,
                productionRejection: baseRecord.productionRejection,
                skippedReason: baseRecord.skippedReason,
                promptVersion: baseRecord.promptVersion,
                modelIdentifier: baseRecord.modelIdentifier,
                availability: baseRecord.availability,
                languageDiagnostics: RefineEvalLanguageDiagnosticsBuilder.build(
                    evalCase: evalCase,
                    record: baseRecord,
                    trace: result.languageTrace
                ),
                protectedLiteralDiagnostics: baseRecord.protectedLiteralDiagnostics
            )
        } catch {
            return RefineEvalRunRecord(
                caseID: evalCase.id,
                runIndex: runIndex,
                input: evalCase.input,
                output: nil,
                decision: nil,
                kind: nil,
                latencyMs: elapsedMs(since: started),
                providerError: String(describing: error),
                productionRejection: nil,
                skippedReason: nil,
                promptVersion: metadata.promptVersion,
                modelIdentifier: metadata.modelIdentifier,
                availability: availability.diagnosticLabel,
                languageDiagnostics: nil
            )
        }
    }

    private static func elapsedMs(since start: Date) -> Double {
        Date().timeIntervalSince(start) * 1000
    }
}

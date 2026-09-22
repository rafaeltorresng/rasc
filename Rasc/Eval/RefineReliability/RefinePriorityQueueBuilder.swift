import Foundation

enum RefinePriorityQueueBuilder {
    static let sourceLanguageDrift = "m12b001_dev_language_drift"
    static let sourceValidatorFalseNegative = "validator_false_negative"
    static let sourceEvaluatorDisagreement = "evaluator_disagreement"
    static let sourceM12B001Regression = "m12b001_dev_regression"
    static let sourcePermanentRegression = "permanent_regression"
    static let sourceReviewQueueTinyMixed = "review_queue_tiny_mixed"

    struct BuildInput: Sendable {
        var corpusRoot: URL
        var m12b001DevResults: URL?
        var rootCauseTableMarkdown: URL?
        var includeHoldout: Bool
    }

    static func build(input: BuildInput) throws -> RefinePriorityQueueManifest {
        let corpusRoot = input.corpusRoot
        let corpus = try RefineEvalDatasetLoader.loadCorpus(from: corpusRoot)
        let regression = try RefineEvalDatasetLoader.loadRegression(from: corpusRoot)
        let reviewQueue = try RefineEvalDatasetLoader.loadReviewQueue(from: corpusRoot)
        let splits = try RefineEvalDatasetLoader.loadSplits(from: corpusRoot)

        let caseMap = Dictionary(uniqueKeysWithValues: (corpus + regression).map { ($0.id, $0) })
        var sourcesByCaseID: [String: Set<String>] = [:]

        func add(_ caseID: String, source: String) {
            guard let evalCase = caseMap[caseID] else { return }
            if !input.includeHoldout, isHoldout(evalCase, splits: splits) { return }
            sourcesByCaseID[caseID, default: []].insert(source)
        }

        if let resultsURL = input.m12b001DevResults,
           let bundle = try? loadResultsBundle(resultsURL)
        {
            let driftIDs = bundle.scores
                .filter { $0.runIndex == 0 }
                .filter { $0.objectiveFailures.contains { $0.kind == .languageDrift } }
                .map(\.caseID)
            for id in driftIDs {
                add(id, source: sourceLanguageDrift)
            }

            let baselineResultsPath = corpusRoot
                .appendingPathComponent("reports/baseline-dev-v2/results.json")
            if let baselineBundle = try? loadResultsBundle(baselineResultsPath) {
                let baselinePass = Dictionary(
                    uniqueKeysWithValues: baselineBundle.scores
                        .filter { $0.runIndex == 0 }
                        .map { ($0.caseID, $0.passedObjectively) }
                )
                for score in bundle.scores where score.runIndex == 0 {
                    if baselinePass[score.caseID] == true && !score.passedObjectively {
                        add(score.caseID, source: sourceM12B001Regression)
                    }
                }
            }
        }

        if let rootCauseURL = input.rootCauseTableMarkdown,
           FileManager.default.fileExists(atPath: rootCauseURL.path)
        {
            let text = try String(contentsOf: rootCauseURL, encoding: .utf8)
            for (caseID, rootCause) in parseRootCauseCases(from: text) {
                switch rootCause {
                case sourceValidatorFalseNegative:
                    add(caseID, source: sourceValidatorFalseNegative)
                case sourceEvaluatorDisagreement:
                    add(caseID, source: sourceEvaluatorDisagreement)
                default:
                    break
                }
            }
        }

        for evalCase in regression {
            add(evalCase.id, source: sourcePermanentRegression)
        }

        for evalCase in reviewQueue {
            let isTiny = evalCase.category.contains("tiny")
                || evalCase.category.contains("one-word")
                || evalCase.category.contains("two-three-word")
                || evalCase.tags.contains("mixed")
                || evalCase.expected.expectedLanguage == "mixed"
            if isTiny {
                add(evalCase.id, source: sourceReviewQueueTinyMixed)
            }
        }

        let sourceCounts = RefinePriorityQueueOverlapStats.computeSourceCounts(sourcesByCaseID)
        let reviewQueueIDs = reviewQueue.map(\.id)
        let adjudications = RefineAdjudicationStore.latestByCaseID(
            (try? RefineAdjudicationStore.load(from: corpusRoot)) ?? []
        )
        let adjudicationsV2 = (try? RefineAdjudicationStore.latestMergedV2(from: corpusRoot)) ?? [:]

        return RefinePriorityQueueManifest(
            version: 1,
            generatedAt: ISO8601DateFormatter().string(from: Date()),
            excludesHoldout: !input.includeHoldout,
            caseIDs: sourcesByCaseID.keys.sorted(),
            sourcesByCaseID: sourcesByCaseID.mapValues { Array($0).sorted() },
            overlapStats: RefinePriorityQueueOverlapStats(
                totalUniqueCases: sourcesByCaseID.count,
                sourceCounts: sourceCounts,
                multiSourceCases: sourcesByCaseID.values.filter { $0.count > 1 }.count
            ),
            reviewQueue75Status: RefineAdjudicationStore.summarizeReviewQueue75(
                reviewQueueCaseIDs: reviewQueueIDs,
                adjudications: adjudications,
                adjudicationsV2: adjudicationsV2
            )
        )
    }

    static func write(_ manifest: RefinePriorityQueueManifest, to corpusRoot: URL) throws {
        let url = corpusRoot.appendingPathComponent("priority-queue.v1.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: url)
    }

    private static func isHoldout(_ evalCase: RefineEvalCase, splits: RefineEvalSplitsManifest) -> Bool {
        (evalCase.split ?? splits.assignments[evalCase.id]) == .holdout
    }

    private static func loadResultsBundle(_ url: URL) throws -> RefineEvalRunBundle {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(RefineEvalRunBundle.self, from: data)
    }

    private static func parseRootCauseCases(from markdown: String) -> [(String, String)] {
        var rows: [(String, String)] = []
        for line in markdown.split(separator: "\n") {
            guard line.contains("`") else { continue }
            let text = String(line)
            guard let firstTick = text.firstIndex(of: "`"),
                  let secondTick = text[text.index(after: firstTick)...].firstIndex(of: "`")
            else { continue }
            let caseID = String(text[text.index(after: firstTick)..<secondTick])
            if text.contains(sourceValidatorFalseNegative) {
                rows.append((caseID, sourceValidatorFalseNegative))
            } else if text.contains(sourceEvaluatorDisagreement) {
                rows.append((caseID, sourceEvaluatorDisagreement))
            }
        }
        return rows
    }

}

private extension RefinePriorityQueueOverlapStats {
    static func computeSourceCounts(_ sources: [String: Set<String>]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for tags in sources.values {
            for tag in tags {
                counts[tag, default: 0] += 1
            }
        }
        return counts
    }
}

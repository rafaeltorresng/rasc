import Foundation

#if DEBUG
enum RefineReviewCommandLine {
    static func runIfRequested() -> Bool {
        let args = CommandLine.arguments
        guard args.contains("--refine-review-generate-queue")
            || args.contains("--refine-review-apply-adjudications")
            || args.contains("--refine-review-status")
        else { return false }

        do {
            let corpusRoot = RefineEvalRunConfiguration.defaultCorpusRoot()
            if args.contains("--refine-review-generate-queue") {
                let includeHoldout = args.contains("--include-holdout")
                let manifest = try RefinePriorityQueueBuilder.build(
                    input: RefinePriorityQueueBuilder.BuildInput(
                        corpusRoot: corpusRoot,
                        m12b001DevResults: corpusRoot
                            .appendingPathComponent("experiments/M12B-001-language-contract/reports/dev/results.json"),
                        rootCauseTableMarkdown: corpusRoot
                            .appendingPathComponent("experiments/M12B-002-language-diagnostics/m12b-001-root-cause-table.md"),
                        includeHoldout: includeHoldout
                    )
                )
                try RefinePriorityQueueBuilder.write(manifest, to: corpusRoot)
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                FileHandle.standardOutput.write(try encoder.encode(manifest))
                FileHandle.standardOutput.write(Data("\n".utf8))
            }

            if args.contains("--refine-review-apply-adjudications") {
                let result = try RefineCorpusCorrector.applyAcceptedCorrections(corpusRoot: corpusRoot)
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                FileHandle.standardOutput.write(try encoder.encode(result))
                FileHandle.standardOutput.write(Data("\n".utf8))
            }

            if args.contains("--refine-review-status") {
                let adjudications = try RefineAdjudicationStore.load(from: corpusRoot)
                let latest = RefineAdjudicationStore.latestByCaseID(adjudications)
                let latestV2 = try RefineAdjudicationStore.latestMergedV2(from: corpusRoot)
                let reviewQueue = try RefineEvalDatasetLoader.loadReviewQueue(from: corpusRoot)
                let summary = RefineAdjudicationStore.summarizeReviewQueue75(
                    reviewQueueCaseIDs: reviewQueue.map(\.id),
                    adjudications: latest,
                    adjudicationsV2: latestV2
                )
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                FileHandle.standardOutput.write(try encoder.encode(summary))
                FileHandle.standardOutput.write(Data("\n".utf8))
            }

            exit(0)
        } catch {
            FileHandle.standardError.write(Data("Refine review command failed: \(error)\n".utf8))
            exit(1)
        }
    }
}
#endif

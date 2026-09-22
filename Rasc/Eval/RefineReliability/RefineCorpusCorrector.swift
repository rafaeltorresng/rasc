import Foundation

enum RefineCorpusCorrector {
    static func applyAcceptedCorrections(
        corpusRoot: URL,
        sourceFileName: String = "corpus.v1.jsonl",
        targetFileName: String = "corpus.v2.jsonl",
        changelogFileName: String = "corpus.v2.changelog.json"
    ) throws -> RefineCorpusApplyResult {
        let adjudicationsV2 = try RefineAdjudicationStore.latestMergedV2(from: corpusRoot)
        let applicable = adjudicationsV2.values.filter {
            $0.benchmarkJudgment == .benchmarkExpectationWrong || $0.benchmarkJudgment == .needsConstraintEdit
        }
        guard !applicable.isEmpty else {
            throw RefineCorpusCorrectorError.noApplicableCorrections
        }

        let sourceURL = corpusRoot.appendingPathComponent(sourceFileName)
        let targetURL = corpusRoot.appendingPathComponent(targetFileName)
        let changelogURL = corpusRoot.appendingPathComponent(changelogFileName)

        var cases = try RefineEvalDatasetLoader.loadJSONL(sourceURL)
        var changelog: [RefineCorpusChangelogEntry] = []
        let caseIndex = Dictionary(uniqueKeysWithValues: cases.enumerated().map { ($1.id, $0) })

        for record in applicable {
            guard let correction = record.constraintCorrection else { continue }
            guard let index = caseIndex[record.caseID] else { continue }
            var evalCase = cases[index]
            var changes: [String] = []

            if let expectedLanguage = correction.expectedLanguage {
                evalCase.expected.expectedLanguage = expectedLanguage
                changes.append("expectedLanguage=\(expectedLanguage)")
            }
            if let preferred = correction.preferredAction {
                evalCase.expected.preferredAction = RefineEvalAction(rawValue: preferred)
                changes.append("preferredAction=\(preferred)")
            }
            if let allowed = correction.allowedActions {
                evalCase.expected.allowedActions = allowed.compactMap(RefineEvalAction.init(rawValue:))
                changes.append("allowedActions=\(allowed.joined(separator: ","))")
            }
            if let tokens = correction.mustPreserveTokens {
                evalCase.expected.mustPreserveTokens = tokens
                changes.append("mustPreserveTokens")
            }
            if let maxRatio = correction.maxExpansionRatio {
                evalCase.expected.maxExpansionRatio = maxRatio
                changes.append("maxExpansionRatio=\(maxRatio)")
            }
            if let notes = correction.semanticNotes {
                evalCase.expected.semanticNotes = notes
                changes.append("semanticNotes")
            }
            if let severity = correction.severity, let parsed = RefineEvalSeverity(rawValue: severity) {
                evalCase.severity = parsed
                changes.append("severity=\(severity)")
            }

            guard !changes.isEmpty else { continue }
            cases[index] = evalCase
            changelog.append(
                RefineCorpusChangelogEntry(
                    caseID: record.caseID,
                    adjudicationReviewedAt: record.benchmarkReviewedAt ?? record.reviewedAt,
                    verdict: record.benchmarkJudgment?.rawValue ?? "needsConstraintEdit",
                    note: record.benchmarkNote,
                    changes: changes
                )
            )
        }

        guard !changelog.isEmpty else {
            throw RefineCorpusCorrectorError.noApplicableCorrections
        }

        try writeJSONL(cases, to: targetURL)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(changelog).write(to: changelogURL)

        return RefineCorpusApplyResult(
            sourceCorpusVersion: "v1",
            targetCorpusVersion: "v2",
            appliedCaseCount: changelog.count,
            changelog: changelog,
            outputPath: targetURL.path
        )
    }

    private static func writeJSONL(_ cases: [RefineEvalCase], to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let lines = cases.compactMap { evalCase -> String? in
            guard let data = try? encoder.encode(evalCase) else { return nil }
            return String(decoding: data, as: UTF8.self)
        }
        try lines.joined(separator: "\n").appending("\n").write(to: url, atomically: true, encoding: .utf8)
    }
}

enum RefineCorpusCorrectorError: Error, Equatable {
    case noApplicableCorrections
}

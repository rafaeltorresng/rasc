import Foundation

enum RefineEvalDatasetLoader {
    static func loadCorpus(from root: URL) throws -> [RefineEvalCase] {
        try loadJSONL(root.appendingPathComponent("corpus.v1.jsonl"))
    }

    static func loadRegression(from root: URL) throws -> [RefineEvalCase] {
        try loadJSONL(root.appendingPathComponent("regression.jsonl"))
    }

    static func loadReviewQueue(from root: URL) throws -> [RefineEvalCase] {
        try loadJSONL(root.appendingPathComponent("review-queue.jsonl"))
    }

    static func loadSplits(from root: URL) throws -> RefineEvalSplitsManifest {
        let url = root.appendingPathComponent("splits.v1.json")
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(RefineEvalSplitsManifest.self, from: data)
    }

    static func loadJSONL(_ url: URL) throws -> [RefineEvalCase] {
        let data = try String(contentsOf: url, encoding: .utf8)
        let decoder = JSONDecoder()
        return data
            .split(whereSeparator: \.isNewline)
            .compactMap { line -> RefineEvalCase? in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return nil }
                return try? decoder.decode(RefineEvalCase.self, from: Data(trimmed.utf8))
            }
    }

    static func filter(
        cases: [RefineEvalCase],
        split: RefineEvalSplit,
        tags: Set<String>,
        categories: Set<String>,
        criticalStabilityOnly: Bool,
        splitsManifest: RefineEvalSplitsManifest?
    ) -> [RefineEvalCase] {
        var filtered = cases

        if split != .all && split != .regression {
            filtered = filtered.filter { evalCase in
                let assigned = evalCase.split ?? splitsManifest?.assignments[evalCase.id]
                return assigned == split
            }
        }

        if !tags.isEmpty {
            filtered = filtered.filter { evalCase in
                !tags.isDisjoint(with: Set(evalCase.tags))
            }
        }

        if !categories.isEmpty {
            filtered = filtered.filter { evalCase in
                !categories.isDisjoint(with: Set(evalCase.category))
            }
        }

        if criticalStabilityOnly {
            filtered = filtered.filter { $0.inReviewQueue == true || $0.severity == .critical }
        }

        return filtered.sorted { $0.id < $1.id }
    }

    static func stableSplit(for caseID: String, manifest: RefineEvalSplitsManifest) -> RefineEvalSplit? {
        manifest.assignments[caseID]
    }
}

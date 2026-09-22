#if DEBUG
import Foundation

struct RefineEvalLanguageResolverCaseResult: Codable, Equatable, Sendable {
    var caseID: String
    var input: String
    var scope: String
    var expectedLanguage: String?
    var split: String?
    var categories: [String]
    var tags: [String]
    var tokenCount: Int
    var tokenBucket: String
    var cohort: String
    var production: RefineEvalLanguageResolverOutcome
    var candidate: RefineEvalLanguageResolverOutcome
}

struct RefineEvalLanguageResolverOutcome: Codable, Equatable, Sendable {
    var label: String
    var localeIdentifier: String
    var confidence: String
    var usedSystemFallback: Bool
    var resolverReason: String
    var enforcesPostValidation: Bool
}

enum RefineEvalLanguageResolverBenchmark {
    static let launchArgument = "--run-refine-resolver-eval"

    static func shouldRun(at launch: [String] = ProcessInfo.processInfo.arguments) -> Bool {
        launch.contains(launchArgument)
    }

    static func run(outputDirectory: URL, corpusRoot: URL) throws -> URL {
        let corpus = try RefineEvalDatasetLoader.loadCorpus(from: corpusRoot)
        let regression = try RefineEvalDatasetLoader.loadRegression(from: corpusRoot)
        let splits = try RefineEvalDatasetLoader.loadSplits(from: corpusRoot)
        let frontierWrongLanguage = loadFrontierWrongLanguageCaseIDs(
            corpusRoot.appendingPathComponent("frontier-adjudications.v1.jsonl")
        )

        let caseMap = Dictionary(uniqueKeysWithValues: (corpus + regression).map { ($0.id, $0) })
        let evaluationIDs = buildEvaluationCaseIDs(
            cases: corpus + regression,
            splits: splits,
            frontierWrongLanguage: frontierWrongLanguage
        )

        let results = evaluationIDs.compactMap { caseID -> RefineEvalLanguageResolverCaseResult? in
            guard let evalCase = caseMap[caseID] else { return nil }
            return evaluate(evalCase: evalCase, splits: splits, frontierWrongLanguage: frontierWrongLanguage)
        }

        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let outputURL = outputDirectory.appendingPathComponent("resolver-results.json")
        let payload = RefineEvalLanguageResolverReport(
            schemaVersion: 1,
            experiment: "M12B-007A-language-resolver",
            generatedAt: ISO8601DateFormatter().string(from: Date()),
            caseCount: results.count,
            results: results.sorted { $0.caseID < $1.caseID }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(payload).write(to: outputURL)
        return outputURL
    }

    private static func buildEvaluationCaseIDs(
        cases: [RefineEvalCase],
        splits: RefineEvalSplitsManifest,
        frontierWrongLanguage: Set<String>
    ) -> Set<String> {
        var ids = frontierWrongLanguage

        for evalCase in cases {
            let split = evalCase.split ?? splits.assignments[evalCase.id]
            guard split == .dev || split == .validation else { continue }
            guard evalCase.languagePolicy.mode == .matchNote else { continue }

            let tags = Set(evalCase.tags)
            let categories = Set(evalCase.category)
            let isLanguageEvalCase =
                evalCase.expected.expectedLanguage != nil
                || tags.contains("language")
                || tags.contains("mixed")
                || tags.contains("ambiguous")
                || tags.contains("tiny")
                || categories.contains("language")
                || evalCase.scope == .selection
                || frontierWrongLanguage.contains(evalCase.id)
                || evalCase.id == "selection-extra-007"

            if isLanguageEvalCase {
                ids.insert(evalCase.id)
            }
        }

        ids.insert("selection-extra-007")
        return ids
    }

    private static func evaluate(
        evalCase: RefineEvalCase,
        splits: RefineEvalSplitsManifest,
        frontierWrongLanguage: Set<String>
    ) -> RefineEvalLanguageResolverCaseResult {
        let request = refinementRequest(for: evalCase)
        let production = RefineLanguageResolverV1.resolve(request: request)
        let candidate = RefineLanguageResolver.resolve(request: request)
        let tokenCount = evalCase.input.split(whereSeparator: \.isWhitespace).count

        return RefineEvalLanguageResolverCaseResult(
            caseID: evalCase.id,
            input: evalCase.input,
            scope: evalCase.scope.rawValue,
            expectedLanguage: evalCase.expected.expectedLanguage,
            split: (evalCase.split ?? splits.assignments[evalCase.id])?.rawValue,
            categories: evalCase.category,
            tags: evalCase.tags,
            tokenCount: tokenCount,
            tokenBucket: tokenBucket(for: tokenCount),
            cohort: cohort(for: evalCase, frontierWrongLanguage: frontierWrongLanguage),
            production: outcome(from: production),
            candidate: outcome(from: candidate)
        )
    }

    private static func refinementRequest(for evalCase: RefineEvalCase) -> RefinementRequest {
        let fullNote = evalCase.surroundingContext?.fullNote ?? evalCase.input
        let selection: Range<String.Index>? = {
            guard evalCase.scope == .selection, let selected = evalCase.selection else { return nil }
            return fullNote.range(of: selected)
        }()

        return RefinementRequest(
            snapshot: NoteSnapshot(
                noteID: UUID(),
                revision: 1,
                text: fullNote,
                selection: selection
            ),
            languagePolicy: RefineLanguagePolicy(corpusPolicy: evalCase.languagePolicy)
        )
    }

    private static func outcome(from resolved: ResolvedRefineLanguage) -> RefineEvalLanguageResolverOutcome {
        RefineEvalLanguageResolverOutcome(
            label: resolved.label.rawValue,
            localeIdentifier: resolved.localeIdentifier,
            confidence: resolved.confidence == .high ? "high" : "insufficient",
            usedSystemFallback: resolved.usedSystemFallback,
            resolverReason: resolved.resolverReason,
            enforcesPostValidation: resolved.enforcesPostValidation
        )
    }

    private static func tokenBucket(for tokenCount: Int) -> String {
        switch tokenCount {
        case ...3: "1-3"
        case 4...8: "4-8"
        default: "9+"
        }
    }

    private static func cohort(for evalCase: RefineEvalCase, frontierWrongLanguage: Set<String>) -> String {
        if frontierWrongLanguage.contains(evalCase.id) { return "frontierWrongLanguage" }
        if evalCase.id == "selection-extra-007" { return "selectionExtra007" }
        if evalCase.scope == .selection { return "selection" }
        if evalCase.tags.contains("ambiguous") || evalCase.tags.contains("tiny") { return "tinyAmbiguous" }
        if evalCase.tags.contains("mixed") || evalCase.category.contains("mixed") { return "mixedTechnical" }
        switch evalCase.expected.expectedLanguage?.lowercased() {
        case "pt": return "clearPT"
        case "en": return "clearEN"
        case "es": return "clearES"
        default: return "other"
        }
    }

    private static func loadFrontierWrongLanguageCaseIDs(_ url: URL) -> Set<String> {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        var ids: Set<String> = []
        for line in text.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  let row = try? JSONDecoder().decode(FrontierAdjudicationRow.self, from: Data(trimmed.utf8)),
                  row.productFailureLabels.contains("wrongLanguage")
            else { continue }
            ids.insert(row.caseID)
        }
        return ids
    }
}

private struct RefineEvalLanguageResolverReport: Codable {
    var schemaVersion: Int
    var experiment: String
    var generatedAt: String
    var caseCount: Int
    var results: [RefineEvalLanguageResolverCaseResult]
}

private struct FrontierAdjudicationRow: Codable {
    var caseID: String
    var productFailureLabels: [String]
}
#endif

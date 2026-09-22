#if DEBUG
import Foundation

enum RefineEvalCommandLine {
    static let launchArgument = "--run-refine-evals"

    static func shouldRun(at launch: [String] = ProcessInfo.processInfo.arguments) -> Bool {
        launch.contains(launchArgument)
    }

    @MainActor
    static func runIfRequested() -> Bool {
        guard shouldRun() else { return false }
        Task {
            let status = await execute()
            exit(status)
        }
        return true
    }

    @MainActor
    private static func execute() async -> Int32 {
        do {
            let options = try parseArguments()
            let configuration = RefineEvalRunConfiguration(
                split: options.split,
                filterTags: options.filterTags,
                filterCategories: options.filterCategories,
                repetitions: options.repetitions,
                criticalStabilityOnly: options.criticalStabilityOnly,
                outputDirectory: options.outputDirectory,
                corpusRoot: options.corpusRoot,
                includeRegression: options.includeRegression
            )

            let bundle = try await RefineEvalRunner.run(configuration: configuration)
            let corpus = try RefineEvalDatasetLoader.loadCorpus(from: configuration.corpusRoot)
            let regression = (try? RefineEvalDatasetLoader.loadRegression(from: configuration.corpusRoot)) ?? []
            let cases = corpus + regression
            let aggregate = RefineEvalReportGenerator.generate(bundle: bundle, cases: cases)
            try RefineEvalReportGenerator.writeReports(
                bundle: bundle,
                aggregate: aggregate,
                to: configuration.outputDirectory
            )

            if let baseline = options.compareBaseline {
                let baselineData = try Data(contentsOf: baseline.appendingPathComponent("summary.json"))
                let baselineReport = try JSONDecoder().decode(RefineEvalAggregateReport.self, from: baselineData)
                let comparison = RefineEvalComparator.compare(
                    baseline: baselineReport,
                    candidate: aggregate,
                    baselineSummaryPath: baseline.path,
                    candidateSummaryPath: configuration.outputDirectory.path
                )
                try RefineEvalComparator.writeComparison(
                    comparison,
                    to: configuration.outputDirectory.appendingPathComponent("comparison.json")
                )
            }

            FileHandle.standardError.write(Data("Refine eval complete: \(configuration.outputDirectory.path)\n".utf8))
            return 0
        } catch {
            FileHandle.standardError.write(Data("Refine eval failed: \(error)\n".utf8))
            return 1
        }
    }

    private struct ParsedOptions {
        var split: RefineEvalSplit = .dev
        var filterTags: Set<String> = []
        var filterCategories: Set<String> = []
        var repetitions = 1
        var criticalStabilityOnly = false
        var outputDirectory: URL
        var corpusRoot: URL
        var includeRegression = false
        var compareBaseline: URL?
    }

    private static func parseArguments() throws -> ParsedOptions {
        let args = ProcessInfo.processInfo.arguments
        var options = ParsedOptions(
            outputDirectory: FileManager.default.temporaryDirectory
                .appendingPathComponent("rasc-refine-eval-\(UUID().uuidString)", isDirectory: true),
            corpusRoot: RefineEvalRunConfiguration.defaultCorpusRoot()
        )

        var index = 0
        while index < args.count {
            let arg = args[index]
            switch arg {
            case launchArgument:
                break
            case "--split":
                index += 1
                guard index < args.count, let split = RefineEvalSplit(rawValue: args[index]) else {
                    throw RefineEvalCLIError.invalidArgument("--split")
                }
                options.split = split
            case "--output":
                index += 1
                guard index < args.count else { throw RefineEvalCLIError.invalidArgument("--output") }
                options.outputDirectory = URL(fileURLWithPath: args[index], isDirectory: true)
            case "--filter":
                index += 1
                guard index < args.count else { throw RefineEvalCLIError.invalidArgument("--filter") }
                options.filterTags.insert(args[index])
                options.filterCategories.insert(args[index])
            case "--repetitions":
                index += 1
                guard index < args.count, let reps = Int(args[index]), reps > 0 else {
                    throw RefineEvalCLIError.invalidArgument("--repetitions")
                }
                options.repetitions = reps
            case "--critical-stability":
                options.criticalStabilityOnly = true
            case "--include-regression":
                options.includeRegression = true
            case "--corpus-root":
                index += 1
                guard index < args.count else { throw RefineEvalCLIError.invalidArgument("--corpus-root") }
                options.corpusRoot = URL(fileURLWithPath: args[index], isDirectory: true)
            case "--compare":
                index += 1
                guard index < args.count else { throw RefineEvalCLIError.invalidArgument("--compare") }
                options.compareBaseline = URL(fileURLWithPath: args[index], isDirectory: true)
            default:
                break
            }
            index += 1
        }

        return options
    }
}

private enum RefineEvalCLIError: Error, CustomStringConvertible {
    case invalidArgument(String)

    var description: String {
        switch self {
        case let .invalidArgument(value):
            "Invalid or missing value for \(value)"
        }
    }
}
#endif

#if DEBUG
import Foundation

enum RefineEvalLanguageResolverCommandLine {
    static func runIfRequested() -> Bool {
        guard RefineEvalLanguageResolverBenchmark.shouldRun() else { return false }
        do {
            let options = try parseArguments()
            let outputURL = try RefineEvalLanguageResolverBenchmark.run(
                outputDirectory: options.outputDirectory,
                corpusRoot: options.corpusRoot
            )
            FileHandle.standardError.write(Data("Refine resolver eval complete: \(outputURL.path)\n".utf8))
            exit(0)
        } catch {
            FileHandle.standardError.write(Data("Refine resolver eval failed: \(error)\n".utf8))
            exit(1)
        }
        return true
    }

    private struct ParsedOptions {
        var outputDirectory: URL
        var corpusRoot: URL
    }

    private static func parseArguments() throws -> ParsedOptions {
        let args = ProcessInfo.processInfo.arguments
        var outputDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("rasc-refine-resolver-eval-\(UUID().uuidString)", isDirectory: true)
        var corpusRoot = RefineEvalRunConfiguration.defaultCorpusRoot()

        var index = 0
        while index < args.count {
            switch args[index] {
            case RefineEvalLanguageResolverBenchmark.launchArgument:
                break
            case "--output":
                index += 1
                guard index < args.count else { throw RefineEvalLanguageResolverCLIError.invalidArgument("--output") }
                outputDirectory = URL(fileURLWithPath: args[index], isDirectory: true)
            case "--corpus-root":
                index += 1
                guard index < args.count else { throw RefineEvalLanguageResolverCLIError.invalidArgument("--corpus-root") }
                corpusRoot = URL(fileURLWithPath: args[index], isDirectory: true)
            default:
                break
            }
            index += 1
        }

        return ParsedOptions(outputDirectory: outputDirectory, corpusRoot: corpusRoot)
    }
}

private enum RefineEvalLanguageResolverCLIError: Error, CustomStringConvertible {
    case invalidArgument(String)

    var description: String {
        switch self {
        case let .invalidArgument(value):
            "Invalid or missing value for \(value)"
        }
    }
}
#endif

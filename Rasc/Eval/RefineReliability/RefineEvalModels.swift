import Foundation

enum RefineEvalCorpusVersion: String, Codable, Sendable {
    case v1 = "v1"
}

enum RefineEvalSplit: String, Codable, Sendable, CaseIterable {
    case dev
    case validation
    case holdout
    case regression
    case all
}

enum RefineEvalAction: String, Codable, Sendable {
    case noChange
    case cleanup
    case structure
}

enum RefineEvalSeverity: String, Codable, Sendable {
    case low
    case medium
    case high
    case critical
}

enum RefineCorpusLanguagePolicyMode: String, Codable, Sendable {
    case matchNote
    case fixedLocale
}

struct RefineCorpusLanguagePolicy: Codable, Equatable, Sendable {
    var mode: RefineCorpusLanguagePolicyMode
    var preferredLocale: String?
    var locale: String?
}

struct RefineEvalExpectation: Codable, Equatable, Sendable {
    var preferredAction: RefineEvalAction?
    var allowedActions: [RefineEvalAction]?
    var expectedLanguage: String?
    var mustPreserveTokens: [String]?
    var mustNotIntroduceInformation: Bool?
    var maxExpansionRatio: Double?
    var expectsNoChange: Bool?
    var exactOutput: String?
    var semanticNotes: String?
    var preferenceProfile: String?
    var preferenceAdherenceExpectation: String?
    var expectsPreferenceSuppressedForSafety: Bool?
}

struct RefineSurroundingContext: Codable, Equatable, Sendable {
    var before: String?
    var after: String?
    var fullNote: String?
}

struct RefineEvalCase: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var source: String
    var category: [String]
    var tags: [String]
    var input: String
    var scope: RefinementScope
    var selection: String?
    var surroundingContext: RefineSurroundingContext?
    var languagePolicy: RefineCorpusLanguagePolicy
    var refinePreference: String?
    var expected: RefineEvalExpectation
    var severity: RefineEvalSeverity
    var executableUnderCurrentProduction: Bool
    var executionNote: String?
    var reviewStatus: String?
    var inReviewQueue: Bool?
    var split: RefineEvalSplit?

    init(
        id: String,
        source: String,
        category: [String],
        tags: [String],
        input: String,
        scope: RefinementScope = .wholeNote,
        selection: String? = nil,
        surroundingContext: RefineSurroundingContext? = nil,
        languagePolicy: RefineCorpusLanguagePolicy,
        refinePreference: String? = nil,
        expected: RefineEvalExpectation,
        severity: RefineEvalSeverity,
        executableUnderCurrentProduction: Bool = true,
        executionNote: String? = nil,
        reviewStatus: String? = nil,
        inReviewQueue: Bool? = nil,
        split: RefineEvalSplit? = nil
    ) {
        self.id = id
        self.source = source
        self.category = category
        self.tags = tags
        self.input = input
        self.scope = scope
        self.selection = selection
        self.surroundingContext = surroundingContext
        self.languagePolicy = languagePolicy
        self.refinePreference = refinePreference
        self.expected = expected
        self.severity = severity
        self.executableUnderCurrentProduction = executableUnderCurrentProduction
        self.executionNote = executionNote
        self.reviewStatus = reviewStatus
        self.inReviewQueue = inReviewQueue
        self.split = split
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        source = try container.decode(String.self, forKey: .source)
        category = try container.decode([String].self, forKey: .category)
        tags = try container.decode([String].self, forKey: .tags)
        input = try container.decode(String.self, forKey: .input)
        scope = try container.decodeIfPresent(RefinementScope.self, forKey: .scope) ?? .wholeNote
        selection = try container.decodeIfPresent(String.self, forKey: .selection)
        surroundingContext = try container.decodeIfPresent(RefineSurroundingContext.self, forKey: .surroundingContext)
        languagePolicy = try container.decode(RefineCorpusLanguagePolicy.self, forKey: .languagePolicy)
        refinePreference = try container.decodeIfPresent(String.self, forKey: .refinePreference)
        expected = try container.decode(RefineEvalExpectation.self, forKey: .expected)
        severity = try container.decode(RefineEvalSeverity.self, forKey: .severity)
        executableUnderCurrentProduction = try container.decodeIfPresent(
            Bool.self,
            forKey: .executableUnderCurrentProduction
        ) ?? true
        executionNote = try container.decodeIfPresent(String.self, forKey: .executionNote)
        reviewStatus = try container.decodeIfPresent(String.self, forKey: .reviewStatus)
        inReviewQueue = try container.decodeIfPresent(Bool.self, forKey: .inReviewQueue)
        split = try container.decodeIfPresent(RefineEvalSplit.self, forKey: .split)
    }

    var isExecutableUnderBaseline: Bool {
        executableUnderCurrentProduction && languagePolicy.mode == .matchNote
    }

    var isExecutableUnderProduction: Bool {
        switch languagePolicy.mode {
        case .matchNote:
            executableUnderCurrentProduction
        case .fixedLocale:
            true
        }
    }

    func makeRefinementRequest() -> RefinementRequest {
        let fullNote = surroundingContext?.fullNote ?? input
        let selectionRange: Range<String.Index>? = {
            guard scope == .selection else { return nil }
            let selected = selection ?? input
            guard let range = fullNote.range(of: selected) else { return nil }
            return range
        }()
        let snapshot = NoteSnapshot(
            noteID: UUID(),
            revision: 1,
            text: fullNote,
            selection: selectionRange
        )
        return RefinementRequest(
            snapshot: snapshot,
            languagePolicy: RefineLanguagePolicy(corpusPolicy: languagePolicy)
        )
    }

    var inputLengthBucket: String {
        let count = input.split(whereSeparator: \.isWhitespace).count
        switch count {
        case 0: return "empty"
        case 1: return "1"
        case 2...3: return "2-3"
        case 4...8: return "4-8"
        default: return "9+"
        }
    }

    var primaryLanguageTag: String {
        if let expectedLanguage = expected.expectedLanguage {
            return expectedLanguage
        }
        for tag in tags {
            if ["pt", "en", "es", "mixed"].contains(tag) {
                return tag
            }
        }
        return "unknown"
    }
}

struct RefineEvalSplitsManifest: Codable, Sendable {
    var version: Int
    var seed: String
    var ratios: [String: Double]
    var assignments: [String: RefineEvalSplit]
    var notes: [String: String]
}

struct RefineEvalRunRecord: Codable, Sendable {
    var caseID: String
    var runIndex: Int
    var input: String
    var output: String?
    var decision: RefinementDecision?
    var kind: RefinementKind?
    var latencyMs: Double
    var providerError: String?
    var productionRejection: String?
    var skippedReason: String?
    var promptVersion: String
    var modelIdentifier: String
    var availability: String
    var languageDiagnostics: RefineEvalLanguageDiagnostics?
    var preflightReason: String? = nil
    var protectedLiteralDiagnostics: RefineEvalProtectedLiteralDiagnostics? = nil
}

struct RefineEvalProtectedLiteralDiagnostics: Codable, Sendable, Equatable {
    var validatorEvaluated: Bool
    var validatorRejected: Bool
    var violationReason: RefineProtectedLiteralViolationReason?
    var literalClass: RefineProtectedLiteralClass?
}

enum RefineObjectiveFailureKind: String, Codable, Sendable {
    case languageDrift
    case protectedTokenMutation
    case expansionExceeded
    case unexpectedChange
    case unexpectedNoChange
    case emptyOutput
    case selectionScopeViolation
    case contextLeakage
    case forbiddenContentIntroduced
    case exactOutputMismatch
    case productionGuardRejection
    case providerError
    case skippedNotExecutable
}

struct RefineObjectiveFailure: Codable, Sendable, Equatable {
    var kind: RefineObjectiveFailureKind
    var message: String
    var severity: RefineEvalSeverity
}

struct RefineEvalCaseScore: Codable, Sendable {
    var caseID: String
    var runIndex: Int
    var objectiveFailures: [RefineObjectiveFailure]
    var requiresSemanticReview: Bool
    var semanticReviewReasons: [String]
    var requiresHumanReview: Bool
    var evaluatorDisagreement: Bool
    var languageBehavior: RefineEvalLanguageBehaviorSnapshot?
    var passedObjectively: Bool
    var inputLanguage: String
    var outputLanguage: String?
    var expansionRatio: Double?
    var latencyMs: Double
    var decision: RefinementDecision?

    init(
        caseID: String,
        runIndex: Int,
        objectiveFailures: [RefineObjectiveFailure],
        requiresSemanticReview: Bool,
        semanticReviewReasons: [String],
        requiresHumanReview: Bool = false,
        evaluatorDisagreement: Bool = false,
        languageBehavior: RefineEvalLanguageBehaviorSnapshot? = nil,
        passedObjectively: Bool,
        inputLanguage: String,
        outputLanguage: String?,
        expansionRatio: Double?,
        latencyMs: Double,
        decision: RefinementDecision?
    ) {
        self.caseID = caseID
        self.runIndex = runIndex
        self.objectiveFailures = objectiveFailures
        self.requiresSemanticReview = requiresSemanticReview
        self.semanticReviewReasons = semanticReviewReasons
        self.requiresHumanReview = requiresHumanReview
        self.evaluatorDisagreement = evaluatorDisagreement
        self.languageBehavior = languageBehavior
        self.passedObjectively = passedObjectively
        self.inputLanguage = inputLanguage
        self.outputLanguage = outputLanguage
        self.expansionRatio = expansionRatio
        self.latencyMs = latencyMs
        self.decision = decision
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        caseID = try container.decode(String.self, forKey: .caseID)
        runIndex = try container.decode(Int.self, forKey: .runIndex)
        objectiveFailures = try container.decode([RefineObjectiveFailure].self, forKey: .objectiveFailures)
        requiresSemanticReview = try container.decode(Bool.self, forKey: .requiresSemanticReview)
        semanticReviewReasons = try container.decode([String].self, forKey: .semanticReviewReasons)
        requiresHumanReview = try container.decodeIfPresent(Bool.self, forKey: .requiresHumanReview) ?? false
        evaluatorDisagreement = try container.decodeIfPresent(Bool.self, forKey: .evaluatorDisagreement) ?? false
        languageBehavior = try container.decodeIfPresent(RefineEvalLanguageBehaviorSnapshot.self, forKey: .languageBehavior)
        passedObjectively = try container.decode(Bool.self, forKey: .passedObjectively)
        inputLanguage = try container.decode(String.self, forKey: .inputLanguage)
        outputLanguage = try container.decodeIfPresent(String.self, forKey: .outputLanguage)
        expansionRatio = try container.decodeIfPresent(Double.self, forKey: .expansionRatio)
        latencyMs = try container.decode(Double.self, forKey: .latencyMs)
        decision = try container.decodeIfPresent(RefinementDecision.self, forKey: .decision)
    }
}

struct RefineEvalRunConfiguration: Sendable {
    var split: RefineEvalSplit
    var filterTags: Set<String>
    var filterCategories: Set<String>
    var repetitions: Int
    var criticalStabilityOnly: Bool
    var outputDirectory: URL
    var corpusRoot: URL
    var includeRegression: Bool

    static func defaultCorpusRoot() -> URL {
        let env = ProcessInfo.processInfo.environment["RASC_EVAL_ROOT"]
        if let env, !env.isEmpty {
            return URL(fileURLWithPath: env, isDirectory: true)
        }
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let candidate = cwd.appendingPathComponent("Evals/Refine", isDirectory: true)
        if FileManager.default.fileExists(atPath: candidate.path) {
            return candidate
        }
        // Xcode build products may run from DerivedData; walk up to repo root.
        var url = cwd
        for _ in 0..<8 {
            let probe = url.appendingPathComponent("Evals/Refine", isDirectory: true)
            if FileManager.default.fileExists(atPath: probe.path) {
                return probe
            }
            url.deleteLastPathComponent()
        }
        return candidate
    }
}

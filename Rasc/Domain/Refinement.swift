import Foundation

enum RefinementContentUnitKind: String, Codable, Equatable, Sendable {
    case lexicalWord
    case wordWithAttachedPunctuation
    case url
    case email
    case handle
    case number
    case money
    case emoji
    case technicalIdentifier
    case codeLike
    case mixedAlphanumericIdentifier
}

struct RefinementContentUnitClassifier {
    static func classify(_ text: String) -> RefinementContentUnitKind? {
        let candidate = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else { return nil }

        // A money amount is one structural unit even when its currency marker and
        // value are separated by whitespace. No other multi-part form is joined.
        if matches(candidate, pattern: #"^(?:R\$|US\$|[$€£¥])(?:\s*[+-]?(?:\d+(?:[.,]\d+)*))?$"#) {
            return .money
        }

        guard candidate.split(whereSeparator: { $0.isWhitespace }).count == 1 else {
            return nil
        }

        return classifyUnspaced(candidate, allowsAttachedPunctuation: true)
    }

    private static func classifyUnspaced(
        _ candidate: String,
        allowsAttachedPunctuation: Bool
    ) -> RefinementContentUnitKind? {
        if matches(candidate, pattern: #"(?i)^(?:https?://|www\.)\S+$"#) {
            return .url
        }
        if matches(candidate, pattern: #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#) {
            return .email
        }
        if matches(candidate, pattern: #"^@[\p{L}\p{M}\p{N}_][\p{L}\p{M}\p{N}_.-]*$"#) {
            return .handle
        }
        if matches(candidate, pattern: #"^(?:R\$|US\$|[$€£¥])(?:[+-]?(?:\d+(?:[.,]\d+)*))?$"#) {
            return .money
        }
        if matches(candidate, pattern: #"^[+-]?(?:\d+(?:[.,]\d+)*)$"#) {
            return .number
        }
        if isEmojiSequence(candidate) {
            return .emoji
        }
        if matches(candidate, pattern: #"^[\p{L}\p{M}]+(?:['’\-][\p{L}\p{M}]+)*$"#) {
            return .lexicalWord
        }
        if matches(candidate, pattern: #"^(?=.*[\p{L}\p{N}])(?=.*[_\.])[\p{L}\p{M}\p{N}_.-]+$"#) {
            return .technicalIdentifier
        }
        if matches(candidate, pattern: #"^(?=.*\p{L})(?=.*\p{N})[\p{L}\p{M}\p{N}-]+$"#) {
            return .mixedAlphanumericIdentifier
        }
        if allowsAttachedPunctuation {
            let attachedPunctuation = CharacterSet(charactersIn: "?!.,:;()[]{}<>'\"“”‘’")
            let core = candidate.trimmingCharacters(in: attachedPunctuation)
            if core != candidate,
               !core.isEmpty,
               classifyUnspaced(core, allowsAttachedPunctuation: false) != nil {
                return .wordWithAttachedPunctuation
            }
        }
        if containsLetterOrNumber(candidate), containsCodeSymbol(candidate) {
            return .codeLike
        }

        guard allowsAttachedPunctuation else { return nil }
        let core = candidate.trimmingCharacters(in: .punctuationCharacters)
        guard core != candidate,
              !core.isEmpty,
              classifyUnspaced(core, allowsAttachedPunctuation: false) != nil
        else {
            return nil
        }
        return .wordWithAttachedPunctuation
    }

    private static func matches(_ text: String, pattern: String) -> Bool {
        text.range(of: pattern, options: .regularExpression) != nil
    }

    private static func containsLetterOrNumber(_ text: String) -> Bool {
        text.unicodeScalars.contains {
            CharacterSet.alphanumerics.contains($0)
        }
    }

    private static func containsCodeSymbol(_ text: String) -> Bool {
        text.unicodeScalars.contains {
            CharacterSet.symbols.contains($0) || CharacterSet.punctuationCharacters.contains($0)
        }
    }

    private static func isEmojiSequence(_ text: String) -> Bool {
        var hasEmoji = false
        for scalar in text.unicodeScalars {
            if scalar.properties.isEmojiPresentation
                || (scalar.properties.isEmoji && scalar.value >= 0x238C) {
                hasEmoji = true
                continue
            }
            if scalar.value == 0x200D
                || scalar.value == 0xFE0F
                || (0x1F3FB...0x1F3FF).contains(scalar.value) {
                continue
            }
            return false
        }
        return hasEmoji
    }
}

enum RefinementPreflightReason: String, Codable, Equatable, Sendable {
    case wholeNoteSingleContentUnit = "whole_note_single_content_unit"
}

enum RefinementPreflightOutcome: Equatable, Sendable {
    case proceed
    case noChange(RefinementPreflightReason)
}

struct RefinementPreflightPolicy {
    static func evaluate(_ request: RefinementRequest) -> RefinementPreflightOutcome {
        guard request.scope == .wholeNote,
              RefinementContentUnitClassifier.classify(request.inputText) != nil
        else {
            return .proceed
        }
        return .noChange(.wholeNoteSingleContentUnit)
    }

    static func result(for request: RefinementRequest) -> RefinementResult? {
        guard case .noChange = evaluate(request) else { return nil }
        return RefinementResult(
            decision: .noChange,
            kind: .alreadyGood,
            text: request.inputText
        )
    }
}

struct NoteSnapshot: Equatable, Sendable {
    let noteID: UUID
    let revision: Int
    let text: String
    let selection: Range<String.Index>?

    init(
        noteID: UUID,
        revision: Int,
        text: String,
        selection: Range<String.Index>? = nil
    ) {
        self.noteID = noteID
        self.revision = revision
        self.text = text
        self.selection = Self.validSelection(selection, in: text)
    }

    var selectedText: String? {
        selection.map { String(text[$0]) }
    }

    private static func validSelection(
        _ selection: Range<String.Index>?,
        in text: String
    ) -> Range<String.Index>? {
        guard let selection,
              !selection.isEmpty,
              let lowerBound = selection.lowerBound.samePosition(in: text),
              let upperBound = selection.upperBound.samePosition(in: text),
              lowerBound <= upperBound
        else {
            return nil
        }

        return lowerBound..<upperBound
    }
}

struct RefinementRequest: Equatable, Sendable {
    private static let selectionContextWindowCharacters = 100
    private static let minimumSelectionReplacementCharacters = 48
    private static let selectionReplacementMultiplier = 4
    private static let minimumSelectionContextMatchCharacters = 12

    let requestID: UUID
    let snapshot: NoteSnapshot
    let scope: RefinementScope
    let inputText: String
    let languagePolicy: RefineLanguagePolicy

    init(
        requestID: UUID = UUID(),
        snapshot: NoteSnapshot,
        languagePolicy: RefineLanguagePolicy = .productionDefault
    ) {
        self.requestID = requestID
        self.snapshot = snapshot
        self.languagePolicy = languagePolicy
        scope = snapshot.selection == nil ? .wholeNote : .selection
        inputText = snapshot.selectedText ?? snapshot.text
    }

    var selectionContext: SelectionRefinementContext? {
        guard scope == .selection, let selection = snapshot.selection else { return nil }
        return SelectionRefinementContext(
            before: String(
                snapshot.text[..<selection.lowerBound].suffix(Self.selectionContextWindowCharacters)
            ),
            selected: inputText,
            after: String(
                snapshot.text[selection.upperBound...].prefix(Self.selectionContextWindowCharacters)
            )
        )
    }

    func allowsChangedText(_ text: String) -> Bool {
        guard scope == .selection else { return true }
        return text.count <= max(
            Self.minimumSelectionReplacementCharacters,
            inputText.count * Self.selectionReplacementMultiplier
        )
    }

    func isReplacementOnly(_ text: String) -> Bool {
        guard scope == .selection, let selection = snapshot.selection else { return true }
        guard text != snapshot.text else { return false }

        let contextMatchCharacters = max(
            Self.minimumSelectionContextMatchCharacters,
            inputText.count / 2
        )
        let precedingContext = String(snapshot.text[..<selection.lowerBound])
        let followingContext = String(snapshot.text[selection.upperBound...])

        return !Self.containsUnchangedContext(
            in: text,
            context: precedingContext,
            minimumCharacters: contextMatchCharacters
        ) && !Self.containsUnchangedContext(
            in: text,
            context: followingContext,
            minimumCharacters: contextMatchCharacters
        )
    }

    private static func containsUnchangedContext(
        in replacement: String,
        context: String,
        minimumCharacters: Int
    ) -> Bool {
        let characters = Array(context)
        guard characters.count >= minimumCharacters else { return false }

        for start in 0...(characters.count - minimumCharacters) {
            let end = start + minimumCharacters
            if replacement.contains(String(characters[start..<end])) {
                return true
            }
        }

        return false
    }

    func isCurrent(noteID: UUID, revision: Int, requestID: UUID) -> Bool {
        snapshot.noteID == noteID
            && snapshot.revision == revision
            && self.requestID == requestID
    }
}

struct SelectionRefinementContext: Equatable, Sendable {
    let before: String
    let selected: String
    let after: String
}

enum RefinementScope: String, Codable, Equatable, Sendable {
    case wholeNote
    case selection
}

enum RefinementKind: String, Codable, Equatable, Sendable {
    case messyText
    case tasks
    case meeting
    case idea
    case message
    case technical
    case alreadyGood
    case unknown
}

enum RefinementDecision: String, Codable, Equatable, Sendable {
    case changed
    case noChange
}

struct RefinementResult: Codable, Equatable, Sendable {
    let decision: RefinementDecision
    let kind: RefinementKind
    let text: String
    let languageTrace: RefinementLanguageTrace?
    let protectedLiteralTrace: RefinementProtectedLiteralTrace?

    init(
        decision: RefinementDecision,
        kind: RefinementKind,
        text: String,
        languageTrace: RefinementLanguageTrace? = nil,
        protectedLiteralTrace: RefinementProtectedLiteralTrace? = nil
    ) {
        self.decision = decision
        self.kind = kind
        self.text = text
        self.languageTrace = languageTrace
        self.protectedLiteralTrace = protectedLiteralTrace
    }
}

enum RefinementUnavailableReason: Equatable, Sendable {
    case deviceNotEligible
    case appleIntelligenceNotEnabled
    case modelNotReady
    case unsupportedEnvironment
    case unknown
}

enum RefinementAvailability: Equatable, Sendable {
    case available
    case unavailable(RefinementUnavailableReason)

    var diagnosticLabel: String {
        switch self {
        case .available:
            "available"
        case .unavailable(.appleIntelligenceNotEnabled):
            "unavailable.appleIntelligenceNotEnabled"
        case .unavailable(.deviceNotEligible):
            "unavailable.deviceNotEligible"
        case .unavailable(.modelNotReady):
            "unavailable.modelNotReady"
        case .unavailable(.unsupportedEnvironment):
            "unavailable.unsupportedEnvironment"
        case .unavailable(.unknown):
            "unavailable.unknown"
        }
    }
}

enum RefinementError: Error, Equatable, Sendable {
    case unavailable(RefinementUnavailableReason)
    case contextTooLarge
    case unsupportedLanguage
    case invalidOutput
    case providerFailure
}

enum RefinementMessage: Equatable, Sendable {
    case alreadyUseful
    case unavailable(RefinementUnavailableReason)
    case contextTooLarge
    case couldNotRefine
    case couldNotSafelyRefineSelection
    case couldNotSaveRefinement
    case nothingToRefine
    case multipleSelection

    var text: String {
        switch self {
        case .alreadyUseful:
            "This note is already useful."
        case .unavailable(.appleIntelligenceNotEnabled):
            "Turn on Apple Intelligence in System Settings to use Refine."
        case .unavailable(.deviceNotEligible):
            "Refine requires a Mac that supports Apple Intelligence."
        case .unavailable(.modelNotReady):
            "Apple Intelligence is still preparing its on-device model. Try again later."
        case .unavailable(.unknown):
            "Refine is unavailable right now. Capture and Keep still work."
        case .unavailable(.unsupportedEnvironment):
            "Refine needs macOS 26 or later and Apple Intelligence. Capture and Keep still work."
        case .contextTooLarge:
            "This note is too long to refine at once. Select a smaller section."
        case .couldNotRefine:
            "Couldn't refine this note."
        case .couldNotSafelyRefineSelection:
            "Couldn't safely refine this selection."
        case .couldNotSaveRefinement:
            "Couldn't save this refinement."
        case .nothingToRefine:
            "Nothing to refine."
        case .multipleSelection:
            "Select one section to refine at a time."
        }
    }

    var isTransient: Bool {
        self == .alreadyUseful || self == .nothingToRefine
    }
}

struct RefinementMetadata: Equatable, Sendable {
    let provider: String
    let modelIdentifier: String
    let promptVersion: String
}

struct RefinementPreview: Equatable, Sendable {
    let request: RefinementRequest
    let result: RefinementResult
    let metadata: RefinementMetadata

    var proposedNoteText: String {
        guard let selection = request.snapshot.selection else { return result.text }
        var text = request.snapshot.text
        text.replaceSubrange(selection, with: result.text)
        return text
    }
}

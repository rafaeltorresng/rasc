import Foundation

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

    init(requestID: UUID = UUID(), snapshot: NoteSnapshot) {
        self.requestID = requestID
        self.snapshot = snapshot
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
        case .unavailable(.unsupportedEnvironment), .unavailable(.unknown):
            "Refine is currently unavailable."
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
}

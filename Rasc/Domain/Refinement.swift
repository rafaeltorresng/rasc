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
    let requestID: UUID
    let snapshot: NoteSnapshot
    let inputText: String

    init(requestID: UUID = UUID(), snapshot: NoteSnapshot) {
        self.requestID = requestID
        self.snapshot = snapshot
        inputText = snapshot.selectedText ?? snapshot.text
    }

    func isCurrent(noteID: UUID, revision: Int, requestID: UUID) -> Bool {
        snapshot.noteID == noteID
            && snapshot.revision == revision
            && self.requestID == requestID
    }
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

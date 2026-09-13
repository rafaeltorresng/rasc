import Foundation
import Testing
@testable import Rasc

@Suite
struct RefinementContractTests {
    @Test
    func detectsCurrentAndStaleRequestsFromImmutableIdentity() {
        let noteID = UUID()
        let requestID = UUID()
        let request = RefinementRequest(
            requestID: requestID,
            snapshot: NoteSnapshot(
                noteID: noteID,
                revision: 7,
                text: "maybe retry after queue tick"
            )
        )

        #expect(request.isCurrent(noteID: noteID, revision: 7, requestID: requestID))
        #expect(!request.isCurrent(noteID: noteID, revision: 8, requestID: requestID))
        #expect(!request.isCurrent(noteID: UUID(), revision: 7, requestID: requestID))
        #expect(!request.isCurrent(noteID: noteID, revision: 7, requestID: UUID()))
    }

    @Test
    func snapshotsTheSelectedTextWithoutSplittingUnicodeCharacters() throws {
        var editorText = "Antes: café 👩🏽‍💻 com João amanhã. Depois."
        let selection = try #require(editorText.range(of: "café 👩🏽‍💻 com João amanhã"))
        let snapshot = NoteSnapshot(
            noteID: UUID(),
            revision: 3,
            text: editorText,
            selection: selection
        )
        let request = RefinementRequest(requestID: UUID(), snapshot: snapshot)

        editorText = "The editor changed while Refine was running."

        #expect(request.inputText == "café 👩🏽‍💻 com João amanhã")
        #expect(request.snapshot.text == "Antes: café 👩🏽‍💻 com João amanhã. Depois.")
        #expect(request.snapshot.selection == selection)
        #expect(request.snapshot.selectedText == "café 👩🏽‍💻 com João amanhã")
    }

    @Test
    func usesTheWholeUnicodeTextWhenThereIsNoSelection() {
        let text = "Hipótese: falha em next_retry_at — não confirmada 🧪"
        let request = RefinementRequest(
            requestID: UUID(),
            snapshot: NoteSnapshot(noteID: UUID(), revision: 1, text: text)
        )

        #expect(request.inputText == text)
        #expect(request.snapshot.selectedText == nil)
    }

    @Test
    func treatsAUnicodeCaretAsNoSelection() {
        let text = "Revisar café 👩🏽‍💻 depois"
        let caret = text.index(text.startIndex, offsetBy: 13)
        let request = RefinementRequest(
            requestID: UUID(),
            snapshot: NoteSnapshot(
                noteID: UUID(),
                revision: 2,
                text: text,
                selection: caret..<caret
            )
        )

        #expect(request.snapshot.selection == nil)
        #expect(request.snapshot.selectedText == nil)
        #expect(request.inputText == text)
    }

    @Test
    func rejectsASelectionThatIsNotValidWithinTheSnapshotText() {
        let text = "café"
        let otherText = "0123456789"
        let lowerBound = otherText.index(otherText.startIndex, offsetBy: 6)
        let upperBound = otherText.index(otherText.startIndex, offsetBy: 8)
        let request = RefinementRequest(
            requestID: UUID(),
            snapshot: NoteSnapshot(
                noteID: UUID(),
                revision: 4,
                text: text,
                selection: lowerBound..<upperBound
            )
        )

        #expect(request.snapshot.selection == nil)
        #expect(request.snapshot.selectedText == nil)
        #expect(request.inputText == text)
    }

    @Test
    func modelsChangedAndNoChangeResultsWithoutExplanatoryMetadata() {
        let changed = RefinementResult(
            decision: .changed,
            kind: .tasks,
            text: "- [ ] Inspect the logs."
        )
        let unchanged = RefinementResult(
            decision: .noChange,
            kind: .alreadyGood,
            text: "Send the contract tomorrow."
        )

        #expect(changed.decision == .changed)
        #expect(changed.kind == .tasks)
        #expect(unchanged.decision == .noChange)
        #expect(unchanged.kind == .alreadyGood)
        #expect(unchanged.text == "Send the contract tomorrow.")
    }

    @Test
    func loadsTheVersionedRepresentativeEvalDataset() throws {
        let url = try #require(
            Bundle(for: RefinementContractBundleToken.self).url(
                forResource: "RefinementEvals.v1",
                withExtension: "json"
            )
        )
        let dataset = try JSONDecoder().decode(
            RefinementEvalDataset.self,
            from: Data(contentsOf: url)
        )

        #expect(dataset.version == 1)
        #expect(dataset.cases.count == 9)
        #expect(Set(dataset.cases.map(\.id)).count == dataset.cases.count)
        #expect(Set(dataset.cases.map(\.language)) == ["pt", "en", "mixed"])
        #expect(Set(dataset.cases.map(\.expectedKind)).isSuperset(of: [
            .messyText,
            .tasks,
            .meeting,
            .message,
            .technical,
            .alreadyGood,
        ]))
        #expect(dataset.cases.contains { $0.expectsNoChange })
        #expect(dataset.cases.allSatisfy { !$0.input.isEmpty })
        #expect(dataset.cases.allSatisfy {
            !$0.mustPreserve.isEmpty || !$0.mustNotIntroduce.isEmpty || $0.expectsNoChange
        })
    }
}

private final class RefinementContractBundleToken {}

private struct RefinementEvalDataset: Decodable {
    let version: Int
    let cases: [RefinementEvalCase]
}

private struct RefinementEvalCase: Decodable {
    let id: String
    let language: String
    let input: String
    let expectedKind: RefinementKind
    let mustPreserve: [String]
    let mustNotIntroduce: [String]
    let expectsNoChange: Bool
}

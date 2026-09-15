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
        #expect(request.scope == .selection)
        #expect(request.snapshot.text == "Antes: café 👩🏽‍💻 com João amanhã. Depois.")
        #expect(request.snapshot.selection == selection)
        #expect(request.snapshot.selectedText == "café 👩🏽‍💻 com João amanhã")
    }

    @Test
    func selectionContextUsesOnlyUnicodeSafeLocalWindows() throws {
        let before = String(repeating: "a", count: 120)
        let selected = "café 👩🏽‍💻"
        let after = String(repeating: "b", count: 120)
        let text = before + selected + after
        let selection = try #require(text.range(of: selected))
        let request = RefinementRequest(
            snapshot: NoteSnapshot(noteID: UUID(), revision: 1, text: text, selection: selection)
        )
        let context = try #require(request.selectionContext)

        #expect(context.before == String(repeating: "a", count: 100))
        #expect(context.selected == selected)
        #expect(context.after == String(repeating: "b", count: 100))
    }

    @Test
    func usesTheWholeUnicodeTextWhenThereIsNoSelection() {
        let text = "Hipótese: falha em next_retry_at — não confirmada 🧪"
        let request = RefinementRequest(
            requestID: UUID(),
            snapshot: NoteSnapshot(noteID: UUID(), revision: 1, text: text)
        )

        #expect(request.inputText == text)
        #expect(request.scope == .wholeNote)
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
    func modelsDynamicProviderAvailabilityWithoutCloudFallback() {
        #expect(RefinementAvailability.available == .available)
        #expect(RefinementAvailability.unavailable(.deviceNotEligible) != .available)
        #expect(RefinementAvailability.unavailable(.appleIntelligenceNotEnabled) != .available)
        #expect(RefinementAvailability.unavailable(.modelNotReady) != .available)
        #expect(RefinementAvailability.unavailable(.unsupportedEnvironment) != .available)
        #expect(RefinementAvailability.unavailable(.unknown) != .available)
    }

    @Test
    func capturesProviderAndPromptIdentityForAcceptedRevisions() {
        let metadata = RefinementMetadata(
            provider: "foundation-models",
            modelIdentifier: "system-language-model.default",
            promptVersion: "refine-v1"
        )

        #expect(metadata.provider == "foundation-models")
        #expect(metadata.modelIdentifier == "system-language-model.default")
        #expect(metadata.promptVersion == "refine-v1")
    }

    @Test
    func unavailableReasonsHaveConciseActionableMessages() {
        #expect(RefinementMessage.unavailable(.appleIntelligenceNotEnabled).text ==
            "Turn on Apple Intelligence in System Settings to use Refine.")
        #expect(RefinementMessage.unavailable(.deviceNotEligible).text ==
            "Refine requires a Mac that supports Apple Intelligence.")
        #expect(RefinementMessage.unavailable(.modelNotReady).text ==
            "Apple Intelligence is still preparing its on-device model. Try again later.")
        #expect(RefinementMessage.unavailable(.unsupportedEnvironment).text ==
            "Refine is currently unavailable.")
        #expect(RefinementMessage.unavailable(.unknown).text ==
            "Refine is currently unavailable.")
        #expect(RefinementMessage.couldNotSafelyRefineSelection.text ==
            "Couldn't safely refine this selection.")
        #expect(RefinementMessage.couldNotSaveRefinement.text ==
            "Couldn't save this refinement.")
    }

    @Test
    func availabilityDiagnosticLabelsContainOnlyTheAvailabilityCase() {
        #expect(RefinementAvailability.available.diagnosticLabel == "available")
        #expect(RefinementAvailability.unavailable(.appleIntelligenceNotEnabled).diagnosticLabel ==
            "unavailable.appleIntelligenceNotEnabled")
        #expect(RefinementAvailability.unavailable(.deviceNotEligible).diagnosticLabel ==
            "unavailable.deviceNotEligible")
        #expect(RefinementAvailability.unavailable(.modelNotReady).diagnosticLabel ==
            "unavailable.modelNotReady")
        #expect(RefinementAvailability.unavailable(.unsupportedEnvironment).diagnosticLabel ==
            "unavailable.unsupportedEnvironment")
        #expect(RefinementAvailability.unavailable(.unknown).diagnosticLabel ==
            "unavailable.unknown")
    }

    @Test
    func previewKeepsTheImmutableRequestAndStructuredResultTogether() {
        let request = RefinementRequest(
            requestID: UUID(),
            snapshot: NoteSnapshot(noteID: UUID(), revision: 2, text: "rough note")
        )
        let result = RefinementResult(decision: .changed, kind: .messyText, text: "Clear note.")
        let metadata = RefinementMetadata(
            provider: "fake",
            modelIdentifier: "fake-v1",
            promptVersion: "refine-v1"
        )

        let preview = RefinementPreview(request: request, result: result, metadata: metadata)

        #expect(preview.request == request)
        #expect(preview.result == result)
        #expect(preview.metadata == metadata)
    }

    @Test
    func selectionScopeKeepsOnlyLocalReadOnlyContext() throws {
        let fullNote = "ola tudobem como vc ta?"
        let selection = try #require(fullNote.range(of: "ola tudobem"))
        let request = RefinementRequest(
            snapshot: NoteSnapshot(noteID: UUID(), revision: 1, text: fullNote, selection: selection)
        )

        #expect(request.scope == .selection)
        #expect(request.inputText == "ola tudobem")
        #expect(request.snapshot.text == fullNote)
        let context = try #require(request.selectionContext)
        #expect(context.before == "")
        #expect(context.selected == "ola tudobem")
        #expect(context.after == " como vc ta?")
    }

    @Test
    func selectionScopeRejectsClearlyDisproportionateReplacementButWholeNoteDoesNot() throws {
        let fullNote = "ola tudobem como vc ta?"
        let selection = try #require(fullNote.range(of: "ola tudobem"))
        let selectionRequest = RefinementRequest(
            snapshot: NoteSnapshot(noteID: UUID(), revision: 1, text: fullNote, selection: selection)
        )
        let wholeNoteRequest = RefinementRequest(
            snapshot: NoteSnapshot(noteID: UUID(), revision: 1, text: fullNote)
        )
        let runaway = String(repeating: "Hello, everyone! ", count: 30)

        #expect(!selectionRequest.allowsChangedText(runaway))
        #expect(wholeNoteRequest.allowsChangedText(runaway))
    }

    @Test
    func shortSelectionRejectsParagraphSizedReplacement() throws {
        let fullNote = "A short text note."
        let selection = try #require(fullNote.range(of: "short text"))
        let request = RefinementRequest(
            snapshot: NoteSnapshot(noteID: UUID(), revision: 1, text: fullNote, selection: selection)
        )

        #expect(request.inputText.count == 10)
        #expect(!request.allowsChangedText(String(repeating: "x", count: 200)))
    }

    @Test
    func selectionReplacementRejectsUnchangedSurroundingContext() throws {
        let fullNote = "ola tudobem como vc ta?"
        let selection = try #require(fullNote.range(of: "ola tudobem"))
        let selectionRequest = RefinementRequest(
            snapshot: NoteSnapshot(noteID: UUID(), revision: 1, text: fullNote, selection: selection)
        )
        let wholeNoteRequest = RefinementRequest(
            snapshot: NoteSnapshot(noteID: UUID(), revision: 1, text: fullNote)
        )

        #expect(!selectionRequest.isReplacementOnly(fullNote))
        #expect(!selectionRequest.isReplacementOnly("Olá, tudo bem como vc ta?"))
        #expect(selectionRequest.isReplacementOnly("Olá, tudo bem"))
        #expect(wholeNoteRequest.isReplacementOnly(fullNote))
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
        #expect(dataset.cases.count == 21)
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
        let selectionCases = dataset.cases.filter { $0.scope == .selection }
        #expect(selectionCases.count == 6)
        #expect(selectionCases.allSatisfy { $0.fullNote != nil && $0.selection != nil })
        let reportedCase = try #require(
            selectionCases.first(where: { $0.id == "selection-pt-ola-tudobem-001" })
        )
        #expect(reportedCase.fullNote == "ola tudobem como vc ta?")
        #expect(reportedCase.selection == "ola tudobem")
        let planningCase = try #require(
            dataset.cases.first(where: { $0.id == "planning-abbreviated-pt-001" })
        )
        #expect(planningCase.input ==
            "trocar nums narrativos por algo como de x itens/conteudos, y% das narrativas sao pos/neg")
        #expect(planningCase.mustPreserve.contains("x"))
        #expect(planningCase.mustPreserve.contains("y%"))
        let slangCase = try #require(
            dataset.cases.first(where: { $0.id == "casual-slang-pt-001" })
        )
        #expect(slangCase.input == "dale rapaziada, qual a boa?")
        #expect(slangCase.expectsNoChange)
        let intentionalCasualCase = try #require(
            dataset.cases.first(where: { $0.id == "casual-intentional-pt-001" })
        )
        #expect(intentionalCasualCase.expectsNoChange)
        let telegraphicWorkCase = try #require(
            dataset.cases.first(where: { $0.id == "telegraphic-work-note-pt-001" })
        )
        #expect(!telegraphicWorkCase.expectsNoChange)
        #expect(telegraphicWorkCase.mustPreserve.contains("talvez"))
        let formalCase = try #require(
            dataset.cases.first(where: { $0.id == "formal-clear-pt-001" })
        )
        #expect(formalCase.expectsNoChange)
        let ambiguousCase = try #require(
            dataset.cases.first(where: { $0.id == "ambiguous-fragment-pt-001" })
        )
        #expect(ambiguousCase.expectsNoChange)
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
    let scope: RefinementScope?
    let fullNote: String?
    let selection: String?
}

import Foundation
import Testing
@testable import Rasc

@Suite
struct RefinementContractTests {
    @Test(arguments: [
        ("deploy", RefinementContentUnitKind.lexicalWord),
        ("deploy?", RefinementContentUnitKind.wordWithAttachedPunctuation),
        ("(deploy)", RefinementContentUnitKind.wordWithAttachedPunctuation),
        ("https://example.com/path?q=1", RefinementContentUnitKind.url),
        ("ana@example.com", RefinementContentUnitKind.email),
        ("@rafa", RefinementContentUnitKind.handle),
        ("R$", RefinementContentUnitKind.money),
        ("R$12,50", RefinementContentUnitKind.money),
        ("R$ 12,50", RefinementContentUnitKind.money),
        ("42", RefinementContentUnitKind.number),
        ("foo_bar", RefinementContentUnitKind.technicalIdentifier),
        ("C++", RefinementContentUnitKind.codeLike),
        ("Q3", RefinementContentUnitKind.mixedAlphanumericIdentifier),
        ("👍", RefinementContentUnitKind.emoji),
        ("👩🏽‍💻", RefinementContentUnitKind.emoji),
    ])
    func classifiesExactlyOneStructuralContentUnit(
        input: String,
        expectedKind: RefinementContentUnitKind
    ) {
        #expect(RefinementContentUnitClassifier.classify(input) == expectedKind)
    }

    @Test(arguments: [
        "",
        "   \n\t",
        "???",
        "deploy retry",
        "normal sentence here",
        "API retry",
    ])
    func doesNotClassifyEmptyPunctuationOnlyOrMultipleUnitsAsOneContentUnit(input: String) {
        #expect(RefinementContentUnitClassifier.classify(input) == nil)
    }

    @Test
    func preflightReturnsTheExistingNoChangeContractForAWholeNoteSingleUnit() throws {
        let request = RefinementRequest(
            snapshot: NoteSnapshot(noteID: UUID(), revision: 1, text: "deploy?")
        )

        let decision = RefinementPreflightPolicy.evaluate(request)
        let result = try #require(RefinementPreflightPolicy.result(for: request))

        #expect(decision == .noChange(.wholeNoteSingleContentUnit))
        #expect(result == RefinementResult(
            decision: .noChange,
            kind: .alreadyGood,
            text: request.inputText
        ))
    }

    @Test
    func preflightNeverGatesASingleUnitSelection() throws {
        let text = "Keep deploy available for selection refinement."
        let selection = try #require(text.range(of: "deploy"))
        let request = RefinementRequest(
            snapshot: NoteSnapshot(noteID: UUID(), revision: 1, text: text, selection: selection)
        )

        #expect(RefinementPreflightPolicy.evaluate(request) == .proceed)
        #expect(RefinementPreflightPolicy.result(for: request) == nil)
    }

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
    func selectionDuplicateContextGuardRejectsRegressionCase() throws {
        let fullNote = "call retry later then retry again"
        let selection = try #require(fullNote.range(of: "retry"))
        let request = RefinementRequest(
            snapshot: NoteSnapshot(noteID: UUID(), revision: 1, text: fullNote, selection: selection)
        )

        #expect(request.hasDuplicateContextLeak("retry again"))
    }

    @Test
    func selectionDuplicateContextGuardAllowsLegitimateExpansionWhenNotCopiedFromContext() throws {
        let fullNote = "call retry later then retry workflow"
        let selection = try #require(fullNote.range(of: "retry"))
        let request = RefinementRequest(
            snapshot: NoteSnapshot(noteID: UUID(), revision: 1, text: fullNote, selection: selection)
        )

        #expect(!request.hasDuplicateContextLeak("retry logic"))
    }

    @Test
    func selectionDuplicateContextGuardRejectsLeakFromEarlierOccurrence() throws {
        let fullNote = "retry again then call retry"
        let selection = try #require(fullNote.range(of: "retry", range: fullNote.range(of: "then call ")!.upperBound..<fullNote.endIndex))
        let request = RefinementRequest(
            snapshot: NoteSnapshot(noteID: UUID(), revision: 1, text: fullNote, selection: selection)
        )

        #expect(request.hasDuplicateContextLeak("retry again"))
    }

    @Test
    func selectionDuplicateContextGuardRejectsLeakFromLaterOccurrence() throws {
        let fullNote = "call retry later then retry again"
        let selection = try #require(fullNote.range(of: "retry"))
        let request = RefinementRequest(
            snapshot: NoteSnapshot(noteID: UUID(), revision: 1, text: fullNote, selection: selection)
        )

        #expect(request.hasDuplicateContextLeak("retry again"))
    }

    @Test
    func selectionDuplicateContextGuardRejectsWhenAnyForeignDuplicateMatches() throws {
        let fullNote = "retry now, retry later, retry again"
        let selection = try #require(fullNote.range(of: "retry"))
        let request = RefinementRequest(
            snapshot: NoteSnapshot(noteID: UUID(), revision: 1, text: fullNote, selection: selection)
        )

        #expect(request.hasDuplicateContextLeak("retry again"))
    }

    @Test
    func selectionDuplicateContextGuardCatchesImportsShorterThanReplacementOnlyMinimum() throws {
        let fullNote = "call retry later then retry again"
        let selection = try #require(fullNote.range(of: "retry"))
        let request = RefinementRequest(
            snapshot: NoteSnapshot(noteID: UUID(), revision: 1, text: fullNote, selection: selection)
        )

        #expect(request.isReplacementOnly("retry again"))
        #expect(request.hasDuplicateContextLeak("retry again"))
    }

    @Test
    func selectionDuplicateContextGuardDoesNotTreatEmbeddedSubstringAsDuplicateOccurrence() throws {
        let fullNote = "catalog review"
        let selection = try #require(fullNote.range(of: "log"))
        let request = RefinementRequest(
            snapshot: NoteSnapshot(noteID: UUID(), revision: 1, text: fullNote, selection: selection)
        )

        #expect(RefinementSelectionDuplicateContextGuard.standaloneOccurrences(of: "log", in: fullNote).isEmpty)
        #expect(!request.hasDuplicateContextLeak("logic"))
    }

    @Test
    func selectionDuplicateContextGuardRespectsPunctuationBoundaries() throws {
        let fullNote = "word, then word, again"
        let selection = try #require(fullNote.range(of: "word,"))
        let request = RefinementRequest(
            snapshot: NoteSnapshot(noteID: UUID(), revision: 1, text: fullNote, selection: selection)
        )

        #expect(request.hasDuplicateContextLeak("word, again"))
    }

    @Test
    func selectionDuplicateContextGuardDetectsDuplicateOccurrenceOnAnotherLine() throws {
        let fullNote = "line one\nretry\nline three\nretry again"
        let selection = try #require(fullNote.range(of: "retry"))
        let request = RefinementRequest(
            snapshot: NoteSnapshot(noteID: UUID(), revision: 1, text: fullNote, selection: selection)
        )

        #expect(request.hasDuplicateContextLeak("retry again"))
    }

    @Test
    func selectionDuplicateContextGuardDoesNotApplyToWholeNoteRefine() throws {
        let request = RefinementRequest(
            snapshot: NoteSnapshot(noteID: UUID(), revision: 1, text: "call retry later then retry again")
        )

        #expect(request.scope == .wholeNote)
        #expect(!request.hasDuplicateContextLeak("retry again"))
    }

    @Test
    func selectionDuplicateContextGuardAllowsExistingGoodSelectionCleanup() throws {
        let fullNote = "ola tudobem como vc ta?"
        let selection = try #require(fullNote.range(of: "ola tudobem"))
        let request = RefinementRequest(
            snapshot: NoteSnapshot(noteID: UUID(), revision: 1, text: fullNote, selection: selection)
        )

        #expect(!request.hasDuplicateContextLeak("Olá, tudo bem"))
    }

    @Test(arguments: [
        ("docs https://rasc.app/a", "Docs: https://rasc.app/a.", RefineProtectedLiteralClass.url),
        ("email ana@acme.com", "Email: ana@acme.com.", RefineProtectedLiteralClass.email),
        ("ping @rafa tomorrow", "Ping @rafa tomorrow.", RefineProtectedLiteralClass.handle),
        ("check next_retry_at", "Check next_retry_at.", RefineProtectedLiteralClass.identifier),
        ("check retryCount", "Check retryCount.", RefineProtectedLiteralClass.identifier),
        ("inspect URLSession", "Inspect URLSession.", RefineProtectedLiteralClass.identifier),
        ("run worker.retry()", "Run worker.retry().", RefineProtectedLiteralClass.codeLike),
        ("check /api/v2/export", "Check /api/v2/export.", RefineProtectedLiteralClass.codeLike),
        ("ship \"release-42\"", "Ship \"release-42\".", RefineProtectedLiteralClass.quotedLiteral),
        ("id 550e8400-e29b-41d4-a716-446655440000", "ID: 550e8400-e29b-41d4-a716-446655440000.", RefineProtectedLiteralClass.opaqueID),
        ("retry 500 tomorrow", "Retry 500 tomorrow.", RefineProtectedLiteralClass.integer),
    ])
    func exactProtectedLiteralValidatorAcceptsPreservedValues(
        source: String,
        proposal: String,
        expectedClass: RefineProtectedLiteralClass
    ) {
        let outcome = RefineProtectedLiteralValidator.validate(source: source, proposal: proposal)
        #expect(outcome == .valid)
        #expect(RefineProtectedLiteralValidator.extract(from: source).contains { $0.literalClass == expectedClass })
    }

    @Test(arguments: [
        ("docs https://rasc.app/a", "Docs are available.", RefineProtectedLiteralClass.url, RefineProtectedLiteralViolationReason.dropped),
        ("docs https://rasc.app/a", "Docs: https://rasc.app/b.", RefineProtectedLiteralClass.url, RefineProtectedLiteralViolationReason.mutated),
        ("email ana@acme.com", "Send the email.", RefineProtectedLiteralClass.email, RefineProtectedLiteralViolationReason.dropped),
        ("ping @rafa tomorrow", "Ping @raf tomorrow.", RefineProtectedLiteralClass.handle, RefineProtectedLiteralViolationReason.mutated),
        ("check next_retry_at", "Check retry tomorrow.", RefineProtectedLiteralClass.identifier, RefineProtectedLiteralViolationReason.dropped),
        ("check retryCount", "Check retryCounter.", RefineProtectedLiteralClass.identifier, RefineProtectedLiteralViolationReason.mutated),
        ("run worker.retry()", "Run the retry.", RefineProtectedLiteralClass.codeLike, RefineProtectedLiteralViolationReason.dropped),
        ("ship \"release-42\"", "Ship \"release-43\".", RefineProtectedLiteralClass.quotedLiteral, RefineProtectedLiteralViolationReason.mutated),
        ("id 550e8400-e29b-41d4-a716-446655440000", "Keep the ID.", RefineProtectedLiteralClass.opaqueID, RefineProtectedLiteralViolationReason.dropped),
        ("retry 500 tomorrow", "Retry tomorrow.", RefineProtectedLiteralClass.integer, RefineProtectedLiteralViolationReason.dropped),
        ("retry 500 tomorrow", "Retry 501 tomorrow.", RefineProtectedLiteralClass.integer, RefineProtectedLiteralViolationReason.mutated),
    ])
    func exactProtectedLiteralValidatorRejectsDroppedOrMutatedValues(
        source: String,
        proposal: String,
        expectedClass: RefineProtectedLiteralClass,
        expectedReason: RefineProtectedLiteralViolationReason
    ) throws {
        let violation = try #require(RefineProtectedLiteralValidator.validate(source: source, proposal: proposal).violation)
        #expect(violation.literalClass == expectedClass)
        #expect(violation.reason == expectedReason)
    }

    @Test(arguments: [
        (
            "fatal error: unexpectedly found nil while unwrapping an Optional value\n0   Rasc  0x0000000104ab2c10",
            "Fatal error: unexpectedly found nil while unwrapping an Optional value"
        ),
        ("investigate next_retry_at in worker", "Investigate when to retry the next task in the worker"),
        ("talvez o endpoint /api/v2/export tá retornando 500", "/api/v2/export"),
        ("next_retry_at", "next retry at"),
        ("metrics p95 latency", "Latencia P95"),
    ])
    func exactValidatorRejectsEveryInScopeProposalPredictedByM12B005A(
        source: String,
        proposal: String
    ) {
        #expect(RefineProtectedLiteralValidator.validate(source: source, proposal: proposal).violation != nil)
    }

    @Test(arguments: [
        ("reunião 15h amanhã", "Reunião às 3:00 PM amanhã."),
        ("pagar R$ 300 amanhã", "Pagar R$300 amanhã."),
        ("desconto 50% hoje", "Desconto de 50 % hoje."),
        ("prazo 31/12", "Prazo December 31."),
        ("valor 1.234,50", "Valor 1,234.50."),
        ("ordinary prose here", "Clear ordinary prose here."),
        ("trocar itens/conteudos amanhã", "Trocar itens/conteúdos amanhã."),
    ])
    func exactValidatorDoesNotClassifyExcludedOrOrdinaryText(source: String, proposal: String) {
        #expect(RefineProtectedLiteralValidator.extract(from: source).isEmpty)
        #expect(RefineProtectedLiteralValidator.validate(source: source, proposal: proposal) == .valid)
    }

    @Test(arguments: [
        ("pagar R$ 99,90 amanhã", "Pagar 99,90 amanhã.", RefineProtectedLiteralViolationReason.currencyDropped),
        ("pagar R$ 99,90 amanhã", "Pagar $ 99.90 amanhã.", RefineProtectedLiteralViolationReason.currencyChanged),
        ("pagar R$ 99,90 amanhã", "Pagar R$ 199,90 amanhã.", RefineProtectedLiteralViolationReason.valueChanged),
        ("pagar R$ 50 amanhã", "Pagar amanhã.", RefineProtectedLiteralViolationReason.literalDropped),
        ("pagar R$ 50 e R$ 100", "Pagar R$ 100.", RefineProtectedLiteralViolationReason.multiplicityChanged),
        ("pagar R$ 50 e R$ 50", "Pagar R$ 50.", RefineProtectedLiteralViolationReason.multiplicityChanged),
        ("pagar R$ 50", "Pagar R$ 50 e R$ 100.", RefineProtectedLiteralViolationReason.multiplicityChanged),
        ("pay $99.90", "Pay USD 99.90.", RefineProtectedLiteralViolationReason.currencyChanged),
        ("pagar R$ 1.000 amanhã", "Pagar R$1.000 amanhã.", RefineProtectedLiteralViolationReason.ambiguousTransformation),
        ("pagar R$ 1.250.00 amanhã", "Pagar R$1.250.00 amanhã.", RefineProtectedLiteralViolationReason.ambiguousTransformation),
    ])
    func moneyValidatorRejectsUnsafeOrUnprovableTransformations(
        source: String,
        proposal: String,
        expectedReason: RefineProtectedLiteralViolationReason
    ) throws {
        let violation = try #require(RefineMoneyLiteralValidator.validate(
            source: source,
            proposal: proposal
        ).violation)
        #expect(violation.literalClass == .money)
        #expect(violation.reason == expectedReason)
    }

    @Test(arguments: [
        ("pagar R$ 99,90 amanhã", "Pagar R$99,90 amanhã."),
        ("pagar R$ 99,90 amanhã", "Pagar R$ 99.90 amanhã."),
        ("pagar R$ 1.234,56", "Pagar BRL 1,234.56."),
        ("pay $1,234.56", "Pay $ 1.234,56."),
        ("pay USD 99.90", "Pay US$ 99,90."),
        ("pay EUR 80.00", "Pay € 80,00."),
        ("pay £1,234.56", "Pay GBP 1.234,56."),
        ("pagar R$ 50 e R$ 100", "Pagar R$50 e R$100."),
        ("pagar R$ 50 e R$ 50", "Pagar R$50 e R$50."),
    ])
    func moneyValidatorAcceptsProvenEquivalentValues(source: String, proposal: String) {
        #expect(RefineMoneyLiteralValidator.validate(source: source, proposal: proposal) == .valid)
    }

    @Test(arguments: [
        "99,90",
        "total 1000 amanhã",
        "price$50",
        "$value",
        "USDParser",
        "foo_bar",
    ])
    func moneyExtractorDoesNotInferBareNumbersOrCode(input: String) {
        #expect(RefineMoneyLiteralValidator.extract(from: input).isEmpty)
    }

    @Test
    func ambiguousMoneyRequiresExactLiteralPreservation() {
        #expect(RefineMoneyLiteralValidator.validate(
            source: "pagar R$ 1.000 amanhã",
            proposal: "Pagar R$ 1.000 amanhã."
        ) == .valid)
        #expect(RefineMoneyLiteralValidator.parseAmount("1.000") == .ambiguous)
        #expect(RefineMoneyLiteralValidator.parseAmount("1.250.00") == .invalid)
        #expect(RefineMoneyLiteralValidator.parseAmount("1.234,56") == .parsed(Decimal(string: "1234.56")!))
        #expect(RefineMoneyLiteralValidator.parseAmount("1,234.56") == .parsed(Decimal(string: "1234.56")!))
    }

    @Test
    func moneyFinalizerContainsKnownBRLFailures() throws {
        let request = RefinementRequest(snapshot: NoteSnapshot(
            noteID: UUID(), revision: 1, text: "pagar R$ 99,90 amanhã"
        ))
        for unsafe in ["Pagar $ 99.90 amanhã.", "Pagar 99.90 amanhã."] {
            let result = RefineMoneyLiteralValidator.finalize(
                RefinementResult(decision: .changed, kind: .unknown, text: unsafe),
                for: request
            )
            #expect(result.decision == .noChange)
            #expect(result.text == request.inputText)
            #expect(result.protectedLiteralTrace?.literalClass == .money)
            #expect(result.protectedLiteralTrace?.validatorRejected == true)
        }
    }

    @Test
    func moneySelectionProtectsOnlySelectedSource() throws {
        let fullNote = "Orçamento R$ 100; pagar R$ 50 amanhã."
        let selectedMoney = try #require(fullNote.range(of: "pagar R$ 50 amanhã"))
        let selectedRequest = RefinementRequest(snapshot: NoteSnapshot(
            noteID: UUID(), revision: 1, text: fullNote, selection: selectedMoney
        ))
        #expect(RefineMoneyLiteralValidator.validate(
            source: selectedRequest.inputText,
            proposal: "Pagar R$50 amanhã."
        ) == .valid)
        #expect(RefineMoneyLiteralValidator.validate(
            source: selectedRequest.inputText,
            proposal: "Pagar R$55 amanhã."
        ).violation?.reason == .valueChanged)

        let selectedPlain = try #require(fullNote.range(of: "pagar"))
        let plainRequest = RefinementRequest(snapshot: NoteSnapshot(
            noteID: UUID(), revision: 1, text: fullNote, selection: selectedPlain
        ))
        let result = RefineMoneyLiteralValidator.finalize(
            RefinementResult(decision: .changed, kind: .unknown, text: "Pagar"),
            for: plainRequest
        )
        #expect(result.decision == .changed)
    }

    @Test(arguments: [
        ("desconto 50% hoje", "Desconto de 55% hoje.", RefineProtectedLiteralViolationReason.valueChanged),
        ("desconto 50% hoje", "Desconto de 50 hoje.", RefineProtectedLiteralViolationReason.literalDropped),
        ("desconto 50% hoje", "Desconto de 0.5 hoje.", RefineProtectedLiteralViolationReason.literalDropped),
        ("cresceu 10% e depois 20%", "Cresceu 10% e depois 15%.", RefineProtectedLiteralViolationReason.valueChanged),
        ("cresceu 10% e depois 20%", "Cresceu 10%.", RefineProtectedLiteralViolationReason.multiplicityChanged),
        ("cresceu 10% e 10%", "Cresceu 10%.", RefineProtectedLiteralViolationReason.multiplicityChanged),
        ("taxa 1.000% hoje", "Taxa de 1000% hoje.", RefineProtectedLiteralViolationReason.ambiguousTransformation),
    ])
    func percentageValidatorRejectsUnsafeOrUnprovableTransformations(
        source: String,
        proposal: String,
        expectedReason: RefineProtectedLiteralViolationReason
    ) throws {
        let violation = try #require(RefinePercentageLiteralValidator.validate(
            source: source,
            proposal: proposal
        ).violation)
        #expect(violation.literalClass == .percentage)
        #expect(violation.reason == expectedReason)
    }

    @Test(arguments: [
        ("desconto 50% hoje", "Desconto de 50 % hoje."),
        ("desconto 50 % hoje", "Desconto de 50% hoje."),
        ("taxa 12,5% hoje", "Taxa de 12,5 % hoje."),
        ("taxa 12,5% hoje", "Taxa de 12.5% hoje."),
        ("cresceu 10% e depois 20%", "Cresceu 10% e depois 20%."),
        ("cresceu 10% e 10%", "Cresceu 10% e 10%."),
        ("taxa +5% hoje", "Taxa de +5 % hoje."),
    ])
    func percentageValidatorAcceptsProvenEquivalentValues(source: String, proposal: String) {
        #expect(RefinePercentageLiteralValidator.validate(source: source, proposal: proposal) == .valid)
    }

    @Test(arguments: [
        "50",
        "total 1000 amanhã",
        "ratio 0.5 today",
        "percentile",
    ])
    func percentageExtractorDoesNotInferBareNumbersOrNonPercentText(input: String) {
        #expect(RefinePercentageLiteralValidator.extract(from: input).isEmpty)
    }

    @Test
    func ambiguousPercentageRequiresExactLiteralPreservation() {
        #expect(RefinePercentageLiteralValidator.validate(
            source: "taxa 1.000% hoje",
            proposal: "Taxa de 1.000% hoje."
        ) == .valid)
        #expect(RefinePercentageLiteralValidator.parseNumericText("1.000") == .ambiguous)
    }

    @Test
    func percentageFinalizerContainsKnownRepresentationFailures() throws {
        let request = RefinementRequest(snapshot: NoteSnapshot(
            noteID: UUID(), revision: 1, text: "desconto 50% hoje"
        ))
        for unsafe in ["Desconto de 55% hoje.", "Desconto de 50 hoje.", "Desconto de 0.5 hoje."] {
            let result = RefinePercentageLiteralValidator.finalize(
                RefinementResult(decision: .changed, kind: .unknown, text: unsafe),
                for: request
            )
            #expect(result.decision == .noChange)
            #expect(result.text == request.inputText)
            #expect(result.protectedLiteralTrace?.literalClass == .percentage)
            #expect(result.protectedLiteralTrace?.validatorRejected == true)
        }
    }

    @Test
    func percentageSelectionProtectsOnlySelectedSource() throws {
        let fullNote = "Meta 80%; desconto 50% hoje."
        let selectedPercentage = try #require(fullNote.range(of: "desconto 50% hoje"))
        let selectedRequest = RefinementRequest(snapshot: NoteSnapshot(
            noteID: UUID(), revision: 1, text: fullNote, selection: selectedPercentage
        ))
        #expect(RefinePercentageLiteralValidator.validate(
            source: selectedRequest.inputText,
            proposal: "Desconto de 50 % hoje."
        ) == .valid)
        #expect(RefinePercentageLiteralValidator.validate(
            source: selectedRequest.inputText,
            proposal: "Desconto de 55% hoje."
        ).violation?.reason == .valueChanged)

        let selectedPlain = try #require(fullNote.range(of: "desconto"))
        let plainRequest = RefinementRequest(snapshot: NoteSnapshot(
            noteID: UUID(), revision: 1, text: fullNote, selection: selectedPlain
        ))
        let result = RefinePercentageLiteralValidator.finalize(
            RefinementResult(decision: .changed, kind: .unknown, text: "Desconto"),
            for: plainRequest
        )
        #expect(result.decision == .changed)
    }

    @Test(arguments: [
        ("reunião 15h amanhã", "Reunião às 17h amanhã.", RefineProtectedLiteralViolationReason.valueChanged),
        ("reunião 15:30 amanhã", "Reunião às 15:45 amanhã.", RefineProtectedLiteralViolationReason.valueChanged),
        ("meeting 3 PM tomorrow", "Meeting at 5 PM tomorrow.", RefineProtectedLiteralViolationReason.valueChanged),
        ("meeting 3 PM tomorrow", "Meeting at 3 AM tomorrow.", RefineProtectedLiteralViolationReason.ampmChanged),
        ("reunião 15:00 amanhã", "Reunião às 3 PM amanhã.", RefineProtectedLiteralViolationReason.crossFamilyRewrite),
        ("meeting 3 PM tomorrow", "Meeting at 15:00 tomorrow.", RefineProtectedLiteralViolationReason.crossFamilyRewrite),
        ("reunião 15h amanhã", "Reunião amanhã.", RefineProtectedLiteralViolationReason.literalDropped),
        ("reunião 9h e 14h", "Reunião às 9h.", RefineProtectedLiteralViolationReason.multiplicityChanged),
        ("reunião 9h e 9h", "Reunião às 9h.", RefineProtectedLiteralViolationReason.multiplicityChanged),
    ])
    func timeValidatorRejectsUnsafeOrUnprovableTransformations(
        source: String,
        proposal: String,
        expectedReason: RefineProtectedLiteralViolationReason
    ) throws {
        let violation = try #require(RefineTimeLiteralValidator.validate(
            source: source,
            proposal: proposal
        ).violation)
        #expect(violation.literalClass == .time)
        #expect(violation.reason == expectedReason)
    }

    @Test(arguments: [
        ("reunião 15h amanhã", "Reunião às 15:00 amanhã."),
        ("reunião 15h30 amanhã", "Reunião às 15:30 amanhã."),
        ("reunião 15:00 amanhã", "Reunião às 15h amanhã."),
        ("meeting 3 PM tomorrow", "Meeting at 3:00 PM tomorrow."),
        ("meeting 3:30 PM tomorrow", "Meeting at 3:30PM tomorrow."),
        ("reunião 9h e 14h", "Reunião às 9h e 14h."),
        ("reunião 9h e 9h", "Reunião às 9h e 9h."),
        ("meeting 12 AM tomorrow", "Meeting at 12:00 AM tomorrow."),
    ])
    func timeValidatorAcceptsSameFamilyEquivalentValues(source: String, proposal: String) {
        #expect(RefineTimeLiteralValidator.validate(source: source, proposal: proposal) == .valid)
    }

    @Test(arguments: [
        "3",
        "15",
        "3.30",
        "15.30",
        "total 1000 amanhã",
        "room405",
    ])
    func timeExtractorDoesNotInferBareNumbersOrMalformedForms(input: String) {
        #expect(RefineTimeLiteralValidator.extract(from: input).isEmpty)
    }

    @Test
    func timeFinalizerContainsKnownFailures() throws {
        let request = RefinementRequest(snapshot: NoteSnapshot(
            noteID: UUID(), revision: 1, text: "reunião 15h amanhã"
        ))
        for unsafe in ["Reunião às 17h amanhã.", "Reunião às 3 PM amanhã.", "Reunião amanhã."] {
            let result = RefineTimeLiteralValidator.finalize(
                RefinementResult(decision: .changed, kind: .unknown, text: unsafe),
                for: request
            )
            #expect(result.decision == .noChange)
            #expect(result.text == request.inputText)
            #expect(result.protectedLiteralTrace?.literalClass == .time)
            #expect(result.protectedLiteralTrace?.validatorRejected == true)
        }
    }

    @Test
    func timeSelectionProtectsOnlySelectedSource() throws {
        let fullNote = "Almoço 12h; reunião 15h amanhã."
        let selectedTime = try #require(fullNote.range(of: "reunião 15h amanhã"))
        let selectedRequest = RefinementRequest(snapshot: NoteSnapshot(
            noteID: UUID(), revision: 1, text: fullNote, selection: selectedTime
        ))
        #expect(RefineTimeLiteralValidator.validate(
            source: selectedRequest.inputText,
            proposal: "Reunião às 15:00 amanhã."
        ) == .valid)
        #expect(RefineTimeLiteralValidator.validate(
            source: selectedRequest.inputText,
            proposal: "Reunião às 17h amanhã."
        ).violation?.reason == .valueChanged)

        let selectedPlain = try #require(fullNote.range(of: "reunião"))
        let plainRequest = RefinementRequest(snapshot: NoteSnapshot(
            noteID: UUID(), revision: 1, text: fullNote, selection: selectedPlain
        ))
        let result = RefineTimeLiteralValidator.finalize(
            RefinementResult(decision: .changed, kind: .unknown, text: "Reunião"),
            for: plainRequest
        )
        #expect(result.decision == .changed)
    }

    @Test
    func selectionProtectsOnlyLiteralsInsideSelectedSource() throws {
        let fullNote = "Deploy foo_bar after talking to @rafa."
        let selectedIdentifier = try #require(fullNote.range(of: "foo_bar"))
        let identifierRequest = RefinementRequest(snapshot: NoteSnapshot(
            noteID: UUID(), revision: 1, text: fullNote, selection: selectedIdentifier
        ))
        let rejected = RefineProtectedLiteralValidator.finalize(
            RefinementResult(decision: .changed, kind: .unknown, text: "foo bar"),
            for: identifierRequest
        )
        #expect(rejected.decision == .noChange)
        #expect(rejected.text == "foo_bar")

        let selectedPlainText = try #require(fullNote.range(of: "after talking"))
        let plainRequest = RefinementRequest(snapshot: NoteSnapshot(
            noteID: UUID(), revision: 1, text: fullNote, selection: selectedPlainText
        ))
        let allowed = RefineProtectedLiteralValidator.finalize(
            RefinementResult(decision: .changed, kind: .unknown, text: "after speaking"),
            for: plainRequest
        )
        #expect(allowed.decision == .changed)
        #expect(allowed.protectedLiteralTrace?.validatorRejected == false)
    }

    @Test
    func selectionRequiresEveryProtectedLiteralInsideTheSelection() throws {
        let fullNote = "Before foo_bar and @rafa after."
        let selection = try #require(fullNote.range(of: "foo_bar and @rafa"))
        let request = RefinementRequest(snapshot: NoteSnapshot(
            noteID: UUID(), revision: 1, text: fullNote, selection: selection
        ))

        let result = RefineProtectedLiteralValidator.finalize(
            RefinementResult(decision: .changed, kind: .unknown, text: "foo_bar"),
            for: request
        )

        #expect(result.decision == .noChange)
        #expect(result.text == "foo_bar and @rafa")
        #expect(result.protectedLiteralTrace?.literalClass == .handle)
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

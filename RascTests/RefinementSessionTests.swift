import Foundation
import Testing
@testable import Rasc

@Suite(.serialized)
@MainActor
struct RefinementSessionTests {
    @Test
    func commandJCreatesAFullNoteRequestFromTheCurrentInMemoryContent() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let provider = ControlledRefinementProvider()
        let session = fixture.makeSession(provider: provider)
        session.text = "rough note before autosave"

        session.startRefinement()
        let request = await provider.nextRequest()

        #expect(session.surface == .refining)
        #expect(request.inputText == "rough note before autosave")
        #expect(request.snapshot.text == "rough note before autosave")
        #expect(request.snapshot.selection == nil)
        #expect(request.snapshot.revision == session.contentRevision)
        #expect(try await fixture.repository.fetch(id: request.snapshot.noteID)?.content == request.snapshot.text)
        session.cancelRefinement()
        await provider.fail(requestID: request.requestID, with: .providerFailure)
        await Task.yield()
    }

    @Test
    func commandJCreatesARequestFromOnlyTheImmutableSelection() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let provider = ControlledRefinementProvider()
        let session = fixture.makeSession(provider: provider)
        session.text = "Keep this. rough café 👩🏽‍💻 selection. Keep this too."
        let selection = try #require(session.text.range(of: "rough café 👩🏽‍💻 selection"))

        session.startRefinement(selection: selection)
        let request = await provider.nextRequest()

        #expect(request.inputText == "rough café 👩🏽‍💻 selection")
        #expect(request.snapshot.selection == selection)
        #expect(request.snapshot.selectedText == request.inputText)
        session.cancelRefinement()
        await provider.fail(requestID: request.requestID, with: .providerFailure)
        await Task.yield()
    }

    @Test
    func changedResultBecomesPreviewWithoutMutatingTheOriginal() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let provider = ControlledRefinementProvider()
        let session = fixture.makeSession(provider: provider)
        session.text = "rough note"
        session.startRefinement()
        let request = await provider.nextRequest()

        await provider.succeed(
            requestID: request.requestID,
            with: .init(decision: .changed, kind: .messyText, text: "Clear note.")
        )
        try await waitUntil { session.surface == .refinementPreview }

        #expect(session.text == "rough note")
        #expect(session.refinementPreview?.result.text == "Clear note.")
    }

    @Test
    func noChangeIsSuccessfulAndReturnsToTheUsableEditor() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let provider = ControlledRefinementProvider()
        let session = fixture.makeSession(provider: provider)
        session.text = "Already useful."
        session.startRefinement()
        let request = await provider.nextRequest()

        await provider.succeed(
            requestID: request.requestID,
            with: .init(decision: .noChange, kind: .alreadyGood, text: request.inputText)
        )
        try await waitUntil { session.message == .alreadyUseful }

        #expect(session.text == "Already useful.")
        #expect(session.refinementPreview == nil)
        #expect(try await fixture.repository.refinementRevisions(for: request.snapshot.noteID).isEmpty)
    }

    @Test
    func casualPortugueseSlangCanResolveToNoChangeWithoutAFailure() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let provider = ControlledRefinementProvider()
        let session = fixture.makeSession(provider: provider)
        session.text = "dale rapaziada, qual a boa?"

        session.startRefinement()
        let request = await provider.nextRequest()
        await provider.succeed(
            requestID: request.requestID,
            with: .init(decision: .noChange, kind: .alreadyGood, text: request.inputText)
        )
        try await waitUntil { session.message == .alreadyUseful }

        #expect(session.text == "dale rapaziada, qual a boa?")
        #expect(session.refinementPreview == nil)
        #expect(session.message != .couldNotRefine)
        #expect(try await fixture.repository.refinementRevisions(for: request.snapshot.noteID).isEmpty)
    }

    @Test
    func abbreviatedPortuguesePlanningTextPreservesXYPlaceholdersInPreview() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let provider = ControlledRefinementProvider()
        let session = fixture.makeSession(provider: provider)
        session.text = "trocar nums narrativos por algo como de x itens/conteudos, y% das narrativas sao pos/neg"
        let conservativeResult =
            "Trocar números narrativos por algo como: x itens/conteúdos; y% das narrativas são positivas/negativas."

        session.startRefinement()
        let request = await provider.nextRequest()
        await provider.succeed(
            requestID: request.requestID,
            with: .init(decision: .changed, kind: .messyText, text: conservativeResult)
        )
        try await waitUntil { session.surface == .refinementPreview }

        #expect(session.refinementPreview?.result.text == conservativeResult)
        #expect(session.refinementPreview?.result.text.contains("x") == true)
        #expect(session.refinementPreview?.result.text.contains("y%") == true)
        #expect(session.message != .couldNotRefine)
    }

    @Test
    func enterAcceptsChangedPreviewAndOnlyThenWritesARevision() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let provider = ControlledRefinementProvider()
        let session = fixture.makeSession(provider: provider)
        session.text = "rough note"
        session.startRefinement()
        let request = await provider.nextRequest()
        await provider.succeed(
            requestID: request.requestID,
            with: .init(decision: .changed, kind: .messyText, text: "Clear note.")
        )
        try await waitUntil { session.surface == .refinementPreview }

        #expect(try await fixture.repository.refinementRevisions(for: request.snapshot.noteID).isEmpty)
        try await session.acceptRefinement()

        #expect(session.surface == .editor)
        #expect(session.text == "Clear note.")
        #expect(try await fixture.repository.fetch(id: request.snapshot.noteID)?.content == "Clear note.")
        let revision = try #require(
            try await fixture.repository.refinementRevisions(for: request.snapshot.noteID).first
        )
        #expect(revision.beforeContent == "rough note")
        #expect(revision.afterContent == "Clear note.")
        #expect(revision.provider == "fake")
        #expect(revision.modelIdentifier == "fake-v1")
        #expect(revision.promptVersion == "refine-v1")
    }

    @Test
    func escapeWhileAcceptanceIsPersistingDoesNotSplitEditorAndDatabaseState() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let provider = ControlledRefinementProvider()
        let session = fixture.makeSession(provider: provider)
        session.text = "rough note"
        session.startRefinement()
        let request = await provider.nextRequest()
        await provider.succeed(
            requestID: request.requestID,
            with: .init(decision: .changed, kind: .messyText, text: "Clear note.")
        )
        try await waitUntil { session.surface == .refinementPreview }
        let escapeTask = Task { @MainActor in
            session.handleEscape()
        }

        try await session.acceptRefinement()
        _ = await escapeTask.value

        #expect(session.surface == .editor)
        #expect(session.text == "Clear note.")
        #expect(try await fixture.repository.fetch(id: request.snapshot.noteID)?.content == "Clear note.")
        #expect(try await fixture.repository.refinementRevisions(for: request.snapshot.noteID).count == 1)
    }

    @Test
    func acceptedRefinementRegistersUndoThatRestoresAndPersistsTheOriginal() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let provider = ControlledRefinementProvider()
        let session = fixture.makeSession(provider: provider)
        let undoManager = UndoManager()
        session.text = "original thought"
        session.startRefinement()
        let request = await provider.nextRequest()
        await provider.succeed(
            requestID: request.requestID,
            with: .init(decision: .changed, kind: .messyText, text: "Refined thought.")
        )
        try await waitUntil { session.surface == .refinementPreview }
        try await session.acceptRefinement(undoManager: undoManager)

        undoManager.undo()
        try await session.flush()

        #expect(session.text == "original thought")
        #expect(try await fixture.repository.fetch(id: request.snapshot.noteID)?.content == "original thought")
    }

    @Test
    func escapeCancelsPreviewWithoutMutationOrRevision() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let provider = ControlledRefinementProvider()
        let session = fixture.makeSession(provider: provider)
        session.text = "rough note"
        session.startRefinement()
        let request = await provider.nextRequest()
        await provider.succeed(
            requestID: request.requestID,
            with: .init(decision: .changed, kind: .messyText, text: "Clear note.")
        )
        try await waitUntil { session.surface == .refinementPreview }

        #expect(session.handleEscape())

        #expect(session.surface == .editor)
        #expect(session.text == "rough note")
        #expect(try await fixture.repository.refinementRevisions(for: request.snapshot.noteID).isEmpty)
    }

    @Test
    func staleNoteRevisionNeverDisplaysItsResult() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let provider = ControlledRefinementProvider()
        let session = fixture.makeSession(provider: provider)
        session.text = "revision one"
        session.startRefinement()
        let request = await provider.nextRequest()

        session.text = "revision two"
        await provider.succeed(
            requestID: request.requestID,
            with: .init(decision: .changed, kind: .messyText, text: "Stale rewrite")
        )
        await Task.yield()

        #expect(session.surface == .editor)
        #expect(session.text == "revision two")
        #expect(session.refinementPreview == nil)
    }

    @Test
    func contentEditedWhileRunningInvalidatesTheActiveRequestImmediately() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let provider = ControlledRefinementProvider()
        let session = fixture.makeSession(provider: provider)
        session.text = "before"
        session.startRefinement()
        let request = await provider.nextRequest()

        session.text = "after local edit"

        #expect(session.activeRefinementRequest == nil)
        #expect(session.surface == .editor)
        #expect(session.text == "after local edit")
        await provider.fail(requestID: request.requestID, with: .providerFailure)
        await Task.yield()
    }

    @Test
    func staleRequestIDCannotReplaceTheNewerRequestPreview() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let provider = ControlledRefinementProvider()
        let session = fixture.makeSession(provider: provider)
        session.text = "same note"
        session.startRefinement()
        let first = await provider.nextRequest()
        session.startRefinement()
        let second = await provider.nextRequest(after: first.requestID)

        await provider.succeed(
            requestID: first.requestID,
            with: .init(decision: .changed, kind: .unknown, text: "First stale result")
        )
        await Task.yield()
        #expect(session.surface == .refining)
        #expect(session.activeRefinementRequest?.requestID == second.requestID)

        await provider.succeed(
            requestID: second.requestID,
            with: .init(decision: .changed, kind: .unknown, text: "Second current result")
        )
        try await waitUntil { session.surface == .refinementPreview }
        #expect(session.refinementPreview?.result.text == "Second current result")
    }

    @Test
    func switchingNotesWhileRunningCancelsTheOldRequest() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let active = try await fixture.repository.createScratch(content: "active note")
        try await Task.sleep(for: .milliseconds(10))
        let target = try await fixture.repository.createScratch(content: "target note")
        fixture.userDefaults.set(active.id.uuidString, forKey: "activeNoteID")
        let provider = ControlledRefinementProvider()
        let session = fixture.makeSession(provider: provider)
        try await session.restore()
        session.startRefinement()
        let request = await provider.nextRequest()

        try await session.openSearch()
        let targetIndex = try #require(session.searchResults.firstIndex(where: { $0.id == target.id }))
        session.selectSearchResult(at: targetIndex)
        #expect(try await session.openSelectedSearchResult())
        await provider.succeed(
            requestID: request.requestID,
            with: .init(decision: .changed, kind: .unknown, text: "Wrong note result")
        )
        await Task.yield()

        #expect(session.text == "target note")
        #expect(session.surface == .editor)
        #expect(session.refinementPreview == nil)
    }

    @Test
    func acceptingSelectionReplacesOnlyItsOriginalRegion() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let provider = ControlledRefinementProvider()
        let session = fixture.makeSession(provider: provider)
        session.text = "Keep before. confusing middle. Keep after."
        let selection = try #require(session.text.range(of: "confusing middle"))
        session.startRefinement(selection: selection)
        let request = await provider.nextRequest()
        await provider.succeed(
            requestID: request.requestID,
            with: .init(decision: .changed, kind: .messyText, text: "Clear middle")
        )
        try await waitUntil { session.surface == .refinementPreview }

        try await session.acceptRefinement()

        #expect(session.text == "Keep before. Clear middle. Keep after.")
    }

    @Test
    func portugueseSelectionRefinementStaysLocalAndReplacesOnlyTheOriginalFragment() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let provider = ControlledRefinementProvider()
        let session = fixture.makeSession(provider: provider)
        session.text = "ola tudobem como vc ta?"
        let selection = try #require(session.text.range(of: "ola tudobem"))

        session.startRefinement(selection: selection)
        let request = await provider.nextRequest()
        #expect(request.scope == .selection)
        #expect(request.inputText == "ola tudobem")
        let context = try #require(request.selectionContext)
        #expect(context.before == "")
        #expect(context.selected == "ola tudobem")
        #expect(context.after == " como vc ta?")

        await provider.succeed(
            requestID: request.requestID,
            with: .init(decision: .changed, kind: .message, text: "olá, tudo bem")
        )
        try await waitUntil { session.surface == .refinementPreview }
        try await session.acceptRefinement()

        #expect(session.text == "olá, tudo bem como vc ta?")
        #expect(!session.text.contains("Hello, everyone!"))
        #expect(session.text.count < 80)
    }

    @Test
    func fullNoteEchoIsRejectedAsASelectionReplacementBeforePreview() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let provider = ControlledRefinementProvider()
        let session = fixture.makeSession(provider: provider)
        session.text = "ola tudobem como vc ta?"
        let selection = try #require(session.text.range(of: "ola tudobem"))

        session.startRefinement(selection: selection)
        let request = await provider.nextRequest()
        await provider.succeed(
            requestID: request.requestID,
            with: .init(decision: .changed, kind: .message, text: "ola tudobem como vc ta?")
        )
        try await waitUntil { session.message == .couldNotSafelyRefineSelection }

        #expect(session.refinementPreview == nil)
        #expect(session.text == "ola tudobem como vc ta?")
        #expect(try await fixture.repository.refinementRevisions(for: request.snapshot.noteID).isEmpty)
    }

    @Test
    func runawaySelectionResultIsRejectedBeforePreviewAndDoesNotMutateTheNote() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let provider = ControlledRefinementProvider()
        let session = fixture.makeSession(provider: provider)
        session.text = "ola tudobem como vc ta?"
        let selection = try #require(session.text.range(of: "ola tudobem"))

        session.startRefinement(selection: selection)
        let request = await provider.nextRequest()
        let runaway = String(repeating: "Hello, everyone! This is unrelated. ", count: 20)
        await provider.succeed(
            requestID: request.requestID,
            with: .init(decision: .changed, kind: .message, text: runaway)
        )
        try await waitUntil { session.message == .couldNotSafelyRefineSelection }

        #expect(session.refinementPreview == nil)
        #expect(session.text == "ola tudobem como vc ta?")
        #expect(try await fixture.repository.refinementRevisions(for: request.snapshot.noteID).isEmpty)
    }

    @Test
    func wholeNoteResultIsNotLimitedByTheSelectionRunawayGuard() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let provider = ControlledRefinementProvider()
        let session = fixture.makeSession(provider: provider)
        session.text = "short note"

        session.startRefinement()
        let request = await provider.nextRequest()
        let longWholeNote = String(repeating: "Whole-note rewrite. ", count: 20)
        await provider.succeed(
            requestID: request.requestID,
            with: .init(decision: .changed, kind: .messyText, text: longWholeNote)
        )
        try await waitUntil { session.surface == .refinementPreview }

        #expect(session.refinementPreview?.result.text == longWholeNote)
    }

    @Test
    func acceptingSelectionTracksTheReplacementInTheUpdatedText() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let provider = ControlledRefinementProvider()
        let session = fixture.makeSession(provider: provider)
        session.text = "Keep before. confusing middle. Keep after."
        let selection = try #require(session.text.range(of: "confusing middle"))
        session.updateEditorSelection(selection)
        session.startRefinement()
        let request = await provider.nextRequest()
        await provider.succeed(
            requestID: request.requestID,
            with: .init(decision: .changed, kind: .messyText, text: "Clear middle")
        )
        try await waitUntil { session.surface == .refinementPreview }

        try await session.acceptRefinement()

        let updatedSelection = NoteSnapshot(
            noteID: request.snapshot.noteID,
            revision: session.contentRevision,
            text: session.text,
            selection: session.editorSelection
        )
        #expect(updatedSelection.selectedText == "Clear middle")
    }

    @Test
    func acceptingUnicodeSelectionDoesNotSplitGraphemeClusters() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let provider = ControlledRefinementProvider()
        let session = fixture.makeSession(provider: provider)
        session.text = "Antes ☕️ café 👩🏽‍💻 confuso. Depois 🇧🇷."
        let selection = try #require(session.text.range(of: "café 👩🏽‍💻 confuso"))
        session.startRefinement(selection: selection)
        let request = await provider.nextRequest()
        await provider.succeed(
            requestID: request.requestID,
            with: .init(decision: .changed, kind: .message, text: "café claro 👩🏽‍💻")
        )
        try await waitUntil { session.surface == .refinementPreview }

        try await session.acceptRefinement()

        #expect(session.text == "Antes ☕️ café claro 👩🏽‍💻. Depois 🇧🇷.")
    }

    @Test
    func providerFailureLeavesTheOriginalUntouched() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let provider = ControlledRefinementProvider()
        let session = fixture.makeSession(provider: provider)
        session.text = "original"
        session.startRefinement()
        let request = await provider.nextRequest()

        await provider.fail(requestID: request.requestID, with: .providerFailure)
        try await waitUntil { session.message == .couldNotRefine }

        #expect(session.text == "original")
        #expect(try await fixture.repository.refinementRevisions(for: request.snapshot.noteID).isEmpty)
    }

    @Test
    func unavailableProviderLeavesNotesUsableAndNeverRunsGeneration() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let provider = ControlledRefinementProvider(
            availability: .unavailable(.appleIntelligenceNotEnabled)
        )
        let session = fixture.makeSession(provider: provider)
        session.text = "still editable"

        session.startRefinement()
        try await waitUntil { session.message == .unavailable(.appleIntelligenceNotEnabled) }
        session.text += " after unavailable"

        #expect(session.text == "still editable after unavailable")
        #expect(session.surface == .editor)
        #expect(await provider.generationRequestCount == 0)
        try await session.flush()
        #expect(try await fixture.repository.fetchMostRecent()?.content == session.text)
    }

    @Test
    func cancelledResultNeverSurfacesWhenProviderCompletesLate() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let provider = ControlledRefinementProvider()
        let session = fixture.makeSession(provider: provider)
        session.text = "original"
        session.startRefinement()
        let request = await provider.nextRequest()

        #expect(session.handleEscape())
        await provider.succeed(
            requestID: request.requestID,
            with: .init(decision: .changed, kind: .unknown, text: "Late result")
        )
        await Task.yield()

        #expect(session.surface == .editor)
        #expect(session.text == "original")
        #expect(session.refinementPreview == nil)
    }

    private func makeFixture() throws -> RefinementFixture {
        let databaseURL = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appendingPathExtension("sqlite")
        let suiteName = "RascRefinementTests.\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        userDefaults.removePersistentDomain(forName: suiteName)
        return RefinementFixture(
            databaseURL: databaseURL,
            repository: try NoteRepository(databaseURL: databaseURL),
            userDefaults: userDefaults,
            suiteName: suiteName
        )
    }

    private func waitUntil(
        _ condition: @escaping @MainActor () -> Bool
    ) async throws {
        for _ in 0..<100 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Timed out waiting for Refine state")
    }
}

private struct RefinementFixture {
    let databaseURL: URL
    let repository: NoteRepository
    let userDefaults: UserDefaults
    let suiteName: String

    @MainActor
    func makeSession(provider: some RefinementProvider) -> ScratchpadSession {
        ScratchpadSession(
            repository: repository,
            refinementProvider: provider,
            userDefaults: userDefaults
        )
    }

    func remove() {
        userDefaults.removePersistentDomain(forName: suiteName)
        try? repository.closeForTesting()
        try? FileManager.default.removeItem(at: databaseURL)
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: databaseURL.path + "-shm"))
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: databaseURL.path + "-wal"))
    }
}

private actor ControlledRefinementProvider: RefinementProvider {
    nonisolated let metadata = RefinementMetadata(
        provider: "fake",
        modelIdentifier: "fake-v1",
        promptVersion: "refine-v1"
    )

    private let configuredAvailability: RefinementAvailability
    private var requests: [RefinementRequest] = []
    private var requestContinuations: [CheckedContinuation<RefinementRequest, Never>] = []
    private var responseContinuations: [UUID: CheckedContinuation<RefinementResult, Error>] = [:]

    init(availability: RefinementAvailability = .available) {
        configuredAvailability = availability
    }

    var generationRequestCount: Int { requests.count }

    func availability(for request: RefinementRequest) async -> RefinementAvailability {
        configuredAvailability
    }

    func refine(_ request: RefinementRequest) async throws -> RefinementResult {
        requests.append(request)
        if !requestContinuations.isEmpty {
            requestContinuations.removeFirst().resume(returning: request)
        }
        return try await withCheckedThrowingContinuation { continuation in
            responseContinuations[request.requestID] = continuation
        }
    }

    func nextRequest(after previousRequestID: UUID? = nil) async -> RefinementRequest {
        if let request = requests.first(where: { request in
            previousRequestID.map { request.requestID != $0 } ?? true
        }) {
            return request
        }
        return await withCheckedContinuation { continuation in
            requestContinuations.append(continuation)
        }
    }

    func succeed(requestID: UUID, with result: RefinementResult) {
        responseContinuations.removeValue(forKey: requestID)?.resume(returning: result)
    }

    func fail(requestID: UUID, with error: RefinementError) {
        responseContinuations.removeValue(forKey: requestID)?.resume(throwing: error)
    }
}

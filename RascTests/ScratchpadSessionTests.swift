import Foundation
import Testing
@testable import Rasc

@Suite(.serialized)
@MainActor
struct ScratchpadSessionTests {
    @Test
    func requestingSettingsDoesNotChangeTheActiveScratchpad() throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let session = ScratchpadSession(
            repository: fixture.repository,
            userDefaults: fixture.userDefaults
        )
        session.text = "unfinished thought"

        session.requestSettingsPresentation()

        #expect(session.settingsPresentationRequest == 1)
        #expect(session.surface == .editor)
        #expect(session.text == "unfinished thought")
    }

    @Test(arguments: ["", "  \n\t "])
    func doesNotPersistEmptyDrafts(content: String) async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let session = ScratchpadSession(
            repository: fixture.repository,
            userDefaults: fixture.userDefaults
        )
        session.text = content

        try await session.flush()

        #expect(try await fixture.repository.fetchMostRecent() == nil)
        #expect(fixture.userDefaults.string(forKey: "activeNoteID") == nil)
    }

    @Test
    func autosavesTheLatestTextAfterAShortDebounce() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let session = ScratchpadSession(
            repository: fixture.repository,
            userDefaults: fixture.userDefaults
        )
        session.text = "first version"
        session.scheduleAutosave()
        session.text = "latest version"
        session.scheduleAutosave()

        // Persistence resumes on MainActor after the debounce. A busy CI runner
        // can delay that continuation beyond a fixed 300 ms sleep.
        try await waitUntil {
            fixture.userDefaults.string(forKey: "activeNoteID") != nil
        }

        #expect(try await fixture.repository.fetchMostRecent()?.content == "latest version")
        #expect(fixture.userDefaults.string(forKey: "activeNoteID") != nil)
    }

    @Test
    func explicitFlushWinsOverAPendingAutosaveSnapshot() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let session = ScratchpadSession(
            repository: fixture.repository,
            userDefaults: fixture.userDefaults
        )
        session.text = "stale snapshot"
        session.scheduleAutosave()
        session.text = "text at hide or quit"

        try await session.flush()
        try await Task.sleep(for: .milliseconds(250))

        #expect(try await fixture.repository.fetchMostRecent()?.content == "text at hide or quit")
    }

    @Test
    func failedSaveOfADiscardedNotePreservesTheUnsavedText() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let session = ScratchpadSession(repository: fixture.repository, userDefaults: fixture.userDefaults)
        session.text = "original"
        try await session.flush()
        let note = try #require(try await fixture.repository.fetchMostRecent())
        try await fixture.repository.delete(id: note.id)
        session.text = "unsaved edit"

        await #expect(throws: NoteRepository.PersistenceError.staleContent) {
            try await session.flush()
        }
        #expect(session.text == "unsaved edit")
        #expect(session.saveErrorMessage != nil)
        #expect(try await fixture.repository.fetch(id: note.id) == nil)
    }

    @Test
    func contentRevisionInvalidatesARefinementBeforeAutosavePersistsTheEdit() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let note = try await fixture.repository.createScratch(content: "original")
        fixture.userDefaults.set(note.id.uuidString, forKey: "activeNoteID")
        let session = ScratchpadSession(
            repository: fixture.repository,
            userDefaults: fixture.userDefaults
        )
        try await session.restore()

        session.text = "first in-memory edit"
        session.scheduleAutosave()
        let request = RefinementRequest(
            requestID: UUID(),
            snapshot: NoteSnapshot(
                noteID: note.id,
                revision: session.contentRevision,
                text: session.text
            )
        )

        session.text = "second in-memory edit"
        session.scheduleAutosave()

        #expect(session.contentRevision == request.snapshot.revision + 1)
        #expect(!request.isCurrent(
            noteID: note.id,
            revision: session.contentRevision,
            requestID: request.requestID
        ))
        #expect(try await fixture.repository.fetch(id: note.id)?.content == "original")
    }

    @Test
    func contentRevisionChangesOnlyWhenInMemoryContentChanges() throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let session = ScratchpadSession(
            repository: fixture.repository,
            userDefaults: fixture.userDefaults
        )
        let initialRevision = session.contentRevision

        session.text = "draft"
        #expect(session.contentRevision == initialRevision + 1)

        session.text = "draft"
        #expect(session.contentRevision == initialRevision + 1)

        session.text = "draft updated"
        #expect(session.contentRevision == initialRevision + 2)
    }

    @Test
    func relaunchRestoresThePersistedActiveNoteInsteadOfTheMostRecentNote() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let active = try await fixture.repository.createScratch(content: "active note")
        _ = try await fixture.repository.createScratch(content: "newer but inactive")
        fixture.userDefaults.set(active.id.uuidString, forKey: "activeNoteID")

        let relaunchedSession = ScratchpadSession(
            repository: try NoteRepository(databaseURL: fixture.databaseURL),
            userDefaults: fixture.userDefaults
        )
        try await relaunchedSession.restore()

        #expect(relaunchedSession.text == "active note")
    }

    @Test
    func firstM1LaunchAdoptsTheMostRecentExistingNote() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        _ = try await fixture.repository.createScratch(content: "older note")
        let mostRecent = try await fixture.repository.createScratch(content: "M0 active note")

        let session = ScratchpadSession(
            repository: fixture.repository,
            userDefaults: fixture.userDefaults
        )
        try await session.restore()

        #expect(session.text == "M0 active note")
        #expect(fixture.userDefaults.string(forKey: "activeNoteID") == mostRecent.id.uuidString)
    }

    @Test
    func missingActiveNoteRestoresAnEmptyDraft() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        _ = try await fixture.repository.createScratch(content: "existing note")
        fixture.userDefaults.set(UUID().uuidString, forKey: "activeNoteID")

        let session = ScratchpadSession(
            repository: fixture.repository,
            userDefaults: fixture.userDefaults
        )
        try await session.restore()

        #expect(session.text.isEmpty)
        #expect(fixture.userDefaults.string(forKey: "activeNoteID") == nil)
    }

    @Test
    func creatingANewScratchPreservesThePreviousNoteAndRestoresBlank() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let session = ScratchpadSession(
            repository: fixture.repository,
            userDefaults: fixture.userDefaults
        )
        session.text = "keep the previous thought"
        try await session.startNewScratch()

        #expect(session.text.isEmpty)
        #expect(try await fixture.repository.fetchMostRecent()?.content == "keep the previous thought")
        #expect(fixture.userDefaults.string(forKey: "activeNoteID") == nil)

        let relaunchedSession = ScratchpadSession(
            repository: try NoteRepository(databaseURL: fixture.databaseURL),
            userDefaults: fixture.userDefaults
        )
        try await relaunchedSession.restore()
        #expect(relaunchedSession.text.isEmpty)
    }

    @Test
    func startNewScratchOnAnEmptyDraftDoesNotCreateANoteAndFocusesTheEditor() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let session = ScratchpadSession(
            repository: fixture.repository,
            userDefaults: fixture.userDefaults
        )
        session.text = "  \n\t "

        try await session.startNewScratch()

        #expect(session.text.isEmpty)
        #expect(session.surface == .editor)
        #expect(session.focusRequest == 1)
        #expect(try await fixture.repository.fetchAllNonDeleted().isEmpty)
        #expect(fixture.userDefaults.string(forKey: "activeNoteID") == nil)
    }

    @Test
    func startNewScratchPreservesAnUnfinishedThoughtWithoutKeepingIt() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let session = ScratchpadSession(
            repository: fixture.repository,
            userDefaults: fixture.userDefaults
        )
        session.text = "unfinished thought"

        try await session.startNewScratch()

        let stored = try #require(try await fixture.repository.fetchMostRecent())
        #expect(stored.content == "unfinished thought")
        #expect(stored.isKept == false)
        #expect(session.text.isEmpty)
        #expect(session.isActiveNoteKept == false)
        #expect(fixture.userDefaults.string(forKey: "activeNoteID") == nil)

        let recovered = try await session.openNote(id: stored.id)
        #expect(recovered)
        #expect(session.text == "unfinished thought")
    }

    @Test
    func startNewScratchLeavesAKeptThoughtKeptAndRecoverable() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let kept = try await fixture.repository.createScratch(content: "already kept")
        _ = try await fixture.repository.keep(id: kept.id)
        let session = ScratchpadSession(
            repository: fixture.repository,
            userDefaults: fixture.userDefaults
        )
        let opened = try await session.openNote(id: kept.id)
        #expect(opened)
        #expect(session.isActiveNoteKept)

        try await session.startNewScratch()

        #expect(session.text.isEmpty)
        #expect(session.isActiveNoteKept == false)
        let stored = try #require(try await fixture.repository.fetch(id: kept.id))
        #expect(stored.content == "already kept")
        #expect(stored.isKept)
        let recovered = try await session.openNote(id: kept.id)
        #expect(recovered)
        #expect(session.text == "already kept")
        #expect(session.isActiveNoteKept)
    }

    @Test
    func startNewScratchAfterRestorePreservesTheReopenedThought() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let session = ScratchpadSession(
            repository: fixture.repository,
            userDefaults: fixture.userDefaults
        )
        session.text = "hidden by escape"
        try await session.flush()

        let reopened = ScratchpadSession(
            repository: fixture.repository,
            userDefaults: fixture.userDefaults
        )
        try await reopened.restore()
        #expect(reopened.text == "hidden by escape")

        try await reopened.startNewScratch()

        #expect(reopened.text.isEmpty)
        #expect(try await fixture.repository.fetchMostRecent()?.content == "hidden by escape")
        #expect(try await fixture.repository.fetchMostRecent()?.isKept == false)
    }

    @Test
    func startNewScratchDoesNotReplaceTheCurrentScratchWhenSaveFails() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let session = ScratchpadSession(
            repository: fixture.repository,
            userDefaults: fixture.userDefaults
        )
        session.text = "important unfinished text"
        try await session.flush()
        let focusBeforeFailure = session.focusRequest
        try fixture.repository.closeForTesting()

        await #expect(throws: (any Error).self) {
            try await session.startNewScratch()
        }

        #expect(session.text == "important unfinished text")
        #expect(session.saveErrorMessage != nil)
        #expect(session.focusRequest == focusBeforeFailure)
        let reopened = try NoteRepository(databaseURL: fixture.databaseURL)
        #expect(try await reopened.fetchMostRecent()?.content == "important unfinished text")
        #expect(try await reopened.fetchMostRecent()?.isKept == false)
    }

    @Test
    func repeatedStartNewScratchPreservesTheOriginalThoughtOnce() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let session = ScratchpadSession(
            repository: fixture.repository,
            userDefaults: fixture.userDefaults
        )
        session.text = "first thought"
        try await session.startNewScratch()
        try await session.startNewScratch()

        #expect(session.text.isEmpty)
        let notes = try await fixture.repository.fetchAllNonDeleted()
        #expect(notes.map(\.content) == ["first thought"])
        #expect(notes.allSatisfy { !$0.isKept })
    }

    @Test
    func startNewScratchDropsAPendingRefinementWithoutAcceptingIt() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let provider = HeaderNewScratchRefinementProvider()
        let session = ScratchpadSession(
            repository: fixture.repository,
            refinementProvider: provider,
            userDefaults: fixture.userDefaults
        )
        session.text = "rough note about deploy retry"
        session.startRefinement()
        try await waitUntil { session.surface == .refinementPreview }
        #expect(session.refinementPreview?.result.text == "Suggested rewrite")

        try await session.startNewScratch()
        try await Task.sleep(for: .milliseconds(50))

        #expect(session.text.isEmpty)
        #expect(session.surface == .editor)
        #expect(session.refinementPreview == nil)
        #expect(session.message == nil)
        let stored = try #require(try await fixture.repository.fetchMostRecent())
        #expect(stored.content == "rough note about deploy retry")
        #expect(try await fixture.repository.refinementRevisions(for: stored.id).isEmpty)
    }

    @Test
    func startNewScratchCancelsAnInFlightRefinementWithoutApplyingIt() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let provider = HeaderNewScratchRefinementProvider(delay: .milliseconds(400))
        let session = ScratchpadSession(
            repository: fixture.repository,
            refinementProvider: provider,
            userDefaults: fixture.userDefaults
        )
        session.text = "rough note about deploy retry"
        session.startRefinement()
        try await waitUntil { session.surface == .refining }

        try await session.startNewScratch()
        try await Task.sleep(for: .milliseconds(500))

        #expect(session.text.isEmpty)
        #expect(session.surface == .editor)
        #expect(session.refinementPreview == nil)
        #expect(session.message == nil)
        #expect(try await fixture.repository.fetchMostRecent()?.content == "rough note about deploy retry")
    }

    @Test
    func escapeFromTheEditorPreservesTheCurrentThought() throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let session = ScratchpadSession(
            repository: fixture.repository,
            userDefaults: fixture.userDefaults
        )
        session.text = "still unfinished"

        #expect(session.handleEscape() == false)
        #expect(session.text == "still unfinished")
        #expect(session.surface == .editor)
    }

    @Test
    func emptySearchShowsRecentNotes() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let older = try await fixture.repository.createScratch(content: "older note")
        try await Task.sleep(for: .milliseconds(10))
        let newer = try await fixture.repository.createScratch(content: "newer note")
        let session = ScratchpadSession(
            repository: fixture.repository,
            userDefaults: fixture.userDefaults
        )

        try await session.openSearch()

        #expect(session.surface == .search)
        #expect(session.searchQuery.isEmpty)
        #expect(session.searchResults.map(\.id) == [newer.id, older.id])
        #expect(session.selectedSearchIndex == 0)
    }

    @Test
    func searchUpdatesLocallyForTheCurrentQuery() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let queue = try await fixture.repository.createScratch(content: "queue retry")
        _ = try await fixture.repository.createScratch(content: "window focus")
        let session = ScratchpadSession(
            repository: fixture.repository,
            userDefaults: fixture.userDefaults
        )
        try await session.openSearch()

        session.searchQuery = "que"
        try await session.refreshSearch()

        #expect(session.searchResults.map(\.id) == [queue.id])
        #expect(session.selectedSearchIndex == 0)
    }

    @Test
    func arrowNavigationMovesTheSearchSelectionWithinResults() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        _ = try await fixture.repository.createScratch(content: "one")
        try await Task.sleep(for: .milliseconds(10))
        _ = try await fixture.repository.createScratch(content: "two")
        let session = ScratchpadSession(
            repository: fixture.repository,
            userDefaults: fixture.userDefaults
        )
        try await session.openSearch()

        session.moveSearchSelection(by: 1)
        #expect(session.selectedSearchIndex == 1)
        session.moveSearchSelection(by: 1)
        #expect(session.selectedSearchIndex == 1)
        session.moveSearchSelection(by: -1)
        #expect(session.selectedSearchIndex == 0)
        session.moveSearchSelection(by: -1)
        #expect(session.selectedSearchIndex == 0)
    }

    @Test
    func enterOpensTheSelectedNote() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let selected = try await fixture.repository.createScratch(content: "open this result")
        let session = ScratchpadSession(
            repository: fixture.repository,
            userDefaults: fixture.userDefaults
        )
        try await session.openSearch()

        let didOpen = try await session.openSelectedSearchResult()

        #expect(didOpen)
        #expect(session.surface == .editor)
        #expect(session.text == "open this result")
        #expect(fixture.userDefaults.string(forKey: "activeNoteID") == selected.id.uuidString)
    }

    @Test
    func switchingNotesFlushesPendingEditsBeforeOpeningTheResult() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let active = try await fixture.repository.createScratch(content: "original active text")
        try await Task.sleep(for: .milliseconds(10))
        let target = try await fixture.repository.createScratch(content: "target note")
        fixture.userDefaults.set(active.id.uuidString, forKey: "activeNoteID")
        let session = ScratchpadSession(
            repository: fixture.repository,
            userDefaults: fixture.userDefaults
        )
        try await session.restore()
        session.text = "pending active edit"
        session.scheduleAutosave()
        try await session.openSearch()
        #expect(session.searchResults.first?.id == target.id)

        let didOpen = try await session.openSelectedSearchResult()

        #expect(didOpen)
        #expect(try await fixture.repository.fetch(id: active.id)?.content == "pending active edit")
        #expect(session.text == "target note")
        #expect(fixture.userDefaults.string(forKey: "activeNoteID") == target.id.uuidString)
    }

    @Test
    func searchKeepsPreviousResultsUntilTheDebouncedQueryFinishes() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        _ = try await fixture.repository.createScratch(content: "queue retry")
        _ = try await fixture.repository.createScratch(content: "window focus")
        let session = ScratchpadSession(
            repository: fixture.repository,
            userDefaults: fixture.userDefaults
        )
        try await session.openSearch()

        session.searchQuery = "que"
        session.scheduleSearch()
        #expect(!session.searchResults.isEmpty)

        session.searchQuery = "window"
        session.scheduleSearch()
        #expect(!session.searchResults.isEmpty)

        try await waitUntil {
            session.searchResults.map(\.content) == ["window focus"]
        }
    }

    @Test
    func escapeClosesSearchAndReturnsToTheCurrentScratch() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let active = try await fixture.repository.createScratch(content: "current scratch")
        fixture.userDefaults.set(active.id.uuidString, forKey: "activeNoteID")
        let session = ScratchpadSession(
            repository: fixture.repository,
            userDefaults: fixture.userDefaults
        )
        try await session.restore()
        session.text = "current scratch with pending text"
        try await session.openSearch()

        session.closeSearch()

        #expect(session.surface == .editor)
        #expect(session.text == "current scratch with pending text")
        #expect(fixture.userDefaults.string(forKey: "activeNoteID") == active.id.uuidString)
    }

    @Test
    func abandonActiveNoteIfMatchingClearsOnlyTheMatchingScratchSession() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let note = try await fixture.repository.createScratch(content: "active note")
        let other = try await fixture.repository.createScratch(content: "other note")
        let session = ScratchpadSession(
            repository: fixture.repository,
            userDefaults: fixture.userDefaults
        )

        try await session.openNote(id: note.id)
        session.text = "edited active note"
        session.scheduleAutosave()

        await session.abandonActiveNoteIfMatching(id: other.id)

        #expect(session.text == "edited active note")
        #expect(fixture.userDefaults.string(forKey: "activeNoteID") == note.id.uuidString)

        await session.abandonActiveNoteIfMatching(id: note.id)

        #expect(session.text == "")
        #expect(fixture.userDefaults.string(forKey: "activeNoteID") == nil)
    }

    private func waitUntil(
        timeout: Duration = .seconds(2),
        _ predicate: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        Issue.record("Timed out waiting for condition")
    }

    private func makeFixture() throws -> Fixture {
        let databaseURL = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appendingPathExtension("sqlite")
        let suiteName = "RascTests.\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        userDefaults.removePersistentDomain(forName: suiteName)
        return Fixture(
            databaseURL: databaseURL,
            repository: try NoteRepository(databaseURL: databaseURL),
            userDefaults: userDefaults,
            suiteName: suiteName
        )
    }
}

private struct HeaderNewScratchRefinementProvider: RefinementProvider {
    let metadata = RefinementMetadata(
        provider: "test",
        modelIdentifier: "test",
        promptVersion: "test"
    )
    var delay: Duration = .zero

    func availability(for _: RefinementRequest) async -> RefinementAvailability {
        .available
    }

    func refine(_: RefinementRequest) async throws -> RefinementResult {
        if delay > .zero {
            try await Task.sleep(for: delay)
        }
        return RefinementResult(
            decision: .changed,
            kind: .messyText,
            text: "Suggested rewrite"
        )
    }
}

private struct Fixture {
    let databaseURL: URL
    let repository: NoteRepository
    let userDefaults: UserDefaults
    let suiteName: String

    func remove() {
        userDefaults.removePersistentDomain(forName: suiteName)
    }
}

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

        try await Task.sleep(for: .milliseconds(300))

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

        try await Task.sleep(for: .milliseconds(120))
        #expect(session.searchResults.map(\.content) == ["window focus"])
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

private struct Fixture {
    let databaseURL: URL
    let repository: NoteRepository
    let userDefaults: UserDefaults
    let suiteName: String

    func remove() {
        userDefaults.removePersistentDomain(forName: suiteName)
    }
}

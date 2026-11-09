import Foundation
import GRDB
import Testing
@testable import Rasc

@Suite(.serialized)
@MainActor
struct ScratchpadSessionTests {
    @Test
    func imageDocumentIsSavedAndReopened() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let image = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==")!
        let session = ScratchpadSession(repository: fixture.repository, userDefaults: fixture.userDefaults)
        session.text = "hello world"
        let caret = try await session.insertImage(.image(data: image, typeIdentifier: "public.png"), selection: NSRange(location: 5, length: 0))
        #expect(caret == 8)
        #expect(session.document?.hasImages == true)
        try await session.flush()
        let id = try #require(activeNoteID(in: fixture.userDefaults))
        let saved = try #require(try await fixture.repository.fetchDocument(id: id))
        #expect(saved == session.document)
        try await session.startNewScratch()
        #expect(try await session.openNote(id: id))
        #expect(session.document == saved)
        #expect(session.text == "hello\n\u{fffc}\n world")
    }

    @Test
    func imageOnlyThoughtCanBeKeptAndRestored() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let image = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==")!
        let session = ScratchpadSession(repository: fixture.repository, userDefaults: fixture.userDefaults)
        _ = try await session.insertImage(.image(data: image, typeIdentifier: "public.png"), selection: NSRange(location: 0, length: 0))
        #expect(session.hasPersistableContent)
        #expect(try await session.keepActiveNote() == .keptShouldHide)
        let note = try #require(try await fixture.repository.fetchMostRecent())
        #expect(note.displayTitle == "Image")
        #expect(note.isKept)
        #expect(try await session.openNote(id: note.id))
        #expect(session.document?.hasImages == true)
        session.startRefinement()
        #expect(session.message == .containsImages)
    }

    @Test
    func changedThoughtPreventsHidingWhilePasteIsRejected() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let image = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==")!
        let session = ScratchpadSession(repository: fixture.repository, userDefaults: fixture.userDefaults)
        session.text = "first"
        let importTask = try #require(session.beginImageImport(.data(image), selection: NSRange(location: 5, length: 0)))
        session.text = "newer text"
        await #expect(throws: NoteImageImport.ImportError.thoughtChanged) { try await session.flush() }
        #expect(try await importTask.value == nil)
        #expect(session.text == "newer text")
        #expect(session.transientFeedback != nil)
    }

    @Test
    func imageRemainsAfterItsOriginalFileIsDeleted() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let image = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==")!
        let source = FileManager.default.temporaryDirectory.appendingPathComponent("RascSource-\(UUID().uuidString).png")
        try image.write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }
        let session = ScratchpadSession(repository: fixture.repository, userDefaults: fixture.userDefaults)
        let task = try #require(session.beginImageImport(.file(source), selection: NSRange(location: 0, length: 0)))
        #expect(try await task.value != nil)
        try FileManager.default.removeItem(at: source)
        try await session.flush()
        let id = try #require(activeNoteID(in: fixture.userDefaults))
        try await session.startNewScratch()
        #expect(try await session.openNote(id: id))
        #expect(session.document?.parts.contains(.image(data: image, typeIdentifier: "public.png")) == true)
    }

    @Test
    func imageSaveFailureKeepsTheUnsavedDocumentVisible() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let image = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==")!
        let session = ScratchpadSession(repository: fixture.repository, userDefaults: fixture.userDefaults)
        _ = try await session.insertImage(.image(data: image, typeIdentifier: "public.png"), selection: NSRange(location: 0, length: 0))
        let document = session.document
        try fixture.repository.closeForTesting()
        await #expect(throws: (any Error).self) { try await session.flush() }
        #expect(session.document == document)
        #expect(session.document?.hasImages == true)
        #expect(session.saveErrorMessage != nil)
    }

    @Test
    func multipleImagesPasteInOrderAndPersist() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let image = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==")!
        let session = ScratchpadSession(repository: fixture.repository, userDefaults: fixture.userDefaults)
        session.text = "ABC"
        let task = try #require(session.beginImageImports([.data(image), .data(image)], selection: NSRange(location: 1, length: 0)))
        #expect(try await task.value != nil)
        #expect(session.text == "A\n\u{fffc}\n\u{fffc}\nBC")
        try await session.flush()
        let id = try #require(activeNoteID(in: fixture.userDefaults))
        let saved = try #require(try await fixture.repository.fetchDocument(id: id))
        #expect(saved.parts.filter { if case .image = $0 { true } else { false } }.count == 2)
    }

    @Test
    func invalidImageInBatchDoesNotInsertPartialContent() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let image = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==")!
        let session = ScratchpadSession(repository: fixture.repository, userDefaults: fixture.userDefaults)
        session.text = "intact"
        let task = try #require(session.beginImageImports([.data(image), .data(Data([1, 2]))], selection: NSRange(location: 3, length: 0)))
        await #expect(throws: NoteImageImport.ImportError.invalidImage) { try await task.value }
        #expect(session.text == "intact")
        #expect(session.document == nil)
    }

    @Test
    func openingAnotherNoteWaitsForPastedImage() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let target = try await fixture.repository.createScratch(content: "destination")
        let image = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==")!
        let session = ScratchpadSession(repository: fixture.repository, userDefaults: fixture.userDefaults)
        session.text = "previous"
        let importTask = try #require(session.beginImageImport(.data(image), selection: NSRange(location: 8, length: 0)))
        #expect(try await session.openNote(id: target.id))
        #expect(try await importTask.value != nil)
        #expect(session.text == "destination")
        let previous = try #require(try await fixture.repository.search("previous", limit: 10).first)
        #expect(try await fixture.repository.fetchDocument(id: previous.id)?.hasImages == true)
    }

    @Test
    func startingNewScratchWaitsForPastedImage() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let image = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==")!
        let session = ScratchpadSession(repository: fixture.repository, userDefaults: fixture.userDefaults)
        session.text = "previous"
        let importTask = try #require(session.beginImageImport(.data(image), selection: NSRange(location: 8, length: 0)))
        try await session.startNewScratch()
        #expect(try await importTask.value != nil)
        #expect(session.text.isEmpty)
        let note = try #require(try await fixture.repository.fetchMostRecent())
        #expect(note.hasImages)
        #expect(try await fixture.repository.fetchDocument(id: note.id)?.hasImages == true)
    }

    @Test
    func newerImageEditSurvivesConcurrentSave() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let image = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==")!
        let session = ScratchpadSession(repository: fixture.repository, userDefaults: fixture.userDefaults)
        _ = try await session.insertImage(.image(data: image, typeIdentifier: "public.png"), selection: NSRange(location: 0, length: 0))
        let gate = NoteRepositoryTestGate()
        await fixture.repository.installTestGate(gate)
        let first = Task { try await session.flush() }
        await gate.waitForFirstEntry()
        let newer = NoteDocument(parts: [.image(data: image, typeIdentifier: "public.png"), .text("\nnew text")])
        session.replaceDocumentFromEditor(newer)
        gate.release()
        try await first.value
        try await session.flush()
        let id = try #require(activeNoteID(in: fixture.userDefaults))
        #expect(try await fixture.repository.fetchDocument(id: id) == newer)
        #expect(try await fixture.repository.fetchAllNonDeleted().count == 1)
    }

    @Test
    func discardedImageNoteCanBeRestored() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let image = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==")!
        let session = ScratchpadSession(repository: fixture.repository, userDefaults: fixture.userDefaults)
        _ = try await session.insertImage(.image(data: image, typeIdentifier: "public.png"), selection: NSRange(location: 0, length: 0))
        try await session.flush()
        let original = try #require(session.document)
        let id = try #require(activeNoteID(in: fixture.userDefaults))
        try await session.discardActiveNote()
        #expect(try await fixture.repository.fetch(id: id) == nil)
        await session.undoDiscard()
        #expect(session.document == original)
        #expect(try await fixture.repository.fetchDocument(id: id) == original)
    }

    @Test
    func typingDuringNoteSwitchKeepsTheCurrentDraft() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let target = try await fixture.repository.createScratch(content: "another note")
        let session = ScratchpadSession(repository: fixture.repository, userDefaults: fixture.userDefaults)
        session.text = "original draft"
        try await session.flush()
        session.text = "pending edit"
        let gate = NoteRepositoryTestGate()
        await fixture.repository.installTestGate(gate)
        let opening = Task { try await session.openNote(id: target.id) }
        await gate.waitForFirstEntry()
        session.text = "newer edit"
        session.scheduleAutosave()
        gate.release()
        #expect(try await opening.value == false)
        #expect(session.text == "newer edit")
        try await session.flush()
        let activeID = try #require(activeNoteID(in: fixture.userDefaults))
        #expect(try await fixture.repository.fetch(id: activeID)?.content == "newer edit")
        #expect(try await fixture.repository.fetch(id: target.id)?.content == "another note")
    }

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
    func clearingPersistedTextKeepsTheSameNote() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let session = ScratchpadSession(
            repository: fixture.repository,
            userDefaults: fixture.userDefaults
        )
        session.text = "original thought"
        try await session.flush()
        let noteID = try #require(activeNoteID(in: fixture.userDefaults))

        session.text = ""
        try await session.flush()

        #expect(activeNoteID(in: fixture.userDefaults) == noteID)
        #expect(session.text == "")
        #expect(fixture.userDefaults.string(forKey: "activeNoteID") == noteID.uuidString)
        let stored = try #require(try await fixture.repository.fetch(id: noteID))
        #expect(stored.content == "")
        #expect(stored.deletedAt == nil)
        #expect(try rowCount(at: fixture.databaseURL) == 1)
    }

    @Test
    func clearingAKeptNotePreservesKeptState() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let session = ScratchpadSession(
            repository: fixture.repository,
            userDefaults: fixture.userDefaults
        )
        session.text = "kept thought"
        try await session.flush()
        let outcome = try await session.keepActiveNote()
        #expect(outcome == .keptShouldHide)
        let noteID = try #require(try await fixture.repository.fetchMostRecent()?.id)
        try await session.openNote(id: noteID)

        session.text = ""
        try await session.flush()

        let stored = try #require(try await fixture.repository.fetch(id: noteID))
        #expect(activeNoteID(in: fixture.userDefaults) == noteID)
        #expect(stored.content == "")
        #expect(stored.isKept)
        #expect(session.isActiveNoteKept)
    }

    @Test
    func restoringClearedTextReusesTheSameNote() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let session = ScratchpadSession(
            repository: fixture.repository,
            userDefaults: fixture.userDefaults
        )
        session.text = "original thought"
        try await session.flush()
        let noteID = try #require(activeNoteID(in: fixture.userDefaults))
        session.text = ""
        try await session.flush()

        session.text = "original thought"
        try await session.flush()

        #expect(activeNoteID(in: fixture.userDefaults) == noteID)
        #expect(try await fixture.repository.fetch(id: noteID)?.content == "original thought")
        #expect(try await fixture.repository.fetchAllNonDeleted().map(\.id) == [noteID])
        #expect(try rowCount(at: fixture.databaseURL) == 1)
    }

    @Test
    func reopeningAfterClearRestoresTheEmptyNote() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let session = ScratchpadSession(
            repository: fixture.repository,
            userDefaults: fixture.userDefaults
        )
        session.text = "original thought"
        try await session.flush()
        let noteID = try #require(activeNoteID(in: fixture.userDefaults))
        session.text = ""
        try await session.flush()

        let reopened = ScratchpadSession(
            repository: fixture.repository,
            userDefaults: fixture.userDefaults
        )
        try await reopened.restore()

        #expect(activeNoteID(in: fixture.userDefaults) == noteID)
        #expect(reopened.text == "")
        #expect(try await fixture.repository.fetch(id: noteID)?.content == "")
    }

    @Test
    func newScratchAfterClearKeepsTheEmptyNote() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let session = ScratchpadSession(
            repository: fixture.repository,
            userDefaults: fixture.userDefaults
        )
        session.text = "original thought"
        try await session.flush()
        let noteID = try #require(activeNoteID(in: fixture.userDefaults))
        session.text = ""
        try await session.flush()

        try await session.startNewScratch()

        #expect(activeNoteID(in: fixture.userDefaults) == nil)
        #expect(session.text == "")
        #expect(fixture.userDefaults.string(forKey: "activeNoteID") == nil)
        let stored = try #require(try await fixture.repository.fetch(id: noteID))
        #expect(stored.content == "")
        #expect(try rowCount(at: fixture.databaseURL) == 1)
    }

    @Test
    func discardAfterClearUsesTheExplicitDiscardFlow() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let session = ScratchpadSession(
            repository: fixture.repository,
            userDefaults: fixture.userDefaults
        )
        session.text = "original thought"
        try await session.flush()
        let noteID = try #require(activeNoteID(in: fixture.userDefaults))
        _ = try await fixture.repository.keep(id: noteID)
        await session.refreshActiveNoteIfMatching(id: noteID)
        session.text = ""
        try await session.flush()

        try await session.discardActiveNote()

        #expect(activeNoteID(in: fixture.userDefaults) == nil)
        #expect(session.text == "")
        #expect(try await fixture.repository.fetch(id: noteID) == nil)
        await session.undoDiscard()
        let restored = try #require(try await fixture.repository.fetch(id: noteID))
        #expect(restored.content == "")
        #expect(restored.isKept)
        #expect(activeNoteID(in: fixture.userDefaults) == noteID)
        #expect(session.text == "")
        #expect(session.isActiveNoteKept)
    }

    @Test
    func openingAnotherNoteAfterClearKeepsTheEmptyOriginal() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let session = ScratchpadSession(
            repository: fixture.repository,
            userDefaults: fixture.userDefaults
        )
        session.text = "original thought"
        try await session.flush()
        let originalID = try #require(activeNoteID(in: fixture.userDefaults))
        let other = try await fixture.repository.createScratch(content: "other thought")
        session.text = ""
        try await session.flush()

        let didOpen = try await session.openNote(id: other.id)

        #expect(didOpen)
        #expect(activeNoteID(in: fixture.userDefaults) == other.id)
        #expect(session.text == "other thought")
        #expect(try await fixture.repository.fetch(id: originalID)?.content == "")
        let home = HomeSession(repository: fixture.repository)
        await home.reloadImmediately()
        let homeIDs = home.browseGroups.flatMap(\.notes).map(\.id)
        #expect(homeIDs.contains(originalID))
        #expect(homeIDs.contains(other.id))
    }

    @Test
    func clearedTextNoLongerMatchesSearch() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let session = ScratchpadSession(
            repository: fixture.repository,
            userDefaults: fixture.userDefaults
        )
        session.text = "queue retry investigation"
        try await session.flush()
        let noteID = try #require(activeNoteID(in: fixture.userDefaults))
        session.text = ""
        try await session.flush()

        #expect(try await fixture.repository.search("queue", limit: 10).isEmpty)
        try await session.openSearch()
        #expect(session.searchResults.map(\.id) == [noteID])
        #expect(session.searchResults.first?.displayTitle == "Empty thought")
    }

    @Test
    func failedSaveOfClearedTextDoesNotSwapTheSession() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let session = ScratchpadSession(
            repository: fixture.repository,
            userDefaults: fixture.userDefaults
        )
        session.text = "original thought"
        try await session.flush()
        let noteID = try #require(activeNoteID(in: fixture.userDefaults))
        try await fixture.repository.delete(id: noteID)
        session.text = ""

        await #expect(throws: NoteRepository.PersistenceError.staleContent) {
            try await session.flush()
        }
        #expect(activeNoteID(in: fixture.userDefaults) == noteID)
        #expect(session.text == "")
        #expect(session.saveErrorMessage != nil)
        #expect(try await fixture.repository.fetch(id: noteID) == nil)
    }

    @Test
    func flushBeatsAPendingAutosaveThatWouldClearTheNote() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let session = ScratchpadSession(
            repository: fixture.repository,
            userDefaults: fixture.userDefaults
        )
        session.text = "original thought"
        try await session.flush()
        let noteID = try #require(activeNoteID(in: fixture.userDefaults))
        session.text = ""
        session.scheduleAutosave()
        session.text = "recovered before the debounce"
        try await session.flush()
        try await Task.sleep(for: .milliseconds(250))

        #expect(activeNoteID(in: fixture.userDefaults) == noteID)
        #expect(try await fixture.repository.fetch(id: noteID)?.content == "recovered before the debounce")
        #expect(try rowCount(at: fixture.databaseURL) == 1)
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

    @Test
    func refineThenNewDoesNotDuplicateOrReattachTheDraft() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let gate = NoteRepositoryTestGate()
        await fixture.repository.installTestGate(gate)
        let session = ScratchpadSession(
            repository: fixture.repository,
            userDefaults: fixture.userDefaults
        )
        let secondPersist = AsyncSignal()
        var persistEntries = 0
        session.setPersistProbesForTesting(onEntry: { _ in
            persistEntries += 1
            if persistEntries == 2 { secondPersist.signal() }
        })
        session.text = "original thought"
        session.startRefinement()
        await gate.waitForFirstEntry()

        let switching = Task { try await session.startNewScratch() }
        await secondPersist.wait()
        gate.release()
        try await switching.value

        #expect(session.text.isEmpty)
        #expect(activeNoteID(in: fixture.userDefaults) == nil)
        #expect(try rowCount(at: fixture.databaseURL) == 1)
        let stored = try #require(try await fixture.repository.fetchAllNonDeleted().first)
        #expect(stored.content == "original thought")

        let reopened = ScratchpadSession(
            repository: fixture.repository,
            userDefaults: fixture.userDefaults
        )
        try await reopened.restore()
        #expect(reopened.text.isEmpty)
        #expect(activeNoteID(in: fixture.userDefaults) == nil)
    }

    @Test
    func refineThenEscapeKeepsTheSameDraft() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let gate = NoteRepositoryTestGate()
        await fixture.repository.installTestGate(gate)
        let session = ScratchpadSession(
            repository: fixture.repository,
            userDefaults: fixture.userDefaults
        )
        let persistFinished = AsyncSignal()
        session.setPersistProbesForTesting(onExit: { _ in persistFinished.signal() })
        session.text = "original thought"
        session.startRefinement()
        await gate.waitForFirstEntry()

        #expect(session.handleEscape())
        gate.release()
        await persistFinished.wait()

        let noteID = try #require(activeNoteID(in: fixture.userDefaults))
        #expect(session.text == "original thought")
        #expect(session.surface == .editor)
        #expect(session.refinementPreview == nil)
        #expect(try rowCount(at: fixture.databaseURL) == 1)
        #expect(try await fixture.repository.fetch(id: noteID)?.content == "original thought")

        let reopened = ScratchpadSession(
            repository: fixture.repository,
            userDefaults: fixture.userDefaults
        )
        try await reopened.restore()
        #expect(reopened.text == "original thought")
        #expect(activeNoteID(in: fixture.userDefaults) == noteID)
    }

    @Test
    func openingAnotherNoteWhileTheFirstSaveIsInFlightKeepsOneDraft() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let other = try await fixture.repository.createScratch(content: "other thought")
        let gate = NoteRepositoryTestGate()
        await fixture.repository.installTestGate(gate)
        let session = ScratchpadSession(
            repository: fixture.repository,
            userDefaults: fixture.userDefaults
        )
        let secondPersist = AsyncSignal()
        var persistEntries = 0
        session.setPersistProbesForTesting(onEntry: { _ in
            persistEntries += 1
            if persistEntries == 2 { secondPersist.signal() }
        })
        session.text = "original thought"
        session.startRefinement()
        await gate.waitForFirstEntry()

        let switching = Task { try await session.openNote(id: other.id) }
        await secondPersist.wait()
        gate.release()
        let didOpen = try await switching.value

        #expect(didOpen)
        #expect(session.text == "other thought")
        #expect(activeNoteID(in: fixture.userDefaults) == other.id)
        #expect(try rowCount(at: fixture.databaseURL) == 2)
        let notes = try await fixture.repository.fetchAllNonDeleted()
        #expect(notes.contains { $0.content == "original thought" })
        #expect(notes.filter { $0.content == "original thought" }.count == 1)
    }

    @Test
    func abandonDuringAnInFlightSaveDoesNotRepublishTheOldIdentity() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let session = ScratchpadSession(
            repository: fixture.repository,
            userDefaults: fixture.userDefaults
        )
        session.text = "original thought"
        try await session.flush()
        let noteID = try #require(activeNoteID(in: fixture.userDefaults))
        let gate = NoteRepositoryTestGate()
        await fixture.repository.installTestGate(gate)
        let persistFinished = AsyncSignal()
        session.setPersistProbesForTesting(onExit: { _ in persistFinished.signal() })
        session.text = "original thought revised"
        session.startRefinement()
        await gate.waitForFirstEntry()

        await session.abandonActiveNoteIfMatching(id: noteID)
        #expect(session.text.isEmpty)
        #expect(activeNoteID(in: fixture.userDefaults) == nil)
        gate.release()
        await persistFinished.wait()

        #expect(session.text.isEmpty)
        #expect(activeNoteID(in: fixture.userDefaults) == nil)
        #expect(try await fixture.repository.fetch(id: noteID)?.content == "original thought revised")
    }

    @Test
    func clearingTextWhileTheFirstCreateIsInFlightStoresAnEmptyNote() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let gate = NoteRepositoryTestGate()
        await fixture.repository.installTestGate(gate)
        let session = ScratchpadSession(
            repository: fixture.repository,
            userDefaults: fixture.userDefaults
        )
        let emptyEntered = AsyncSignal()
        let emptyFinished = AsyncSignal()
        session.setPersistProbesForTesting(
            onEntry: { content in
                if content.isEmpty { emptyEntered.signal() }
            },
            onExit: { content in
                if content.isEmpty { emptyFinished.signal() }
            }
        )
        session.text = "thought to clear"
        let revisionBeforeClear = session.contentRevision
        session.startRefinement()
        await gate.waitForFirstEntry()

        session.text = ""
        #expect(session.contentRevision == revisionBeforeClear + 1)
        let flushing = Task { try await session.flush() }
        await emptyEntered.wait()
        #expect(activeNoteID(in: fixture.userDefaults) == nil)
        gate.release()
        try await flushing.value
        await emptyFinished.wait()

        let noteID = try #require(activeNoteID(in: fixture.userDefaults))
        #expect(session.text.isEmpty)
        #expect(session.contentRevision == revisionBeforeClear + 1)
        let stored = try #require(try await fixture.repository.fetch(id: noteID))
        #expect(stored.content.isEmpty)
        #expect(stored.deletedAt == nil)
        #expect(stored.keptAt == nil)
        #expect(try rowCount(at: fixture.databaseURL) == 1)

        let reopened = ScratchpadSession(
            repository: fixture.repository,
            userDefaults: fixture.userDefaults
        )
        try await reopened.restore()
        #expect(reopened.text.isEmpty)
        #expect(activeNoteID(in: fixture.userDefaults) == noteID)
    }

    @Test
    func overlappingSavesFinishInCallOrder() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let session = ScratchpadSession(
            repository: fixture.repository,
            userDefaults: fixture.userDefaults
        )
        session.text = "base"
        try await session.flush()
        let noteID = try #require(activeNoteID(in: fixture.userDefaults))
        let gate = NoteRepositoryTestGate()
        await fixture.repository.installTestGate(gate)
        let secondPersist = AsyncSignal()
        var persistEntries = 0
        session.setPersistProbesForTesting(onEntry: { _ in
            persistEntries += 1
            if persistEntries == 2 { secondPersist.signal() }
        })
        session.text = "first write"
        session.startRefinement()
        await gate.waitForFirstEntry()
        session.text = "second write"

        let flushing = Task { try await session.flush() }
        await secondPersist.wait()
        gate.release()
        try await flushing.value

        #expect(activeNoteID(in: fixture.userDefaults) == noteID)
        #expect(try await fixture.repository.fetch(id: noteID)?.content == "second write")
        #expect(try rowCount(at: fixture.databaseURL) == 1)
    }

    @Test
    func failedCreateWhileStartingANewScratchDoesNotClearTheEditor() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let gate = NoteRepositoryTestGate()
        await fixture.repository.installTestGate(gate)
        let session = ScratchpadSession(
            repository: fixture.repository,
            userDefaults: fixture.userDefaults
        )
        let secondPersist = AsyncSignal()
        var persistEntries = 0
        session.setPersistProbesForTesting(onEntry: { _ in
            persistEntries += 1
            if persistEntries == 2 { secondPersist.signal() }
        })
        session.text = "important unfinished text"
        session.startRefinement()
        await gate.waitForFirstEntry()

        let switching = Task { try await session.startNewScratch() }
        await secondPersist.wait()
        try fixture.repository.closeForTesting()
        gate.release()

        await #expect(throws: (any Error).self) {
            try await switching.value
        }
        #expect(session.text == "important unfinished text")
        #expect(session.saveErrorMessage != nil)
        #expect(activeNoteID(in: fixture.userDefaults) == nil)
        #expect(try rowCount(at: fixture.databaseURL) == 0)
    }

    @Test
    func cancelledRefinementDoesNotApplyALateResult() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let provider = GatedRefinementProvider()
        let session = ScratchpadSession(
            repository: fixture.repository,
            refinementProvider: provider,
            userDefaults: fixture.userDefaults
        )
        session.text = "original thought"
        session.startRefinement()
        await provider.entered.wait()
        let noteID = try #require(activeNoteID(in: fixture.userDefaults))

        #expect(session.handleEscape())
        provider.release()
        await provider.finished.wait()
        await Task.yield()

        #expect(session.text == "original thought")
        #expect(session.refinementPreview == nil)
        #expect(session.surface == .editor)
        #expect(activeNoteID(in: fixture.userDefaults) == noteID)
        #expect(try rowCount(at: fixture.databaseURL) == 1)
        #expect(try await fixture.repository.refinementRevisions(for: noteID).isEmpty)
    }

    private func activeNoteID(in userDefaults: UserDefaults) -> UUID? {
        userDefaults.string(forKey: "activeNoteID").flatMap(UUID.init(uuidString:))
    }

    private func rowCount(at databaseURL: URL) throws -> Int {
        try DatabaseQueue(path: databaseURL.path).read { database in
            try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM notes") ?? 0
        }
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
        let databaseURL = try isolatedDatabaseURL()
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

private func isolatedDatabaseURL() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString)
        .appendingPathExtension("sqlite")
    let path = url.resolvingSymlinksInPath().standardizedFileURL.path
    let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
    let productionRoots = [
        home + "/Library/Application Support/Rasc",
        home + "/Library/Containers/com.rafaeltorres.rasc",
    ]
    guard productionRoots.allSatisfy({ !path.hasPrefix($0) }) else {
        throw TestDatabaseIsolationError.refusedProductionPath(path)
    }
    guard path.contains("/T/") || path.hasPrefix("/tmp/") else {
        throw TestDatabaseIsolationError.refusedProductionPath(path)
    }
    return url
}

private enum TestDatabaseIsolationError: Error {
    case refusedProductionPath(String)
}

private final class AsyncSignal: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Never>?
    private var fired = false

    func signal() {
        lock.lock()
        fired = true
        let continuation = continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume()
    }

    func wait() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if fired {
                lock.unlock()
                continuation.resume()
                return
            }
            self.continuation = continuation
            lock.unlock()
        }
    }
}

private final class GatedRefinementProvider: RefinementProvider, @unchecked Sendable {
    let metadata = RefinementMetadata(
        provider: "test",
        modelIdentifier: "test",
        promptVersion: "test"
    )
    let entered = AsyncSignal()
    let finished = AsyncSignal()
    private let releaseSignal = AsyncSignal()

    func availability(for _: RefinementRequest) async -> RefinementAvailability {
        .available
    }

    func refine(_: RefinementRequest) async throws -> RefinementResult {
        entered.signal()
        await releaseSignal.wait()
        finished.signal()
        return RefinementResult(
            decision: .changed,
            kind: .messyText,
            text: "late suggestion"
        )
    }

    func release() {
        releaseSignal.signal()
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

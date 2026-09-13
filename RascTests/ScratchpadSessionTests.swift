import Foundation
import Testing
@testable import Rasc

@Suite(.serialized)
@MainActor
struct ScratchpadSessionTests {
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

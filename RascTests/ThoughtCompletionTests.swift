import Foundation
import Testing
@testable import Rasc

@Suite(.serialized)
@MainActor
struct ThoughtCompletionTests {
    @Test
    func keepActiveNotePersistsKeptAtAndClearsActiveSession() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let session = ScratchpadSession(
            repository: fixture.repository,
            userDefaults: fixture.userDefaults
        )
        session.text = "messy thought to keep"
        try await session.flush()

        let outcome = try await session.keepActiveNote()
        #expect(outcome == .keptShouldHide)
        #expect(session.text.isEmpty)
        #expect(session.isActiveNoteKept == false)
        #expect(fixture.userDefaults.string(forKey: "activeNoteID") == nil)

        let keptNotes = try await fixture.repository.fetchAllNonDeleted()
        #expect(keptNotes.count == 1)
        #expect(keptNotes[0].content == "messy thought to keep")
        #expect(keptNotes[0].isKept)
    }

    @Test
    func restoreAfterKeepStartsFreshUnfinishedScratch() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let session = ScratchpadSession(
            repository: fixture.repository,
            userDefaults: fixture.userDefaults
        )
        session.text = "done thought"
        try await session.flush()
        _ = try await session.keepActiveNote()

        fixture.userDefaults.set(true, forKey: "activeNoteStateInitialized")
        fixture.userDefaults.removeObject(forKey: "activeNoteID")

        try await session.restore()
        #expect(session.text.isEmpty)
        #expect(session.isActiveNoteKept == false)
    }

    @Test
    func reopeningKeptNotePreservesKeptStateUntilUnkeep() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let note = try await fixture.repository.createScratch(content: "kept reopen")
        _ = try await fixture.repository.keep(id: note.id)

        let session = ScratchpadSession(
            repository: fixture.repository,
            userDefaults: fixture.userDefaults
        )
        let opened = try await session.openNote(id: note.id)
        #expect(opened)
        #expect(session.text == "kept reopen")
        #expect(session.isActiveNoteKept)

        try await session.unkeepActiveNote()
        #expect(session.isActiveNoteKept == false)
        #expect(session.text == "kept reopen")
        #expect(try await fixture.repository.fetch(id: note.id)?.isKept == false)
    }

    @Test
    func discardSoftDeletesOnlyTheActiveNote() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let other = try await fixture.repository.createScratch(content: "leave alone")
        let session = ScratchpadSession(
            repository: fixture.repository,
            userDefaults: fixture.userDefaults
        )
        session.text = "discard me"
        try await session.flush()
        let activeID = try #require(UUID(uuidString: fixture.userDefaults.string(forKey: "activeNoteID") ?? ""))

        try await session.discardActiveNote()

        #expect(session.text.isEmpty)
        #expect(try await fixture.repository.fetch(id: activeID) == nil)
        #expect(try await fixture.repository.fetch(id: other.id)?.content == "leave alone")
    }

    @Test
    func copyActiveNoteDoesNotMutateNoteState() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let session = ScratchpadSession(
            repository: fixture.repository,
            userDefaults: fixture.userDefaults
        )
        session.text = "copy payload"
        try await session.flush()
        let noteID = try #require(UUID(uuidString: fixture.userDefaults.string(forKey: "activeNoteID") ?? ""))

        let copied = try await session.copyActiveNoteText()
        #expect(copied == "copy payload")
        #expect(try await fixture.repository.fetch(id: noteID)?.content == "copy payload")
        #expect(try await fixture.repository.fetch(id: noteID)?.isKept == false)
    }

    @Test
    func keepImmediatelyAfterEditPersistsLatestText() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let session = ScratchpadSession(
            repository: fixture.repository,
            userDefaults: fixture.userDefaults
        )
        session.text = "rapid edit"
        session.scheduleAutosave()

        _ = try await session.keepActiveNote()

        let kept = try #require(try await fixture.repository.fetchMostRecent())
        #expect(kept.content == "rapid edit")
        #expect(kept.isKept)
    }

    @Test
    func keepIsUnavailableWhileRefining() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let provider = ThoughtCompletionRefinementProvider()
        let session = ScratchpadSession(
            repository: fixture.repository,
            refinementProvider: provider,
            userDefaults: fixture.userDefaults
        )
        session.text = "refine before keep"
        try await session.flush()
        session.startRefinement()
        _ = await provider.nextRequest()

        let outcome = try await session.keepActiveNote()
        #expect(outcome == .none)
        #expect(session.surface == .refining)
        #expect(try await fixture.repository.fetchMostRecent()?.isKept == false)
    }

    @Test
    func keepAfterAcceptedRefinementPersistsRefinedContent() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let provider = ThoughtCompletionRefinementProvider()
        let session = ScratchpadSession(
            repository: fixture.repository,
            refinementProvider: provider,
            userDefaults: fixture.userDefaults
        )
        session.text = "rough keep target"
        try await session.flush()
        session.startRefinement()
        let request = await provider.nextRequest()
        await provider.succeed(
            requestID: request.requestID,
            with: .init(decision: .changed, kind: .messyText, text: "Refined keep target")
        )
        try await waitUntil { session.surface == .refinementPreview }
        try await session.acceptRefinement()

        let outcome = try await session.keepActiveNote()
        #expect(outcome == .keptShouldHide)

        let kept = try #require(try await fixture.repository.fetchMostRecent())
        #expect(kept.content == "Refined keep target")
        #expect(kept.isKept)
    }

    @Test
    func keepCancelsInFlightRefinementBeforePersistingKeptState() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let provider = ThoughtCompletionRefinementProvider()
        let session = ScratchpadSession(
            repository: fixture.repository,
            refinementProvider: provider,
            userDefaults: fixture.userDefaults
        )
        session.text = "cancel refine then keep"
        try await session.flush()
        session.startRefinement()
        _ = await provider.nextRequest()
        session.cancelRefinement()

        let outcome = try await session.keepActiveNote()
        #expect(outcome == .keptShouldHide)
        #expect(try await fixture.repository.fetchMostRecent()?.content == "cancel refine then keep")
    }

    @Test
    func homeBrowseGroupsSeparateKeptAndUnfinishedNotes() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let calendar = Calendar(identifier: .gregorian)
        let kept = Note(
            id: UUID(),
            content: "kept thought",
            createdAt: now,
            updatedAt: now,
            deletedAt: nil,
            keptAt: now
        )
        let unfinished = Note(
            id: UUID(),
            content: "unfinished thought",
            createdAt: now,
            updatedAt: now,
            deletedAt: nil,
            keptAt: nil
        )

        let groups = HomeLifecycleGrouping.browseGroups(
            from: [unfinished, kept],
            calendar: calendar,
            now: now
        )

        #expect(groups.count == 2)
        #expect(groups[0].sectionTitle == "Kept")
        #expect(groups[0].notes.map(\.id) == [kept.id])
        #expect(groups[1].sectionTitle == "Today")
        #expect(groups[1].notes.map(\.id) == [unfinished.id])
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

private actor ThoughtCompletionRefinementProvider: RefinementProvider {
    nonisolated let metadata = RefinementMetadata(
        provider: "fake",
        modelIdentifier: "fake-v1",
        promptVersion: "refine-v1"
    )

    private var requests: [RefinementRequest] = []
    private var requestContinuations: [CheckedContinuation<RefinementRequest, Never>] = []
    private var responseContinuations: [UUID: CheckedContinuation<RefinementResult, Error>] = [:]

    func availability(for _: RefinementRequest) async -> RefinementAvailability {
        .available
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

    func nextRequest() async -> RefinementRequest {
        if let request = requests.first {
            return request
        }
        return await withCheckedContinuation { continuation in
            requestContinuations.append(continuation)
        }
    }

    func succeed(requestID: UUID, with result: RefinementResult) {
        responseContinuations.removeValue(forKey: requestID)?.resume(returning: result)
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

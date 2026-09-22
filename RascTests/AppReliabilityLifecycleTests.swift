import AppKit
import Foundation
import Testing
@testable import Rasc

@Suite(.serialized)
@MainActor
struct AppReliabilityLifecycleTests {
    @Test
    func flushForTerminationPersistsPendingEdits() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }

        let controller = try PanelController(
            repository: fixture.repository
        )
        controller.scratchpadSession.text = "persist on quit"
        controller.scratchpadSession.scheduleAutosave()

        let didFlush = await controller.flushForTermination()

        #expect(didFlush)
        #expect(try await fixture.repository.fetchMostRecent()?.content == "persist on quit")
    }

    @Test
    func flushForTerminationReturnsFalseWhenPersistenceFails() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }

        let controller = try PanelController(
            repository: fixture.repository
        )
        controller.scratchpadSession.text = "cannot save after close"

        try fixture.repository.closeForTesting()

        let didFlush = await controller.flushForTermination()

        #expect(!didFlush)
    }

    @Test
    func flushForTerminationCancelsActiveRefinement() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }

        let provider = ControlledRefinementProvider()
        let controller = try PanelController(
            repository: fixture.repository,
            refinementProvider: provider
        )
        controller.scratchpadSession.text = "draft"
        controller.scratchpadSession.startRefinement()
        try await waitUntil { controller.scratchpadSession.surface == .refining }

        let didFlush = await controller.flushForTermination()

        #expect(didFlush)
        #expect(controller.scratchpadSession.surface == .editor)
        #expect(controller.scratchpadSession.refinementPreview == nil)
    }

    @Test
    func switchingNotesFlushesBeforeOpeningTarget() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }

        let first = try await fixture.repository.createScratch(content: "first note")
        let second = try await fixture.repository.createScratch(content: "second note")
        fixture.userDefaults.set(first.id.uuidString, forKey: "activeNoteID")

        let session = ScratchpadSession(
            repository: fixture.repository,
            userDefaults: fixture.userDefaults
        )
        try await session.restore()
        session.text = "edited first"
        session.scheduleAutosave()

        try await session.openNote(id: second.id)

        #expect(try await fixture.repository.fetch(id: first.id)?.content == "edited first")
        #expect(session.text == "second note")
        #expect(fixture.userDefaults.string(forKey: "activeNoteID") == second.id.uuidString)
    }

    @Test
    func releaseBundleDoesNotShipEvalCorpora() throws {
        let bundle = Bundle(for: PanelController.self)
        let resourcePaths = bundle.paths(forResourcesOfType: nil, inDirectory: nil)

        for path in resourcePaths {
            let lastComponent = (path as NSString).lastPathComponent
            #expect(!lastComponent.contains("corpus.v1"))
            #expect(!lastComponent.contains("challenge-set"))
            #expect(!lastComponent.hasSuffix(".jsonl"))
        }
    }

    private func makeFixture() throws -> LifecycleFixture {
        let databaseURL = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appendingPathExtension("sqlite")
        let suiteName = "AppReliabilityLifecycle.\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        userDefaults.removePersistentDomain(forName: suiteName)
        return LifecycleFixture(
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
        Issue.record("Timed out waiting for lifecycle state")
    }
}

private struct LifecycleFixture {
    let databaseURL: URL
    let repository: NoteRepository
    let userDefaults: UserDefaults
    let suiteName: String

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
        promptVersion: "refine-v2-language-preference"
    )

    func availability(for request: RefinementRequest) async -> RefinementAvailability {
        .available
    }

    func refine(_ request: RefinementRequest) async throws -> RefinementResult {
        try await withCheckedThrowingContinuation { _ in }
    }
}

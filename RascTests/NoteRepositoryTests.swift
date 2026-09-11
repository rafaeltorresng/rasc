import Foundation
import Testing
@testable import Rasc

@Suite(.serialized)
struct NoteRepositoryTests {
    @Test
    func persistsTheMostRecentScratchAcrossRepositoryInstances() async throws {
        let databaseURL = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appendingPathExtension("sqlite")
        defer { try? FileManager.default.removeItem(at: databaseURL) }

        let writer = try NoteRepository(databaseURL: databaseURL)
        let created = try await writer.createScratch(content: "check production logs")

        let reader = try NoteRepository(databaseURL: databaseURL)
        let restored = try await reader.fetch(id: created.id)

        #expect(restored?.content == "check production logs")
    }

    @Test
    func updatesTheExistingScratchInsteadOfCreatingAnotherOne() async throws {
        let repository = try makeRepository()
        let created = try await repository.createScratch(content: "first thought")

        try await repository.update(id: created.id, content: "revised thought")

        #expect(try await repository.fetch(id: created.id)?.content == "revised thought")
    }

    @Test
    func fetchesTheMostRecentlyUpdatedScratch() async throws {
        let repository = try makeRepository()
        _ = try await repository.createScratch(content: "older")
        let newer = try await repository.createScratch(content: "newer")

        #expect(try await repository.fetchMostRecent()?.id == newer.id)
    }

    @Test
    func deletesAnEmptyScratch() async throws {
        let repository = try makeRepository()
        let created = try await repository.createScratch(content: "temporary")

        try await repository.delete(id: created.id)

        #expect(try await repository.fetch(id: created.id) == nil)
    }

    @Test
    @MainActor
    func restoresTextFlushedByTheScratchpadSession() async throws {
        let databaseURL = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appendingPathExtension("sqlite")
        defer { try? FileManager.default.removeItem(at: databaseURL) }

        let writer = try NoteRepository(databaseURL: databaseURL)
        let session = ScratchpadSession(repository: writer)
        session.text = "check the deployment after lunch"
        try await session.flush()

        let reader = try NoteRepository(databaseURL: databaseURL)
        let restoredSession = ScratchpadSession(repository: reader)
        try await restoredSession.restore()

        #expect(restoredSession.text == "check the deployment after lunch")
    }

    @Test
    @MainActor
    func startsANewScratchOnlyAfterSavingTheCurrentOne() async throws {
        let databaseURL = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appendingPathExtension("sqlite")
        defer { try? FileManager.default.removeItem(at: databaseURL) }

        let session = ScratchpadSession(repository: try NoteRepository(databaseURL: databaseURL))
        session.text = "saved thought"

        try await session.startNewScratch()

        #expect(session.text.isEmpty)
        let restoredSession = ScratchpadSession(repository: try NoteRepository(databaseURL: databaseURL))
        try await restoredSession.restore()
        #expect(restoredSession.text == "saved thought")
    }

    private func makeRepository() throws -> NoteRepository {
        let databaseURL = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appendingPathExtension("sqlite")
        return try NoteRepository(databaseURL: databaseURL)
    }
}

import Foundation
import Testing
@testable import Rasc

@Suite(.serialized)
struct HomeSessionTests {
    @Test
    func searchDelegatesToRepositoryRanking() async throws {
        let repository = try makeRepository()
        let alpha = try await repository.createScratch(content: "alpha deployment checklist")
        let beta = try await repository.createScratch(content: "beta release notes")
        try await repository.update(id: beta.id, content: "beta deployment checklist")

        let repositoryResults = try await repository.search("deployment", limit: HomeSession.searchResultLimit)

        let session = await MainActor.run {
            HomeSession(repository: repository)
        }
        await MainActor.run {
            session.searchQuery = "deployment"
        }
        await session.reloadImmediately()

        let sessionResults = await MainActor.run { session.searchResults }
        #expect(sessionResults.map(\.id) == repositoryResults.map(\.id))
    }

    @Test
    func reloadReflectsUpdatedNoteContent() async throws {
        let repository = try makeRepository()
        let note = try await repository.createScratch(content: "original title line\nbody")
        let session = await MainActor.run {
            HomeSession(repository: repository)
        }
        await session.reloadImmediately()

        try await repository.update(id: note.id, content: "revised title line\nupdated body")
        await session.reloadImmediately()

        let title = await MainActor.run {
            session.temporalGroups.flatMap(\.notes).first?.displayTitle
        }
        #expect(title == "revised title line")
    }

    @Test
    func excludesDeletedNotesFromChronologicalHome() async throws {
        let repository = try makeRepository()
        let kept = try await repository.createScratch(content: "kept note")
        let deleted = try await repository.createScratch(content: "deleted note")
        try await repository.delete(id: deleted.id)

        let session = await MainActor.run {
            HomeSession(repository: repository)
        }
        await session.reloadImmediately()

        let noteIDs = await MainActor.run {
            session.temporalGroups.flatMap(\.notes).map(\.id)
        }

        #expect(noteIDs == [kept.id])
    }

    private func makeRepository() throws -> NoteRepository {
        let databaseURL = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appendingPathExtension("sqlite")
        return try NoteRepository(databaseURL: databaseURL)
    }
}

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
            session.browseGroups.flatMap(\.notes).first?.displayTitle
        }
        #expect(title == "revised title line")
    }

    @Test
    func discardNoteRemovesNoteFromHome() async throws {
        let repository = try makeRepository()
        let kept = try await repository.createScratch(content: "kept note")
        let discarded = try await repository.createScratch(content: "discarded note")

        let session = await MainActor.run {
            HomeSession(repository: repository)
        }
        await session.reloadImmediately()
        try await session.discardNote(id: discarded.id)

        let noteIDs = await MainActor.run {
            session.browseGroups.flatMap(\.notes).map(\.id)
        }

        #expect(noteIDs == [kept.id])
    }

    @Test
    func duplicateNoteCreatesNewUnfinishedNoteWithSameContent() async throws {
        let repository = try makeRepository()
        let source = try await repository.createScratch(content: "source title\nsource body")
        try await repository.keep(id: source.id)

        let session = await MainActor.run {
            HomeSession(repository: repository)
        }
        await session.reloadImmediately()

        let duplicate = try await session.duplicateNote(id: source.id)

        #expect(duplicate.id != source.id)
        #expect(duplicate.content == source.content)
        #expect(duplicate.keptAt == nil)

        let noteIDs = await MainActor.run {
            session.browseGroups.flatMap(\.notes).map(\.id)
        }
        #expect(noteIDs.contains(duplicate.id))
        #expect(noteIDs.contains(source.id))

        let selectedID = await MainActor.run { session.selectedNoteID }
        #expect(selectedID == duplicate.id)
    }

    @Test
    func unkeepNoteMovesKeptNoteOutOfKeptSection() async throws {
        let repository = try makeRepository()
        let kept = try await repository.createScratch(content: "kept note")
        _ = try await repository.keep(id: kept.id)

        let session = await MainActor.run {
            HomeSession(repository: repository)
        }
        await session.reloadImmediately()

        let keptSectionCount = await MainActor.run {
            session.browseGroups.filter {
                if case .kept = $0.kind { return true }
                return false
            }.flatMap(\.notes).count
        }
        #expect(keptSectionCount == 1)

        try await session.unkeepNote(id: kept.id)

        let keptSectionCountAfter = await MainActor.run {
            session.browseGroups.filter {
                if case .kept = $0.kind { return true }
                return false
            }.flatMap(\.notes).count
        }
        let noteIDs = await MainActor.run {
            session.browseGroups.flatMap(\.notes).map(\.id)
        }

        #expect(keptSectionCountAfter == 0)
        #expect(noteIDs.contains(kept.id))
        #expect(try await repository.fetch(id: kept.id)?.keptAt == nil)
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
            session.browseGroups.flatMap(\.notes).map(\.id)
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

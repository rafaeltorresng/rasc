import Foundation
import GRDB
import Testing
@testable import Rasc

@Suite(.serialized)
struct NoteRepositoryTests {
    @Test
    func createsANoteWithTheInitialSchema() async throws {
        let databaseURL = makeDatabaseURL()
        defer { removeDatabase(at: databaseURL) }
        let repository = try NoteRepository(databaseURL: databaseURL)

        let created = try await repository.createScratch(content: "check production logs")

        #expect(created.content == "check production logs")
        #expect(created.createdAt == created.updatedAt)
        let columns = try await DatabaseQueue(path: databaseURL.path).read { database in
            try database.columns(in: Note.databaseTableName).map(\.name)
        }
        #expect(columns == ["id", "content", "created_at", "updated_at", "deleted_at"])
    }

    @Test
    func persistsTheMostRecentScratchAcrossRepositoryInstances() async throws {
        let databaseURL = makeDatabaseURL()
        defer { removeDatabase(at: databaseURL) }

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

    @Test(arguments: ["", "  \n\t "])
    func rejectsContentWithoutMeaningfulCharacters(content: String) async throws {
        let repository = try makeRepository()

        do {
            _ = try await repository.createScratch(content: content)
            Issue.record("Whitespace-only content was persisted")
        } catch {
            #expect(try await repository.fetchMostRecent() == nil)
        }
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
        let databaseURL = makeDatabaseURL()
        defer { removeDatabase(at: databaseURL) }
        let repository = try NoteRepository(databaseURL: databaseURL)
        let created = try await repository.createScratch(content: "temporary")

        try await repository.delete(id: created.id)

        #expect(try await repository.fetch(id: created.id) == nil)
        let deletedAt: Date? = try await DatabaseQueue(path: databaseURL.path).read { database in
            try Date.fetchOne(
                database,
                sql: "SELECT deleted_at FROM notes WHERE id = ?",
                arguments: [created.id]
            )
        }
        #expect(deletedAt != nil)
    }

    @Test
    func migratesTheExistingSchemaWithoutLosingNotes() async throws {
        let databaseURL = makeDatabaseURL()
        defer { removeDatabase(at: databaseURL) }
        let database = try DatabaseQueue(path: databaseURL.path)
        var legacyMigrator = DatabaseMigrator()
        legacyMigrator.registerMigration("v1_create_notes") { database in
            try database.create(table: Note.databaseTableName) { table in
                table.column("id", .text).primaryKey()
                table.column("content", .text).notNull()
                table.column("createdAt", .datetime).notNull()
                table.column("updatedAt", .datetime).notNull()
            }
        }
        try legacyMigrator.migrate(database)

        let noteID = UUID()
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        try await database.write { database in
            try database.execute(
                sql: "INSERT INTO notes (id, content, createdAt, updatedAt) VALUES (?, ?, ?, ?)",
                arguments: [noteID, "preserve this note", timestamp, timestamp]
            )
        }

        let repository = try NoteRepository(databaseURL: databaseURL)

        #expect(try await repository.fetch(id: noteID)?.content == "preserve this note")
        let columns = try await database.read { database in
            try database.columns(in: Note.databaseTableName).map(\.name)
        }
        #expect(columns == ["id", "content", "created_at", "updated_at", "deleted_at"])
    }

    private func makeRepository() throws -> NoteRepository {
        try NoteRepository(databaseURL: makeDatabaseURL())
    }

    private func makeDatabaseURL() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appendingPathExtension("sqlite")
    }

    private func removeDatabase(at databaseURL: URL) {
        try? FileManager.default.removeItem(at: databaseURL)
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: databaseURL.path + "-shm"))
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: databaseURL.path + "-wal"))
    }
}

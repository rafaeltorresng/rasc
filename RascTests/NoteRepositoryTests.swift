import Foundation
import GRDB
import Testing
@testable import Rasc

@Suite(.serialized)
struct NoteRepositoryTests {
    @Test
    func derivesHistoryTextFromNoteContent() {
        let note = Note(
            id: UUID(),
            content: "\n  Queue retry issue  \n\nCheck next_retry_at after deploy.\n",
            createdAt: .distantPast,
            updatedAt: .distantPast,
            deletedAt: nil,
            keptAt: nil
        )

        #expect(note.displayTitle == "Queue retry issue")
        #expect(note.displaySnippet == "Check next_retry_at after deploy.")
    }

    @Test
    func retrievalSnippetAvoidsRepeatingTitlePrefix() {
        let note = Note(
            id: UUID(),
            content: "Queue retry issue\nQueue retry issue after deploy.",
            createdAt: .distantPast,
            updatedAt: .distantPast,
            deletedAt: nil,
            keptAt: nil
        )

        #expect(note.displayRetrievalSnippet == "after deploy.")
    }

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
        #expect(columns == ["id", "content", "created_at", "updated_at", "deleted_at", "kept_at"])
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

    @Test
    func updateWithUnchangedContentPreservesUpdatedAt() async throws {
        let repository = try makeRepository()
        let created = try await repository.createScratch(content: "stable note")
        let originalUpdatedAt = try #require(try await repository.fetch(id: created.id)?.updatedAt)

        try await Task.sleep(for: .milliseconds(10))
        try await repository.update(id: created.id, content: "stable note")

        let fetched = try await repository.fetch(id: created.id)
        #expect(fetched?.content == "stable note")
        #expect(fetched?.updatedAt == originalUpdatedAt)
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
    func returnsRecentNotesByUpdatedAtDescending() async throws {
        let databaseURL = makeDatabaseURL()
        defer { removeDatabase(at: databaseURL) }
        let repository = try NoteRepository(databaseURL: databaseURL)
        let first = try await repository.createScratch(content: "first")
        let second = try await repository.createScratch(content: "second")
        let third = try await repository.createScratch(content: "third")
        let database = try DatabaseQueue(path: databaseURL.path)
        try await database.write { database in
            try database.execute(
                sql: "UPDATE notes SET updated_at = ? WHERE id = ?",
                arguments: [Date(timeIntervalSince1970: 100), first.id]
            )
            try database.execute(
                sql: "UPDATE notes SET updated_at = ? WHERE id = ?",
                arguments: [Date(timeIntervalSince1970: 300), second.id]
            )
            try database.execute(
                sql: "UPDATE notes SET updated_at = ? WHERE id = ?",
                arguments: [Date(timeIntervalSince1970: 200), third.id]
            )
        }

        let recent = try await repository.recent(limit: 3)

        #expect(recent.map(\.id) == [second.id, third.id, first.id])
    }

    @Test
    func excludesDeletedNotesFromRecentAndSearch() async throws {
        let repository = try makeRepository()
        let visible = try await repository.createScratch(content: "visible queue note")
        let deleted = try await repository.createScratch(content: "deleted queue note")
        try await repository.delete(id: deleted.id)

        #expect(try await repository.recent(limit: 10).map(\.id) == [visible.id])
        #expect(try await repository.search("queue", limit: 10).map(\.id) == [visible.id])
    }

    @Test
    func searchesByExactWord() async throws {
        let repository = try makeRepository()
        let matching = try await repository.createScratch(content: "Investigate the queue retry")
        _ = try await repository.createScratch(content: "Review window focus")

        #expect(try await repository.search("queue", limit: 10).map(\.id) == [matching.id])
    }

    @Test
    func searchesByAllTermPrefixes() async throws {
        let repository = try makeRepository()
        let matching = try await repository.createScratch(content: "Caramuru queue retry investigation")
        _ = try await repository.createScratch(content: "Caramel recipe")

        #expect(try await repository.search("caram que", limit: 10).map(\.id) == [matching.id])
    }

    @Test
    func searchesPortugueseTextWithoutRequiringDiacritics() async throws {
        let repository = try makeRepository()
        let matching = try await repository.createScratch(
            content: "João revisa a ação no café depois do deploy"
        )

        #expect(try await repository.search("joao acao cafe", limit: 10).map(\.id) == [matching.id])
    }

    @Test
    func searchesMixedLanguageTechnicalIdentifiers() async throws {
        let repository = try makeRepository()
        let matching = try await repository.createScratch(
            content: "Atualizar next_retry_at after the queue succeeds"
        )

        #expect(try await repository.search("atual next_retry", limit: 10).map(\.id) == [matching.id])
    }

    @Test
    func searchesURLsAndUUIDLikeStrings() async throws {
        let repository = try makeRepository()
        let matching = try await repository.createScratch(
            content: "See https://example.com/api/v2/jobs/550e8400-e29b-41d4-a716-446655440000"
        )

        #expect(try await repository.search("example.com/api", limit: 10).map(\.id) == [matching.id])
        #expect(try await repository.search("550e8400-e29b", limit: 10).map(\.id) == [matching.id])
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
        #expect(columns == ["id", "content", "created_at", "updated_at", "deleted_at", "kept_at"])
    }

    @Test
    func migratesM1NotesIntoTheFTSIndexWithoutDataLoss() async throws {
        let databaseURL = makeDatabaseURL()
        defer { removeDatabase(at: databaseURL) }
        let database = try DatabaseQueue(path: databaseURL.path)
        var m1Migrator = DatabaseMigrator()
        m1Migrator.registerMigration("v1_create_notes") { database in
            try database.create(table: Note.databaseTableName) { table in
                table.column("id", .text).primaryKey()
                table.column("content", .text).notNull()
                table.column("createdAt", .datetime).notNull()
                table.column("updatedAt", .datetime).notNull()
            }
        }
        m1Migrator.registerMigration("v2_m1_notes_schema") { database in
            try database.alter(table: Note.databaseTableName) { table in
                table.rename(column: "createdAt", to: "created_at")
                table.rename(column: "updatedAt", to: "updated_at")
                table.add(column: "deleted_at", .datetime)
            }
        }
        try m1Migrator.migrate(database)

        let noteID = UUID()
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        try await database.write { database in
            try database.execute(
                sql: "INSERT INTO notes (id, content, created_at, updated_at) VALUES (?, ?, ?, ?)",
                arguments: [noteID, "M1 café queue note", timestamp, timestamp]
            )
        }

        let repository = try NoteRepository(databaseURL: databaseURL)

        #expect(try await repository.fetch(id: noteID)?.content == "M1 café queue note")
        #expect(try await repository.search("cafe que", limit: 10).map(\.id) == [noteID])
        let ftsTableExists = try await database.read { database in
            try Bool.fetchOne(
                database,
                sql: "SELECT EXISTS(SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'notes_fts')"
            )
        }
        #expect(ftsTableExists == true)
    }

    @Test
    func migratesM2DatabaseToRefinementRevisionsWithoutLosingNotes() async throws {
        let databaseURL = makeDatabaseURL()
        defer { removeDatabase(at: databaseURL) }
        let database = try DatabaseQueue(path: databaseURL.path)
        var m2Migrator = DatabaseMigrator()
        m2Migrator.registerMigration("v1_create_notes") { database in
            try database.create(table: Note.databaseTableName) { table in
                table.column("id", .text).primaryKey()
                table.column("content", .text).notNull()
                table.column("createdAt", .datetime).notNull()
                table.column("updatedAt", .datetime).notNull()
            }
        }
        m2Migrator.registerMigration("v2_m1_notes_schema") { database in
            try database.alter(table: Note.databaseTableName) { table in
                table.rename(column: "createdAt", to: "created_at")
                table.rename(column: "updatedAt", to: "updated_at")
                table.add(column: "deleted_at", .datetime)
            }
        }
        m2Migrator.registerMigration("v3_m2_create_notes_fts") { database in
            try database.create(virtualTable: "notes_fts", using: FTS5()) { table in
                table.synchronize(withTable: Note.databaseTableName)
                table.tokenizer = .unicode61(diacritics: .remove)
                table.prefixes = [2, 3, 4]
                table.column("content")
            }
        }
        try m2Migrator.migrate(database)

        let noteID = UUID()
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        try await database.write { database in
            try database.execute(
                sql: "INSERT INTO notes (id, content, created_at, updated_at) VALUES (?, ?, ?, ?)",
                arguments: [noteID, "preserve before refinement migration", timestamp, timestamp]
            )
        }

        let repository = try NoteRepository(databaseURL: databaseURL)

        #expect(try await repository.fetch(id: noteID)?.content == "preserve before refinement migration")
        let revisionColumns = try await database.read { database in
            try database.columns(in: "refinement_revisions").map(\.name)
        }
        #expect(revisionColumns == [
            "id",
            "note_id",
            "before_content",
            "after_content",
            "provider",
            "model_identifier",
            "prompt_version",
            "created_at",
        ])
        let revisionCount = try await database.read { database in
            try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM refinement_revisions")
        }
        #expect(revisionCount == 0)
    }

    @Test
    func opensExistingDatabaseAtCurrentSchemaWithoutDataLoss() async throws {
        let databaseURL = makeDatabaseURL()
        defer { removeDatabase(at: databaseURL) }
        let database = try DatabaseQueue(path: databaseURL.path)
        try AppDatabase.migrator.migrate(database)

        let noteID = UUID()
        let timestamp = Date(timeIntervalSince1970: 1_700_000_100)
        try await database.write { database in
            try database.execute(
                sql: """
                INSERT INTO notes (id, content, created_at, updated_at)
                VALUES (?, ?, ?, ?)
                """,
                arguments: [noteID, "existing beta note", timestamp, timestamp]
            )
            try database.execute(
                sql: """
                INSERT INTO refinement_revisions (
                    id, note_id, before_content, after_content, provider,
                    model_identifier, prompt_version, created_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    UUID(),
                    noteID,
                    "existing beta note",
                    "existing beta note refined",
                    "foundation-models",
                    "system-language-model.default",
                    "refine-v1",
                    timestamp,
                ]
            )
        }

        let repository = try NoteRepository(databaseURL: databaseURL)
        let note = try #require(try await repository.fetch(id: noteID))
        #expect(note.content == "existing beta note")

        let searchResults = try await repository.search("beta", limit: 20)
        #expect(searchResults.contains(where: { $0.id == noteID }))

        let revisions = try await repository.refinementRevisions(for: noteID)
        #expect(revisions.count == 1)
        #expect(revisions[0].afterContent == "existing beta note refined")
    }

    @Test
    func acceptsARefinementAndWritesOneCompleteRevisionAtomically() async throws {
        let repository = try makeRepository()
        let note = try await repository.createScratch(content: "rough café 👩🏽‍💻 note")
        let metadata = RefinementMetadata(
            provider: "foundation-models",
            modelIdentifier: "system-language-model.default",
            promptVersion: "refine-v1"
        )

        let revision = try await repository.acceptRefinement(
            noteID: note.id,
            beforeContent: note.content,
            afterContent: "Clear café 👩🏽‍💻 note.",
            metadata: metadata
        )

        #expect(try await repository.fetch(id: note.id)?.content == "Clear café 👩🏽‍💻 note.")
        #expect(revision.noteID == note.id)
        #expect(revision.beforeContent == "rough café 👩🏽‍💻 note")
        #expect(revision.afterContent == "Clear café 👩🏽‍💻 note.")
        #expect(revision.provider == metadata.provider)
        #expect(revision.modelIdentifier == metadata.modelIdentifier)
        #expect(revision.promptVersion == metadata.promptVersion)
        let persistedRevisions = try await repository.refinementRevisions(for: note.id)
        let persisted = try #require(persistedRevisions.first)
        #expect(persistedRevisions.count == 1)
        #expect(persisted.id == revision.id)
        #expect(persisted.noteID == revision.noteID)
        #expect(persisted.beforeContent == revision.beforeContent)
        #expect(persisted.afterContent == revision.afterContent)
        #expect(persisted.provider == revision.provider)
        #expect(persisted.modelIdentifier == revision.modelIdentifier)
        #expect(persisted.promptVersion == revision.promptVersion)
        #expect(abs(persisted.createdAt.timeIntervalSince(revision.createdAt)) < 0.001)
    }

    @Test
    func staleAcceptedRefinementLeavesTheNoteAndRevisionTableUntouched() async throws {
        let repository = try makeRepository()
        let note = try await repository.createScratch(content: "newer content")
        let metadata = RefinementMetadata(
            provider: "fake",
            modelIdentifier: "fake-v1",
            promptVersion: "refine-v1"
        )

        do {
            _ = try await repository.acceptRefinement(
                noteID: note.id,
                beforeContent: "stale content",
                afterContent: "stale rewrite",
                metadata: metadata
            )
            Issue.record("A stale refinement was accepted")
        } catch NoteRepository.PersistenceError.staleContent {
            // Expected.
        }

        #expect(try await repository.fetch(id: note.id)?.content == "newer content")
        #expect(try await repository.refinementRevisions(for: note.id).isEmpty)
    }

    @Test
    func noOpAcceptedRefinementDoesNotWriteARevision() async throws {
        let repository = try makeRepository()
        let note = try await repository.createScratch(content: "Already useful.")
        let metadata = RefinementMetadata(
            provider: "fake",
            modelIdentifier: "fake-v1",
            promptVersion: "refine-v1"
        )

        do {
            _ = try await repository.acceptRefinement(
                noteID: note.id,
                beforeContent: note.content,
                afterContent: note.content,
                metadata: metadata
            )
            Issue.record("A no-op refinement wrote a revision")
        } catch NoteRepository.PersistenceError.noContentChange {
            // Expected.
        }

        #expect(try await repository.fetch(id: note.id)?.content == "Already useful.")
        #expect(try await repository.refinementRevisions(for: note.id).isEmpty)
    }

    @Test
    func keepAndUnkeepPersistKeptAtWithoutChangingContent() async throws {
        let repository = try makeRepository()
        let note = try await repository.createScratch(content: "finish this thought")

        let kept = try await repository.keep(id: note.id)
        #expect(kept.content == "finish this thought")
        #expect(kept.keptAt != nil)
        #expect(kept.isKept)

        let fetched = try #require(try await repository.fetch(id: note.id))
        #expect(fetched.isKept)

        let searchResults = try await repository.search("finish", limit: 10)
        #expect(searchResults.contains(where: { $0.id == note.id && $0.isKept }))

        let unkept = try await repository.unkeep(id: note.id)
        #expect(unkept.content == "finish this thought")
        #expect(unkept.keptAt == nil)
        #expect(try await repository.fetch(id: note.id)?.isKept == false)
    }

    @Test
    func migratesM3ADatabaseToKeptAtWithoutLosingNotes() async throws {
        let databaseURL = makeDatabaseURL()
        defer { removeDatabase(at: databaseURL) }
        let database = try DatabaseQueue(path: databaseURL.path)
        var partialMigrator = DatabaseMigrator()
        partialMigrator.registerMigration("v1_create_notes") { database in
            try database.create(table: Note.databaseTableName) { table in
                table.column("id", .text).primaryKey()
                table.column("content", .text).notNull()
                table.column("createdAt", .datetime).notNull()
                table.column("updatedAt", .datetime).notNull()
            }
        }
        partialMigrator.registerMigration("v2_m1_notes_schema") { database in
            try database.alter(table: Note.databaseTableName) { table in
                table.rename(column: "createdAt", to: "created_at")
                table.rename(column: "updatedAt", to: "updated_at")
                table.add(column: "deleted_at", .datetime)
            }
        }
        partialMigrator.registerMigration("v3_m2_create_notes_fts") { database in
            try database.create(virtualTable: "notes_fts", using: FTS5()) { table in
                table.synchronize(withTable: Note.databaseTableName)
                table.tokenizer = .unicode61(diacritics: .remove)
                table.prefixes = [2, 3, 4]
                table.column("content")
            }
        }
        partialMigrator.registerMigration("v4_m3a_create_refinement_revisions") { database in
            try database.create(table: "refinement_revisions") { table in
                table.column("id", .text).primaryKey()
                table.column("note_id", .text).notNull().indexed().references(Note.databaseTableName)
                table.column("before_content", .text).notNull()
                table.column("after_content", .text).notNull()
                table.column("provider", .text).notNull()
                table.column("model_identifier", .text).notNull()
                table.column("prompt_version", .text).notNull()
                table.column("created_at", .datetime).notNull()
            }
        }
        try partialMigrator.migrate(database)

        let noteID = UUID()
        let timestamp = Date(timeIntervalSince1970: 1_700_000_200)
        try await database.write { database in
            try database.execute(
                sql: """
                INSERT INTO notes (id, content, created_at, updated_at)
                VALUES (?, ?, ?, ?)
                """,
                arguments: [noteID, "legacy beta note", timestamp, timestamp]
            )
        }

        let repository = try NoteRepository(databaseURL: databaseURL)
        let note = try #require(try await repository.fetch(id: noteID))
        #expect(note.content == "legacy beta note")
        #expect(note.keptAt == nil)
        #expect(note.isKept == false)

        let columns = try await database.read { database in
            try database.columns(in: Note.databaseTableName).map(\.name)
        }
        #expect(columns.contains("kept_at"))
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

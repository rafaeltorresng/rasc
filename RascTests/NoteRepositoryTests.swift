import Foundation
import AppKit
import ImageIO
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

    @Test(arguments: ["", "  \n\t "])
    func emptyContentUsesAReadableTitle(content: String) {
        let note = Note(
            id: UUID(),
            content: content,
            createdAt: .distantPast,
            updatedAt: .distantPast,
            deletedAt: nil,
            keptAt: nil
        )

        #expect(note.displayTitle == "Empty thought")
        #expect(note.displaySnippet == nil)
    }

    @Test
    func meaningfulContentRequiresTextOrImages() {
        func note(content: String, hasImages: Bool = false) -> Note {
            Note(
                id: UUID(),
                content: content,
                createdAt: .distantPast,
                updatedAt: .distantPast,
                deletedAt: nil,
                keptAt: nil,
                hasImages: hasImages
            )
        }

        #expect(!note(content: "  \n\t ").hasMeaningfulContent)
        #expect(note(content: "thought").hasMeaningfulContent)
        #expect(note(content: "", hasImages: true).hasMeaningfulContent)
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
        #expect(columns == ["id", "content", "created_at", "updated_at", "deleted_at", "kept_at", "has_images"])
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
    func clearingAnExistingNotePreservesItsIdentity(content: String) async throws {
        let databaseURL = makeDatabaseURL()
        defer { removeDatabase(at: databaseURL) }
        let repository = try NoteRepository(databaseURL: databaseURL)
        let created = try await repository.createScratch(content: "original thought")
        let persisted = try #require(try await repository.fetch(id: created.id))

        try await repository.update(id: created.id, content: content)

        let stored = try #require(try await repository.fetch(id: created.id))
        #expect(stored.id == created.id)
        #expect(stored.content == content)
        #expect(stored.createdAt == persisted.createdAt)
        #expect(stored.updatedAt >= persisted.updatedAt)
        #expect(stored.deletedAt == nil)
        #expect(stored.keptAt == nil)
        #expect(try await repository.fetchAllNonDeleted().map(\.id) == [created.id])
        #expect(try rowCount(at: databaseURL) == 1)
        #expect(try await repository.search("original", limit: 10).isEmpty)
        #expect(try await repository.recent(limit: 10).map(\.id) == [created.id])
    }

    @Test
    func clearingAKeptNotePreservesKeptAt() async throws {
        let repository = try makeRepository()
        let created = try await repository.createScratch(content: "keep me")
        let kept = try await repository.keep(id: created.id)

        try await repository.update(id: created.id, content: "")

        let stored = try #require(try await repository.fetch(id: created.id))
        #expect(stored.id == kept.id)
        #expect(stored.content == "")
        #expect(stored.keptAt == kept.keptAt)
        #expect(stored.isKept)
        await #expect(throws: NoteRepository.PersistenceError.emptyContent) {
            try await repository.keep(id: created.id)
        }
        await #expect(throws: NoteRepository.PersistenceError.emptyContent) {
            try await repository.duplicate(id: created.id)
        }
    }

    @Test
    func clearingADiscardedNoteDoesNotReportSuccess() async throws {
        let repository = try makeRepository()
        let created = try await repository.createScratch(content: "original")
        let receipt = try #require(try await repository.delete(id: created.id))

        await #expect(throws: NoteRepository.PersistenceError.staleContent) {
            try await repository.update(id: created.id, content: "")
        }
        #expect(try await repository.fetch(id: created.id) == nil)
        #expect(try await repository.restoreDiscard(receipt).content == "original")
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

    @Test
    func updatingAMissingNoteReportsFailure() async throws {
        let repository = try makeRepository()
        await #expect(throws: NoteRepository.PersistenceError.staleContent) {
            try await repository.update(id: UUID(), content: "unsaved edit")
        }
    }

    @Test
    func updatingADiscardedNoteDoesNotReportASuccessfulSave() async throws {
        let repository = try makeRepository()
        let note = try await repository.createScratch(content: "original")
        let receipt = try #require(try await repository.delete(id: note.id))

        await #expect(throws: NoteRepository.PersistenceError.staleContent) {
            try await repository.update(id: note.id, content: "unsaved edit")
        }
        #expect(try await repository.restoreDiscard(receipt).content == "original")
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
        #expect(columns == ["id", "content", "created_at", "updated_at", "deleted_at", "kept_at", "has_images"])
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

    private func rowCount(at databaseURL: URL) throws -> Int {
        try DatabaseQueue(path: databaseURL.path).read { database in
            try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM notes") ?? 0
        }
    }

    @Test
    func migrationPreservesEmptyKeptAndDiscardedNotes() async throws {
        let url = makeDatabaseURL()
        defer { removeDatabase(at: url) }
        let db = try DatabaseQueue(path: url.path)
        try AppDatabase.migrator.migrate(db, upTo: "v5_m16_notes_kept_at")
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let notes = [
            Note(id: UUID(), content: "", createdAt: date, updatedAt: date, deletedAt: nil, keptAt: date),
            Note(id: UUID(), content: "discarded text", createdAt: date, updatedAt: date, deletedAt: date, keptAt: nil),
            Note(id: UUID(), content: "ordinary text", createdAt: date, updatedAt: date, deletedAt: nil, keptAt: nil),
        ]
        try await db.write { db in
            for note in notes {
                try db.execute(sql: "INSERT INTO notes (id, content, created_at, updated_at, deleted_at, kept_at) VALUES (?, ?, ?, ?, ?, ?)", arguments: [note.id, note.content, note.createdAt, note.updatedAt, note.deletedAt, note.keptAt])
            }
        }
        let repository = try NoteRepository(databaseURL: url)
        let reopened = try AppDatabase.open(at: url)
        let stored = try await reopened.read { db in try Note.fetchAll(db) }
        #expect(stored.sorted { $0.id.uuidString < $1.id.uuidString } == notes.sorted { $0.id.uuidString < $1.id.uuidString })
        #expect(try await repository.fetchDocument(id: notes[0].id) == NoteDocument(parts: [.text("")]))
        #expect(try await repository.search("ordinary", limit: 10).map(\.id) == [notes[2].id])
    }

    @Test
    func migrationAddsImageIndicatorToExistingDocuments() async throws {
        let url = makeDatabaseURL()
        defer { removeDatabase(at: url) }
        let db = try DatabaseQueue(path: url.path)
        try AppDatabase.migrator.migrate(db, upTo: "v6_structured_note_content")
        let id = UUID()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let document = NoteDocument(parts: [.image(data: testPNG, typeIdentifier: "public.png")])
        let bytes = try PropertyListEncoder().encode(document)
        try await db.write { db in
            try db.execute(sql: "INSERT INTO notes (id, content, created_at, updated_at) VALUES (?, ?, ?, ?)", arguments: [id, document.text, date, date])
            try db.execute(sql: "INSERT INTO note_documents (note_id, document) VALUES (?, ?)", arguments: [id, bytes])
        }
        let repository = try NoteRepository(databaseURL: url)
        let note = try #require(try await repository.fetch(id: id))
        #expect(note.hasImages)
        #expect(note.displayTitle == "Image")
        #expect(try await repository.fetchDocument(id: id) == document)
    }

    @Test
    func migratesV7DocumentsWithoutRewritingImagesOrExposingStaleContentToOlderVersions() async throws {
        let url = makeDatabaseURL()
        defer { removeDatabase(at: url) }
        let db = try DatabaseQueue(path: url.path)
        try AppDatabase.migrator.migrate(db, upTo: "v7_note_image_indicator")
        let id = UUID()
        let discardedID = UUID()
        let emptyID = UUID()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let document = NoteDocument(parts: [.text("legacy\n"), .image(data: testPNG, typeIdentifier: "public.png")])
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let original = try encoder.encode(document)
        try await db.write { db in
            try db.execute(sql: "INSERT INTO notes (id, content, created_at, updated_at, kept_at, has_images) VALUES (?, ?, ?, ?, ?, 1)", arguments: [id, document.text, date, date, date])
            try db.execute(sql: "INSERT INTO note_documents (note_id, document) VALUES (?, ?)", arguments: [id, original])
            try db.execute(sql: "INSERT INTO notes (id, content, created_at, updated_at, deleted_at, has_images) VALUES (?, ?, ?, ?, ?, 1)", arguments: [discardedID, document.text, date, date, date])
            try db.execute(sql: "INSERT INTO note_documents (note_id, document) VALUES (?, ?)", arguments: [discardedID, original])
            try db.execute(sql: "INSERT INTO notes (id, content, created_at, updated_at) VALUES (?, '', ?, ?)", arguments: [emptyID, date, date])
        }
        let repository = try NoteRepository(databaseURL: url)
        let kept = try #require(try await repository.fetch(id: id))
        #expect(kept.isKept && kept.hasImages && kept.createdAt == date)
        #expect(try await repository.fetchDocument(id: id) == document)
        #expect(try await repository.fetch(id: discardedID) == nil)
        #expect(try await repository.fetch(id: emptyID)?.content == "")
        let migrated = try AppDatabase.open(at: url)
        let stored = try await migrated.read { db in
            (try Data.fetchOne(db, sql: "SELECT document FROM note_document_bases WHERE note_id = ?", arguments: [id]),
             try Data.fetchOne(db, sql: "SELECT document FROM note_documents WHERE note_id = ?", arguments: [id]),
             try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM note_document_edits"))
        }
        #expect(stored.0 == original)
        let legacyValue = try #require(stored.1)
        #expect(throws: (any Error).self) { try PropertyListDecoder().decode(NoteDocument.self, from: legacyValue) }
        await #expect(throws: (any Error).self) {
            try await migrated.write { db in
                try db.execute(sql: "UPDATE note_documents SET document = ? WHERE note_id = ?", arguments: [original, id])
            }
        }
        #expect(try await repository.fetchDocument(id: id) == document)
        #expect(stored.2 == 2)
    }

    private var testPNG: Data {
        Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==")!
    }

    @Test(arguments: [
        (0, "\u{fffc}\nHello world", 2),
        (5, "Hello\n\u{fffc}\n world", 8),
        (11, "Hello world\n\u{fffc}\n", 14),
    ])
    func insertingImagePreservesTextAtCursor(offset: Int, expected: String, caret: Int) throws {
        let original = NoteDocument(parts: [.text("Hello world")])
        let result = try original.insertingImage(data: testPNG, typeIdentifier: "public.png", replacing: NSRange(location: offset, length: 0))
        #expect(result.document.editorText == expected)
        #expect(result.caretUTF16Offset == caret)
        #expect(result.document.text.replacingOccurrences(of: "\n", with: "") == "Hello world")
    }

    @Test
    func imageInsertionReplacesSelectionAndKeepsOtherImages() throws {
        let original = NoteDocument(parts: [.text("start\n"), .image(data: testPNG, typeIdentifier: "public.png"), .text("\nreplace this end")])
        let range = (original.editorText as NSString).range(of: "replace this")
        let result = try original.insertingImage(data: testPNG, typeIdentifier: "public.png", replacing: range)
        #expect(result.document.editorText == "start\n\u{fffc}\n\u{fffc}\n end")
        #expect(result.document.parts.filter { if case .image = $0 { true } else { false } }.count == 2)
    }

    @Test
    func imageImportCopiesOriginalFileAndRejectsInvalidData() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        defer { try? FileManager.default.removeItem(at: url) }
        try testPNG.write(to: url)
        let imported = try await NoteImageImport.load(.file(url))
        try FileManager.default.removeItem(at: url)
        #expect(imported == .image(data: testPNG, typeIdentifier: "public.png"))
        await #expect(throws: NoteImageImport.ImportError.invalidImage) {
            try await NoteImageImport.load(.data(Data([1, 2, 3])))
        }
        await #expect(throws: NoteImageImport.ImportError.notLocalFile) {
            try await NoteImageImport.load(.file(URL(string: "https://example.invalid/image.png")!))
        }
    }

    @Test
    func imageImportRejectsOversizedFileBeforeReadingIt() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(NoteImageImport.maximumBytes + 1))
        try handle.close()
        await #expect(throws: NoteImageImport.ImportError.tooLarge) {
            try await NoteImageImport.load(.file(url))
        }
    }

    @Test
    @MainActor
    func importsCommonImageFormatsWithoutChangingOriginalBytes() async throws {
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 8, pixelsHigh: 8, bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        for x in 0..<8 { for y in 0..<8 { bitmap.setColor(.red, atX: x, y: y) } }
        for (format, type) in [(NSBitmapImageRep.FileType.png, "public.png"), (.jpeg, "public.jpeg"), (.tiff, "public.tiff")] {
            let data = try #require(bitmap.representation(using: format, properties: [:]))
            let image = try await NoteImageImport.load(.data(data))
            #expect(image == .image(data: data, typeIdentifier: type))
        }
    }

    @Test
    func imageImportRejectsClipboardThatChanged() async throws {
        let board = NSPasteboard(name: .init("RascTests.\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        board.clearContents()
        board.setData(testPNG, forType: .png)
        let source = NoteImageImport.Source.pasteboard(name: board.name.rawValue, type: NSPasteboard.PasteboardType.png.rawValue, changeCount: board.changeCount)
        let imported = try await NoteImageImport.load(source)
        #expect(imported == .image(data: testPNG, typeIdentifier: "public.png"))
        board.clearContents()
        await #expect(throws: NoteImageImport.ImportError.clipboardChanged) {
            try await NoteImageImport.load(source)
        }
    }

    @Test
    func imageInsertionRejectsInvalidUnicodeAndOutOfRangeSelections() throws {
        let original = NoteDocument(parts: [.text("a😀b")])
        #expect(throws: NoteDocument.EditError.invalidSelection) {
            try original.insertingImage(data: testPNG, typeIdentifier: "public.png", replacing: NSRange(location: 2, length: 0))
        }
        #expect(throws: NoteDocument.EditError.invalidSelection) {
            try original.insertingImage(data: testPNG, typeIdentifier: "public.png", replacing: NSRange(location: 99, length: 1))
        }
    }

    @Test
    func importedInlineImagesBecomeSeparateLines() {
        let document = NoteDocument(parts: [.text("before"), .image(data: testPNG, typeIdentifier: "public.png"), .text("after")])
        #expect(document.placingImagesOnSeparateLines().editorText == "before\n\u{fffc}\nafter")
    }

    @Test
    func adjacentTextPartsHaveOneStableRepresentation() {
        let document = NoteDocument(parts: [.text("first"), .text(""), .text(" second")])
        #expect(document.parts == [.text("first second")])
        #expect(NoteDocument(parts: []).parts == [.text("")])
    }

    @Test
    @MainActor
    func measuresTextAutosaveWithARepresentativeImage() async throws {
        let width = 2048, height = 2048, stride = width * 3
        var pixels = Data(count: stride * height)
        pixels.withUnsafeMutableBytes { bytes in arc4random_buf(bytes.baseAddress, bytes.count) }
        let provider = try #require(CGDataProvider(data: pixels as CFData))
        let image = try #require(CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 24, bytesPerRow: stride, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        let output = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(output, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        let bytes = output as Data
        let databaseURL = makeDatabaseURL()
        defer { removeDatabase(at: databaseURL) }
        let repository = try NoteRepository(databaseURL: databaseURL)
        let original = NoteDocument(parts: [.text("before\n"), .image(data: bytes, typeIdentifier: "public.png"), .text("\nafter")])
        let note = try await repository.createScratch(document: original)
        let suite = "RascBenchmark.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let session = ScratchpadSession(repository: repository, userDefaults: defaults)
        #expect(try await session.openNote(id: note.id))
        var milliseconds: [Int] = []
        for index in 0..<3 {
            session.replaceDocumentFromEditor(NoteDocument(parts: [.text("before \(index)\n"), .image(data: bytes, typeIdentifier: "public.png"), .text("\nafter")]))
            let start = ContinuousClock.now
            try await session.flush()
            let duration = start.duration(to: .now)
            milliseconds.append(Int(duration.components.seconds * 1000 + duration.components.attoseconds / 1_000_000_000_000_000))
        }
        print("RASC_IMAGE_AUTOSAVE_BENCHMARK bytes=\(bytes.count) milliseconds=\(milliseconds)")
        #expect(try await repository.fetchDocument(id: note.id) == session.document)
        try repository.closeForTesting()
    }

    @Test
    func textEditsLeaveTheStoredImageBlobUntouched() async throws {
        let url = makeDatabaseURL()
        defer { removeDatabase(at: url) }
        let repository = try NoteRepository(databaseURL: url)
        let original = NoteDocument(parts: [.text("before\n"), .image(data: testPNG, typeIdentifier: "public.png"), .text("\nafter")])
        let note = try await repository.createScratch(document: original)
        let db = try DatabaseQueue(path: url.path)
        let oldBytes = try await db.read { db in try Data.fetchOne(db, sql: "SELECT document FROM note_document_bases WHERE note_id = ?", arguments: [note.id]) }
        try await db.write { db in
            try db.execute(sql: "CREATE TRIGGER reject_image_blob_update BEFORE UPDATE OF document ON note_document_bases BEGIN SELECT RAISE(ABORT, 'image was rewritten'); END")
        }
        let changed = NoteDocument(parts: [.text("updated\n"), .image(data: testPNG, typeIdentifier: "public.png"), .text("\nending")])
        try await repository.update(id: note.id, document: changed, ifCurrent: original)
        let newBytes = try await db.read { db in try Data.fetchOne(db, sql: "SELECT document FROM note_document_bases WHERE note_id = ?", arguments: [note.id]) }
        #expect(newBytes == oldBytes)
        let reopened = try NoteRepository(databaseURL: url)
        #expect(try await reopened.fetchDocument(id: note.id) == changed)
        #expect(try await reopened.search("updated", limit: 10).map(\.id) == [note.id])
        let copy = try await reopened.duplicate(id: note.id)
        #expect(try await reopened.fetchDocument(id: copy.id) == changed)
        _ = try await reopened.keep(id: note.id)
        let receipt = try #require(try await reopened.delete(id: note.id))
        _ = try await reopened.restoreDiscard(receipt)
        #expect(try await reopened.fetchDocument(id: note.id) == changed)
    }

    @Test
    func staleTextEditCannotOverwriteChangedImagesWithSameProjection() async throws {
        let url = makeDatabaseURL()
        defer { removeDatabase(at: url) }
        let writer = try NoteRepository(databaseURL: url)
        let reader = try NoteRepository(databaseURL: url)
        let first = NoteDocument(parts: [.text("same"), .image(data: testPNG, typeIdentifier: "public.png")])
        let note = try await writer.createScratch(document: first)
        #expect(try await reader.fetchDocument(id: note.id) == first)
        let otherImage = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNgYPj/HwADAgH/5ncLrgAAAABJRU5ErkJggg==")!
        let newer = NoteDocument(parts: [.text("same"), .image(data: otherImage, typeIdentifier: "public.png")])
        try await writer.update(id: note.id, document: newer, ifCurrent: first)
        let stale = NoteDocument(parts: [.text("stale"), .image(data: testPNG, typeIdentifier: "public.png")])
        await #expect(throws: NoteRepository.PersistenceError.staleContent) { try await reader.update(id: note.id, document: stale, ifCurrent: first) }
        #expect(try await reader.fetchDocument(id: note.id) == newer)
    }

    @Test
    func unchangedStructuredDocumentPreservesItsTimestamp() async throws {
        let repository = try makeRepository()
        let document = NoteDocument(parts: [.text("same"), .image(data: testPNG, typeIdentifier: "public.png")])
        let note = try await repository.createScratch(document: document)
        let originalTimestamp = try #require(try await repository.fetch(id: note.id)?.updatedAt)
        try await repository.update(id: note.id, document: document, ifCurrent: document)
        #expect(try await repository.fetch(id: note.id)?.updatedAt == originalTimestamp)
    }

    @Test
    func structuredContentSurvivesReopenSearchDuplicationAndDiscard() async throws {
        let url = makeDatabaseURL()
        defer { removeDatabase(at: url) }
        let repository = try NoteRepository(databaseURL: url)
        let document = NoteDocument(parts: [
            .text("Before\n• list item\n"),
            .image(data: testPNG, typeIdentifier: "public.png"),
            .text("\nAfter café"),
            .image(data: testPNG, typeIdentifier: "public.png"),
        ])
        let note = try await repository.createScratch(document: document)
        let reader = try NoteRepository(databaseURL: url)
        #expect(try await reader.fetchDocument(id: note.id) == document)
        #expect(try await reader.search("list", limit: 10).map(\.id) == [note.id])
        #expect(try await reader.search("cafe", limit: 10).map(\.id) == [note.id])

        let changed = NoteDocument(parts: [.text("replacement"), .image(data: testPNG, typeIdentifier: "public.png")])
        try await repository.update(id: note.id, document: changed, ifCurrent: document)
        #expect(try await reader.fetchDocument(id: note.id) == changed)
        #expect(try await reader.search("list", limit: 10).isEmpty)
        #expect(try await reader.search("replacement", limit: 10).map(\.id) == [note.id])
        let copy = try await repository.duplicate(id: note.id)
        #expect(try await repository.fetchDocument(id: copy.id) == changed)
        let receipt = try #require(try await repository.delete(id: note.id))
        #expect(try await repository.fetchDocument(id: note.id) == nil)
        _ = try await repository.restoreDiscard(receipt)
        #expect(try await repository.fetchDocument(id: note.id) == changed)
    }

    @Test
    func textOnlyWritesAndRefinementCannotOverwriteStructuredContent() async throws {
        let repository = try makeRepository()
        let document = NoteDocument(parts: [.text("original"), .image(data: testPNG, typeIdentifier: "public.png")])
        let note = try await repository.createScratch(document: document)
        await #expect(throws: NoteRepository.PersistenceError.structuredContentRequiresDocument) {
            try await repository.update(id: note.id, content: "replacement")
        }
        let metadata = RefinementMetadata(provider: "test", modelIdentifier: "test", promptVersion: "test")
        await #expect(throws: NoteRepository.PersistenceError.structuredContentRequiresDocument) {
            try await repository.acceptRefinement(noteID: note.id, beforeContent: "original", afterContent: "replacement", metadata: metadata)
        }
        #expect(try await repository.fetchDocument(id: note.id) == document)
        #expect(try await repository.refinementRevisions(for: note.id).isEmpty)
    }

    @Test
    func failedProjectionWriteRollsBackDocumentAndSearch() async throws {
        let url = makeDatabaseURL()
        defer { removeDatabase(at: url) }
        let repository = try NoteRepository(databaseURL: url)
        let original = NoteDocument(parts: [.text("original"), .image(data: testPNG, typeIdentifier: "public.png")])
        let note = try await repository.createScratch(document: original)
        let db = try DatabaseQueue(path: url.path)
        try await db.write { db in
            try db.execute(sql: "CREATE TRIGGER reject_content_update BEFORE UPDATE OF content ON notes BEGIN SELECT RAISE(ABORT, 'test failure'); END")
        }
        let replacement = NoteDocument(parts: [.text("replacement"), .image(data: testPNG, typeIdentifier: "public.png")])
        do {
            try await repository.update(id: note.id, document: replacement, ifCurrent: original)
            Issue.record("Expected the transaction to fail")
        } catch { }
        #expect(try await repository.fetchDocument(id: note.id) == original)
        #expect(try await repository.search("original", limit: 10).map(\.id) == [note.id])
        #expect(try await repository.search("replacement", limit: 10).isEmpty)
    }

    @Test
    func staleDocumentUpdateCannotOverwriteNewerImages() async throws {
        let repository = try makeRepository()
        let original = NoteDocument(parts: [.text("same text")])
        let note = try await repository.createScratch(content: original.text)
        let withImage = NoteDocument(parts: [.text("same text"), .image(data: testPNG, typeIdentifier: "public.png")])
        try await repository.update(id: note.id, document: withImage, ifCurrent: original)
        let stale = NoteDocument(parts: [.text("stale edit")])
        await #expect(throws: NoteRepository.PersistenceError.staleContent) {
            try await repository.update(id: note.id, document: stale, ifCurrent: original)
        }
        #expect(try await repository.fetchDocument(id: note.id) == withImage)
    }

    @Test
    func imageOnlyDocumentCanBeKeptAndInvalidImageCannotBeSaved() async throws {
        let repository = try makeRepository()
        let document = NoteDocument(parts: [.image(data: testPNG, typeIdentifier: "public.png")])
        let note = try await repository.createScratch(document: document)
        let kept = try await repository.keep(id: note.id)
        #expect(kept.isKept)
        #expect(kept.hasImages)
        #expect(kept.displayTitle == "Image")
        #expect(try await repository.fetchDocument(id: note.id) == document)
        await #expect(throws: NoteDocument.DocumentError.invalidImage) {
            try await repository.update(id: note.id, document: NoteDocument(parts: [.image(data: Data(), typeIdentifier: "public.png")]), ifCurrent: document)
        }
        #expect(try await repository.fetchDocument(id: note.id) == document)
    }

    @Test
    @MainActor
    func measuresSuffixAutosaveWithARepresentativeImage() async throws {
        let width = 2048, height = 2048, stride = width * 3
        var pixels = Data(count: stride * height)
        pixels.withUnsafeMutableBytes { bytes in arc4random_buf(bytes.baseAddress, bytes.count) }
        let provider = try #require(CGDataProvider(data: pixels as CFData))
        let image = try #require(CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 24, bytesPerRow: stride, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        let output = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(output, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        let bytes = output as Data
        let databaseURL = makeDatabaseURL()
        defer { removeDatabase(at: databaseURL) }
        let repository = try NoteRepository(databaseURL: databaseURL)
        let original = NoteDocument(parts: [.text("before\n"), .image(data: bytes, typeIdentifier: "public.png"), .text("\nafter")])
        let note = try await repository.createScratch(document: original)
        let suite = "RascSuffixBenchmark.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let session = ScratchpadSession(repository: repository, userDefaults: defaults)
        #expect(try await session.openNote(id: note.id))
        var milliseconds: [Int] = []
        for index in 0..<3 {
            session.replaceDocumentFromEditor(NoteDocument(parts: [.text("before\n"), .image(data: bytes, typeIdentifier: "public.png"), .text("\nafter \(index)")]))
            let start = ContinuousClock.now
            try await session.flush()
            let duration = start.duration(to: .now)
            milliseconds.append(Int(duration.components.seconds * 1000 + duration.components.attoseconds / 1_000_000_000_000_000))
        }
        print("RASC_SUFFIX_BENCHMARK bytes=\(bytes.count) milliseconds=\(milliseconds)")
        #expect(try await repository.fetchDocument(id: note.id) == session.document)
        try repository.closeForTesting()
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

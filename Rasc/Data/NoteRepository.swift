import Foundation
import GRDB

/// A receipt identifies one deletion, so a stale Undo cannot restore a later discard.
struct NoteDiscardReceipt: Equatable, Sendable {
    let id = UUID()
    let noteID: UUID
    let deletedAt: Date
}

actor NoteRepository {
    enum PersistenceError: Error {
        case emptyContent
        case noContentChange
        case staleContent
    }

    private let database: DatabaseQueue
    private var discardReceipts: [UUID: NoteDiscardReceipt] = [:]

    nonisolated static var defaultDatabaseURL: URL {
        get throws {
            let applicationSupportDirectory = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            return applicationSupportDirectory
                .appending(path: "Rasc", directoryHint: .isDirectory)
                .appending(path: "Rasc.sqlite")
        }
    }

    nonisolated static func openDefault() throws -> NoteRepository {
        let databaseURL = try defaultDatabaseURL
        let databaseDirectory = databaseURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: databaseDirectory, withIntermediateDirectories: true)
        return try NoteRepository(databaseURL: databaseURL)
    }

    init(databaseURL: URL) throws {
        database = try AppDatabase.open(at: databaseURL)
    }

    #if DEBUG
    nonisolated func closeForTesting() throws {
        try database.close()
    }
    #endif

    func createScratch(content: String) throws -> Note {
        guard Self.hasMeaningfulContent(content) else {
            throw PersistenceError.emptyContent
        }

        return try database.write { database in
            let now = Date()
            let note = Note(
                id: UUID(),
                content: content,
                createdAt: now,
                updatedAt: now,
                deletedAt: nil,
                keptAt: nil
            )
            try note.insert(database)
            return note
        }
    }

    func fetch(id: UUID) throws -> Note? {
        try database.read { database in
            try Note
                .filter(Note.Columns.id == id)
                .filter(Note.Columns.deletedAt == nil)
                .fetchOne(database)
        }
    }

    func update(id: UUID, content: String) throws {
        guard Self.hasMeaningfulContent(content) else {
            try delete(id: id)
            return
        }

        _ = try database.write { database in
            guard let existing = try Note
                .filter(Note.Columns.id == id)
                .filter(Note.Columns.deletedAt == nil)
                .fetchOne(database)
            else {
                // A save must not appear successful after Home discarded this note.
                throw PersistenceError.staleContent
            }

            guard existing.content != content else {
                return
            }

            try Note
                .filter(Note.Columns.id == id)
                .filter(Note.Columns.deletedAt == nil)
                .updateAll(database, [
                    Note.Columns.content.set(to: content),
                    Note.Columns.updatedAt.set(to: Date()),
                ])
        }
    }

    func acceptRefinement(
        noteID: UUID,
        beforeContent: String,
        afterContent: String,
        metadata: RefinementMetadata
    ) throws -> RefinementRevision {
        guard beforeContent != afterContent else {
            throw PersistenceError.noContentChange
        }
        guard Self.hasMeaningfulContent(afterContent) else {
            throw PersistenceError.emptyContent
        }

        return try database.write { database in
            let now = Date()
            let updatedCount = try Note
                .filter(Note.Columns.id == noteID)
                .filter(Note.Columns.deletedAt == nil)
                .filter(Note.Columns.content == beforeContent)
                .updateAll(database, [
                    Note.Columns.content.set(to: afterContent),
                    Note.Columns.updatedAt.set(to: now),
                ])
            guard updatedCount == 1 else {
                throw PersistenceError.staleContent
            }

            let revision = RefinementRevision(
                id: UUID(),
                noteID: noteID,
                beforeContent: beforeContent,
                afterContent: afterContent,
                provider: metadata.provider,
                modelIdentifier: metadata.modelIdentifier,
                promptVersion: metadata.promptVersion,
                createdAt: now
            )
            try revision.insert(database)
            return revision
        }
    }

    func refinementRevisions(for noteID: UUID) throws -> [RefinementRevision] {
        try database.read { database in
            try RefinementRevision
                .filter(Column("note_id") == noteID)
                .order(Column("created_at"), Column.rowID)
                .fetchAll(database)
        }
    }

    func fetchMostRecent() throws -> Note? {
        try database.read { database in
            try Note
                .filter(Note.Columns.deletedAt == nil)
                .order(Note.Columns.updatedAt.desc, Column.rowID.desc)
                .fetchOne(database)
        }
    }

    func recent(limit: Int) throws -> [Note] {
        guard limit > 0 else { return [] }

        return try database.read { database in
            try Note
                .filter(Note.Columns.deletedAt == nil)
                .order(Note.Columns.updatedAt.desc, Column.rowID.desc)
                .limit(limit)
                .fetchAll(database)
        }
    }

    func fetchAllNonDeleted() throws -> [Note] {
        try database.read { database in
            try Note
                .filter(Note.Columns.deletedAt == nil)
                .order(Note.Columns.updatedAt.desc, Column.rowID.desc)
                .fetchAll(database)
        }
    }

    func search(_ query: String, limit: Int) throws -> [Note] {
        let normalizedQuery = query.precomposedStringWithCanonicalMapping
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else {
            return try recent(limit: limit)
        }
        guard limit > 0,
              let pattern = FTS5Pattern(matchingAllPrefixesIn: normalizedQuery)
        else {
            return []
        }

        return try database.read { database in
            try Note.fetchAll(
                database,
                sql: """
                    SELECT notes.*
                    FROM notes
                    JOIN notes_fts ON notes_fts.rowid = notes.rowid
                    WHERE notes_fts MATCH ?
                      AND notes.deleted_at IS NULL
                    ORDER BY bm25(notes_fts), notes.updated_at DESC, notes.rowid DESC
                    LIMIT ?
                    """,
                arguments: [pattern, limit]
            )
        }
    }

    @discardableResult
    func delete(id: UUID) throws -> NoteDiscardReceipt? {
        let receipt: NoteDiscardReceipt? = try database.write { database in
            let deletedAt = Date()
            let count = try Note
                .filter(Note.Columns.id == id)
                .filter(Note.Columns.deletedAt == nil)
                .updateAll(database, [
                    Note.Columns.deletedAt.set(to: deletedAt),
                ])
            return count == 1 ? NoteDiscardReceipt(noteID: id, deletedAt: deletedAt) : nil
        }
        if let receipt { discardReceipts[id] = receipt }
        return receipt
    }

    func restoreDiscard(_ receipt: NoteDiscardReceipt) throws -> Note {
        guard discardReceipts[receipt.noteID] == receipt else { throw PersistenceError.staleContent }
        let note = try database.write { database in
            let count = try Note
                .filter(Note.Columns.id == receipt.noteID)
                .filter(Note.Columns.deletedAt == receipt.deletedAt)
                .updateAll(database, [Note.Columns.deletedAt.set(to: nil)])
            guard count == 1, let note = try Note.fetchOne(database, key: receipt.noteID) else {
                throw PersistenceError.staleContent
            }
            return note
        }
        discardReceipts[receipt.noteID] = nil
        return note
    }

    func keep(id: UUID) throws -> Note {
        guard let note = try fetch(id: id) else {
            throw PersistenceError.staleContent
        }
        guard Self.hasMeaningfulContent(note.content) else {
            throw PersistenceError.emptyContent
        }

        return try database.write { database in
            let now = Date()
            let updatedCount = try Note
                .filter(Note.Columns.id == id)
                .filter(Note.Columns.deletedAt == nil)
                .updateAll(database, [
                    Note.Columns.keptAt.set(to: now),
                    Note.Columns.updatedAt.set(to: now),
                ])
            guard updatedCount == 1 else {
                throw PersistenceError.staleContent
            }
            return try Note.fetchOne(database, key: id)!
        }
    }

    func unkeep(id: UUID) throws -> Note {
        return try database.write { database in
            let updatedCount = try Note
                .filter(Note.Columns.id == id)
                .filter(Note.Columns.deletedAt == nil)
                .updateAll(database, [
                    Note.Columns.keptAt.set(to: nil),
                    Note.Columns.updatedAt.set(to: Date()),
                ])
            guard updatedCount == 1 else {
                throw PersistenceError.staleContent
            }
            return try Note.fetchOne(database, key: id)!
        }
    }

    private nonisolated static func hasMeaningfulContent(_ content: String) -> Bool {
        !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

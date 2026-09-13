import Foundation
import GRDB

actor NoteRepository {
    enum PersistenceError: Error {
        case emptyContent
    }

    private let database: DatabaseQueue

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
                deletedAt: nil
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
            try Note
                .filter(Note.Columns.id == id)
                .filter(Note.Columns.deletedAt == nil)
                .updateAll(database, [
                    Note.Columns.content.set(to: content),
                    Note.Columns.updatedAt.set(to: Date()),
                ])
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

    func delete(id: UUID) throws {
        _ = try database.write { database in
            try Note
                .filter(Note.Columns.id == id)
                .filter(Note.Columns.deletedAt == nil)
                .updateAll(database, [
                    Note.Columns.deletedAt.set(to: Date()),
                ])
        }
    }

    private nonisolated static func hasMeaningfulContent(_ content: String) -> Bool {
        !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

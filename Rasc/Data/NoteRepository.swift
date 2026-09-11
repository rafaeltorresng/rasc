import Foundation
import GRDB

struct Note: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "notes"

    let id: UUID
    var content: String
    let createdAt: Date
    var updatedAt: Date
}

actor NoteRepository {
    private let database: DatabaseQueue

    nonisolated static func openDefault() throws -> NoteRepository {
        let applicationSupportDirectory = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let databaseDirectory = applicationSupportDirectory.appending(path: "Rasc", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: databaseDirectory, withIntermediateDirectories: true)
        return try NoteRepository(databaseURL: databaseDirectory.appending(path: "Rasc.sqlite"))
    }

    init(databaseURL: URL) throws {
        database = try DatabaseQueue(path: databaseURL.path)

        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1_create_notes") { database in
            try database.create(table: Note.databaseTableName) { table in
                table.column("id", .text).primaryKey()
                table.column("content", .text).notNull()
                table.column("createdAt", .datetime).notNull()
                table.column("updatedAt", .datetime).notNull()
            }
        }
        try migrator.migrate(database)
    }

    func createScratch(content: String) throws -> Note {
        try database.write { database in
            let now = Date()
            let note = Note(id: UUID(), content: content, createdAt: now, updatedAt: now)
            try note.insert(database)
            return note
        }
    }

    func fetch(id: UUID) throws -> Note? {
        try database.read { database in
            try Note.fetchOne(database, key: id)
        }
    }

    func update(id: UUID, content: String) throws {
        _ = try database.write { database in
            try Note
                .filter(key: id)
                .updateAll(database, [
                    Column("content").set(to: content),
                    Column("updatedAt").set(to: Date()),
                ])
        }
    }

    func fetchMostRecent() throws -> Note? {
        try database.read { database in
            try Note
                .order(Column("updatedAt").desc, Column.rowID.desc)
                .fetchOne(database)
        }
    }

    func delete(id: UUID) throws {
        try database.write { database in
            _ = try Note.deleteOne(database, key: id)
        }
    }
}

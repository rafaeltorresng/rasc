import Foundation
import GRDB

enum AppDatabase {
    static func open(at databaseURL: URL) throws -> DatabaseQueue {
        let database = try DatabaseQueue(path: databaseURL.path)
        try migrator.migrate(database)
        return database
    }

    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        // This migration shipped in M0. Its identifier and schema are immutable so
        // existing databases can advance safely to the M1 schema below.
        migrator.registerMigration("v1_create_notes") { database in
            try database.create(table: Note.databaseTableName) { table in
                table.column("id", .text).primaryKey()
                table.column("content", .text).notNull()
                table.column("createdAt", .datetime).notNull()
                table.column("updatedAt", .datetime).notNull()
            }
        }

        migrator.registerMigration("v2_m1_notes_schema") { database in
            try database.alter(table: Note.databaseTableName) { table in
                table.rename(column: "createdAt", to: "created_at")
                table.rename(column: "updatedAt", to: "updated_at")
                table.add(column: "deleted_at", .datetime)
            }
        }

        migrator.registerMigration("v3_m2_create_notes_fts") { database in
            try database.create(virtualTable: "notes_fts", using: FTS5()) { table in
                table.synchronize(withTable: Note.databaseTableName)
                table.tokenizer = .unicode61(diacritics: .remove)
                table.prefixes = [2, 3, 4]
                table.column("content")
            }
        }

        migrator.registerMigration("v4_m3a_create_refinement_revisions") { database in
            try database.create(table: "refinement_revisions") { table in
                table.column("id", .text).primaryKey()
                table.column("note_id", .text)
                    .notNull()
                    .indexed()
                    .references(Note.databaseTableName)
                table.column("before_content", .text).notNull()
                table.column("after_content", .text).notNull()
                table.column("provider", .text).notNull()
                table.column("model_identifier", .text).notNull()
                table.column("prompt_version", .text).notNull()
                table.column("created_at", .datetime).notNull()
            }
        }

        return migrator
    }
}

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

        migrator.registerMigration("v5_m16_notes_kept_at") { database in
            try database.alter(table: Note.databaseTableName) { table in
                table.add(column: "kept_at", .datetime)
            }
        }

        migrator.registerMigration("v6_structured_note_content") { database in
            try database.create(table: "note_documents") { table in
                table.column("note_id", .text).primaryKey()
                    .references(Note.databaseTableName, onDelete: .cascade)
                table.column("document", .blob).notNull()
            }
        }

        migrator.registerMigration("v7_note_image_indicator") { database in
            try database.alter(table: Note.databaseTableName) { table in
                table.add(column: "has_images", .boolean).notNull().defaults(to: false)
            }
            let rows = try Row.fetchAll(database, sql: "SELECT note_id, document FROM note_documents")
            for row in rows {
                let id: UUID = row["note_id"]
                let data: Data = row["document"]
                let document = try PropertyListDecoder().decode(NoteDocument.self, from: data)
                try document.validate()
                if document.hasImages {
                    try database.execute(sql: "UPDATE notes SET has_images = 1 WHERE id = ?", arguments: [id])
                }
            }
        }

        migrator.registerMigration("v8_structured_text_overrides") { database in
            // Older binaries see a deliberately unreadable marker, so they cannot
            // silently ignore text overlays or overwrite newer structured content.
            try database.rename(table: "note_documents", to: "note_document_bases")
            try database.execute(sql: "CREATE VIEW note_documents AS SELECT note_id, X'00' AS document FROM note_document_bases")
            try database.create(table: "note_document_edits") { table in
                table.column("note_id", .text).primaryKey()
                    .references("note_document_bases", onDelete: .cascade)
                table.column("revision", .integer).notNull().defaults(to: 0)
                table.column("text_segments", .blob)
            }
            try database.execute(sql: "INSERT INTO note_document_edits (note_id) SELECT note_id FROM note_document_bases")
        }

        return migrator
    }
}

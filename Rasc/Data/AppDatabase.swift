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

        return migrator
    }
}

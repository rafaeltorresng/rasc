// Appended to the isolated copy of NoteRepository.swift at build time.
extension NoteRepository {
    func loadStudyDraft() throws -> String {
        try database.write { db in
            try db.execute(sql: "CREATE TABLE IF NOT EXISTS study_draft (singleton INTEGER PRIMARY KEY CHECK(singleton = 1), text TEXT NOT NULL)")
            return try String.fetchOne(db, sql: "SELECT text FROM study_draft WHERE singleton = 1") ?? ""
        }
    }

    func saveStudyDraft(_ text: String) throws {
        try database.write { db in
            try db.execute(sql: """
                INSERT INTO study_draft(singleton, text) VALUES (1, ?)
                ON CONFLICT(singleton) DO UPDATE SET text = excluded.text
                """, arguments: [text])
        }
    }

    func undoStudyCapture(_ snapshot: Note) throws -> Bool {
        try database.write { db in
            guard let current = try Note.fetchOne(db, key: snapshot.id), current == snapshot else { return false }
            try db.execute(sql: "UPDATE notes SET deleted_at = ? WHERE id = ?", arguments: [Date(), snapshot.id])
            return db.changesCount == 1
        }
    }
}

// Appended to a copy of Rasc's repository for the isolated study target.
extension NoteRepository {
    struct PendingVoiceText: Codable, Sendable {
        let id: UUID
        let recognized: String
        let text: String
    }

    func initializeStudyStorage() throws -> (scratch: String, pending: PendingVoiceText?) {
        try database.write { db in
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS study_draft (id INTEGER PRIMARY KEY CHECK(id = 1), text TEXT NOT NULL);
                CREATE TABLE IF NOT EXISTS study_pending_voice (id TEXT PRIMARY KEY, recognized TEXT NOT NULL, text TEXT NOT NULL);
                """)
            let scratch = try String.fetchOne(db, sql: "SELECT text FROM study_draft WHERE id = 1") ?? ""
            let rows = try Row.fetchAll(db, sql: "SELECT * FROM study_pending_voice ORDER BY rowid DESC")
            var pending: PendingVoiceText?
            for row in rows {
                guard let id = UUID(uuidString: row["id"]) else { continue }
                if try Note.fetchOne(db, key: id) != nil {
                    try db.execute(sql: "DELETE FROM study_pending_voice WHERE id = ?", arguments: [id.uuidString])
                } else if pending == nil {
                    pending = PendingVoiceText(id: id, recognized: row["recognized"], text: row["text"])
                }
            }
            return (scratch, pending)
        }
    }

    func saveStudyDraft(_ text: String) throws {
        try Task.checkCancellation()
        try database.write { db in
            try db.execute(sql: """
                INSERT INTO study_draft(id, text) VALUES (1, ?)
                ON CONFLICT(id) DO UPDATE SET text = excluded.text
                """, arguments: [text])
        }
    }

    func stageVoiceText(_ pending: PendingVoiceText) throws {
        try Task.checkCancellation()
        try database.write { db in
            guard try Note.fetchOne(db, key: pending.id) == nil else { return }
            try db.execute(sql: """
                INSERT INTO study_pending_voice(id, recognized, text) VALUES (?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET text = excluded.text
                """, arguments: [pending.id.uuidString, pending.recognized, pending.text])
        }
    }

    func discardVoiceText(_ id: UUID) throws {
        try database.write { db in
            try db.execute(sql: "DELETE FROM study_pending_voice WHERE id = ?", arguments: [id.uuidString])
        }
    }

    func keepStudyVoice(id: UUID, content: String) throws -> Note {
        try database.write { db in
            let persisted = try Self.insertKeptVoiceCapture(id: id, content: content, in: db)
            try db.execute(sql: "DELETE FROM study_pending_voice WHERE id = ?", arguments: [id.uuidString])
            return persisted
        }
    }

    func editStudyThought(_ snapshot: Note, text: String) throws -> Note {
        guard let current = try database.read({ try Note.fetchOne($0, key: snapshot.id) }),
              current == snapshot else { throw PersistenceError.staleContent }
        try update(id: snapshot.id, content: text)
        guard let edited = try database.read({ try Note.fetchOne($0, key: snapshot.id) }) else {
            throw PersistenceError.staleContent
        }
        return edited
    }

    func undoStudyCapture(_ snapshot: Note) throws -> Bool {
        try database.write { db in
            guard let current = try Note.fetchOne(db, key: snapshot.id), current == snapshot else { return false }
            try db.execute(sql: "UPDATE notes SET deleted_at = ? WHERE id = ?", arguments: [Date(), snapshot.id])
            return db.changesCount == 1
        }
    }

    func resetStudyNotes() throws {
        try database.write { db in
            try db.execute(sql: "DELETE FROM study_pending_voice; DELETE FROM study_draft; DELETE FROM notes;")
        }
    }

    func rejectStudyDiscardForValidation(_ enabled: Bool) throws {
        try database.write { db in
            if enabled {
                try db.execute(sql: """
                    CREATE TEMP TRIGGER reject_voice_discard BEFORE DELETE ON study_pending_voice
                    BEGIN SELECT RAISE(ABORT, 'injected study journal failure'); END;
                    """)
            } else {
                try db.execute(sql: "DROP TRIGGER IF EXISTS reject_voice_discard")
            }
        }
    }

    func rejectStudyCommitForValidation(_ enabled: Bool) throws {
        try database.write { db in
            if enabled {
                try db.execute(sql: """
                    CREATE TEMP TRIGGER reject_voice_save BEFORE INSERT ON notes
                    BEGIN SELECT RAISE(ABORT, 'injected study write failure'); END;
                    """)
            } else {
                try db.execute(sql: "DROP TRIGGER IF EXISTS reject_voice_save")
            }
        }
    }
}

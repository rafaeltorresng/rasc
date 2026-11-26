// Appended to a temporary copy of NoteRepository.swift so this research can
// exercise the real private database handle without changing the app target.
extension NoteRepository {
    func createKeptVoiceCapture(id: UUID, content: String) throws -> Note {
        try database.write { db in
            try Self.insertKeptVoiceCapture(id: id, content: content, in: db)
        }
    }

    static func insertKeptVoiceCapture(id: UUID, content: String, in db: Database) throws -> Note {
        guard Self.hasMeaningfulContent(content) else { throw PersistenceError.emptyContent }
        if let existing = try Note.fetchOne(db, key: id) {
            guard existing.deletedAt == nil, existing.isKept, existing.content == content else {
                throw PersistenceError.staleContent
            }
            return existing
        }
        let timestamp = Date()
        let note = Note(id: id, content: content, createdAt: timestamp, updatedAt: timestamp,
                        deletedAt: nil, keptAt: timestamp)
        try note.insert(db)
        // Read back the persisted date representation for exact-match receipts.
        guard let persisted = try Note.fetchOne(db, key: id) else { throw PersistenceError.staleContent }
        return persisted
    }
}

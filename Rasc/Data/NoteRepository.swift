import Foundation
import GRDB
#if DEBUG
import ObjectiveC
#endif

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
        case structuredContentRequiresDocument
    }

    private let database: DatabaseQueue
    private var discardReceipts: [UUID: NoteDiscardReceipt] = [:]
    // Retain at most one decoded note; the revision is checked in SQLite on every write.
    private var cachedDocument: (id: UUID, document: NoteDocument, revision: Int64)?

    private struct StoredDocument {
        let document: NoteDocument
        let bytes: Data
        let textSegments: Data?
        let revision: Int64
    }

    nonisolated static var defaultDatabaseURL: URL {
        get throws {
            #if DEBUG
            if TestHostIsolation.isAppTestHost {
                let url = TestHostIsolation.databaseURL()
                TestHostIsolation.assertNotPersonal(url)
                return url
            }
            #endif
            let environment = ProcessInfo.processInfo.environment
            if environment["XCTestConfigurationFilePath"] != nil || environment["XCTestBundlePath"] != nil {
                fatalError("Refusing to open personal Rasc storage from a test host")
            }
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

    /// Holds the first mutation open so tests can interleave session work while a write is in flight.
    /// The gate blocks the actor thread; it does not suspend the actor, so later calls stay queued.
    func installTestGate(_ gate: NoteRepositoryTestGate?) {
        testGate = gate
    }

    private var testGate: NoteRepositoryTestGate?
    #endif

    func createScratch(content: String) throws -> Note {
        #if DEBUG
        testGate?.enter()
        #endif
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

    private nonisolated static func textSegments(_ document: NoteDocument) -> [String] {
        var segments = [""]
        for part in document.parts {
            switch part {
            case .text(let text): segments[segments.count - 1] += text
            case .image: segments.append("")
            }
        }
        return segments
    }

    private nonisolated static func imagesMatch(_ lhs: NoteDocument, _ rhs: NoteDocument) -> Bool {
        let left = lhs.parts.filter { if case .image = $0 { true } else { false } }
        let right = rhs.parts.filter { if case .image = $0 { true } else { false } }
        return left == right
    }

    private nonisolated static func loadStructured(id: UUID, in db: Database) throws -> StoredDocument? {
        guard let row = try Row.fetchOne(db, sql: """
            SELECT note_document_bases.document, note_document_edits.revision, note_document_edits.text_segments
            FROM note_document_bases LEFT JOIN note_document_edits USING (note_id)
            WHERE note_document_bases.note_id = ?
            """, arguments: [id]) else { return nil }
        let bytes: Data = row["document"]
        guard let revision: Int64 = row["revision"] else { throw PersistenceError.staleContent }
        let segmentsData: Data? = row["text_segments"]
        let base = try PropertyListDecoder().decode(NoteDocument.self, from: bytes)
        try base.validate()
        let document: NoteDocument
        if let segmentsData {
            let segments = try PropertyListDecoder().decode([String].self, from: segmentsData)
            let images = base.parts.filter { if case .image = $0 { true } else { false } }
            guard segments.count == images.count + 1 else { throw PersistenceError.staleContent }
            var parts: [NoteDocument.Part] = []
            for (index, image) in images.enumerated() {
                parts.append(.text(segments[index]))
                parts.append(image)
            }
            parts.append(.text(segments[images.count]))
            document = NoteDocument(parts: parts)
        } else {
            document = base
        }
        return StoredDocument(document: document, bytes: bytes, textSegments: segmentsData, revision: revision)
    }

    func duplicate(id: UUID) throws -> Note {
        let result: (Note, NoteDocument?) = try database.write { db in
            guard let source = try Note.filter(Note.Columns.id == id)
                .filter(Note.Columns.deletedAt == nil).fetchOne(db) else {
                throw PersistenceError.staleContent
            }
            let stored = try Self.loadStructured(id: id, in: db)
            if let stored {
                guard stored.document.text == source.content, stored.document.hasImages == source.hasImages else { throw PersistenceError.staleContent }
            } else if source.hasImages {
                throw PersistenceError.staleContent
            } else if !Self.hasMeaningfulContent(source.content) {
                throw PersistenceError.emptyContent
            }
            let now = Date()
            let copy = Note(id: UUID(), content: source.content, createdAt: now,
                            updatedAt: now, deletedAt: nil, keptAt: nil, hasImages: source.hasImages)
            try copy.insert(db)
            if let stored {
                try db.execute(sql: "INSERT INTO note_document_bases (note_id, document) VALUES (?, ?)", arguments: [copy.id, stored.bytes])
                try db.execute(sql: "INSERT INTO note_document_edits (note_id, revision, text_segments) VALUES (?, 0, ?)", arguments: [copy.id, stored.textSegments])
            }
            return (copy, stored?.document)
        }
        if let document = result.1 { cachedDocument = (result.0.id, document, 0) }
        return result.0
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
        #if DEBUG
        testGate?.enter()
        #endif
        _ = try database.write { database in
            guard let existing = try Note
                .filter(Note.Columns.id == id)
                .filter(Note.Columns.deletedAt == nil)
                .fetchOne(database)
            else {
                // A save must not appear successful after Home discarded this note.
                throw PersistenceError.staleContent
            }

            guard try !Self.hasDocument(id: id, in: database) else {
                throw PersistenceError.structuredContentRequiresDocument
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

        let revision: RefinementRevision = try database.write { database in
            if let stored = try Self.loadStructured(id: noteID, in: database) {
                guard !stored.document.hasImages else { throw PersistenceError.structuredContentRequiresDocument }
                guard stored.document.text == beforeContent else { throw PersistenceError.staleContent }
                try database.execute(sql: "DELETE FROM note_document_edits WHERE note_id = ?", arguments: [noteID])
                try database.execute(sql: "DELETE FROM note_document_bases WHERE note_id = ?", arguments: [noteID])
            }
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
        if cachedDocument?.id == noteID { cachedDocument = nil }
        return revision
    }

    /// Structured content and its search projection are committed together.
    func createScratch(document: NoteDocument) throws -> Note {
        #if DEBUG
        testGate?.enter()
        #endif
        try document.validate()
        guard document.hasImages || Self.hasMeaningfulContent(document.text) else {
            throw PersistenceError.emptyContent
        }
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let bytes = try encoder.encode(document)
        let note: Note = try database.write { db in
            let now = Date()
            let note = Note(id: UUID(), content: document.text, createdAt: now,
                            updatedAt: now, deletedAt: nil, keptAt: nil, hasImages: document.hasImages)
            try note.insert(db)
            try db.execute(sql: "INSERT INTO note_document_bases (note_id, document) VALUES (?, ?)", arguments: [note.id, bytes])
            try db.execute(sql: "INSERT INTO note_document_edits (note_id, revision) VALUES (?, 0)", arguments: [note.id])
            return note
        }
        cachedDocument = (note.id, document, 0)
        return note
    }

    /// Reads the note and optional structured content from the same database snapshot.
    func fetchEditable(id: UUID) throws -> (note: Note, document: NoteDocument?)? {
        let result: (Note, StoredDocument?)? = try database.read { db in
            guard let note = try Note.filter(Note.Columns.id == id)
                .filter(Note.Columns.deletedAt == nil).fetchOne(db) else { return nil }
            let stored = try Self.loadStructured(id: id, in: db)
            guard let stored else {
                guard !note.hasImages else { throw PersistenceError.staleContent }
                return (note, nil)
            }
            guard stored.document.text == note.content, stored.document.hasImages == note.hasImages else { throw PersistenceError.staleContent }
            return (note, stored)
        }
        guard let result else { return nil }
        if let stored = result.1 { cachedDocument = (id, stored.document, stored.revision) }
        else if cachedDocument?.id == id { cachedDocument = nil }
        return (result.0, result.1?.document)
    }

    func fetchDocument(id: UUID) throws -> NoteDocument? {
        guard let editable = try fetchEditable(id: id) else { return nil }
        return editable.document ?? NoteDocument(parts: [.text(editable.note.content)])
    }

    func update(id: UUID, document: NoteDocument, ifCurrent expected: NoteDocument) throws {
        #if DEBUG
        testGate?.enter()
        #endif
        // A cached document is safe only with the database revision check below.
        var baseline = cachedDocument.flatMap { $0.id == id && $0.document == expected ? $0 : nil }
        if baseline == nil {
            let stored = try database.read { try Self.loadStructured(id: id, in: $0) }
            if let stored { baseline = (id, stored.document, stored.revision) }
        }
        if let baseline, baseline.document != expected { throw PersistenceError.staleContent }
        guard document.version == NoteDocument.currentVersion else { throw NoteDocument.DocumentError.unsupportedVersion }
        let textOnly = baseline != nil && Self.imagesMatch(expected, document)
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let segments = textOnly ? try encoder.encode(Self.textSegments(document)) : nil
        let bytes: Data?
        if textOnly { bytes = nil }
        else {
            try document.validate()
            bytes = try encoder.encode(document)
        }
        let newRevision: Int64 = try database.write { db in
            guard let existing = try Note.filter(Note.Columns.id == id)
                .filter(Note.Columns.deletedAt == nil).fetchOne(db),
                  existing.content == expected.text, existing.hasImages == expected.hasImages else {
                throw PersistenceError.staleContent
            }
            if document == expected {
                if let baseline {
                    let revision = try Int64.fetchOne(db, sql: "SELECT revision FROM note_document_edits JOIN note_document_bases USING (note_id) WHERE note_id = ?", arguments: [id])
                    guard revision == baseline.revision else { throw PersistenceError.staleContent }
                    return baseline.revision
                }
                guard try !Self.hasDocument(id: id, in: db) else { throw PersistenceError.staleContent }
                return 0
            }
            if let baseline {
                // CAS uses a small separate row; SQLite never rewrites the image blob for text edits.
                try db.execute(sql: "UPDATE note_document_edits SET revision = revision + 1, text_segments = ? WHERE note_id = ? AND revision = ? AND EXISTS (SELECT 1 FROM note_document_bases WHERE note_id = ?)", arguments: [segments, id, baseline.revision, id])
                guard db.changesCount == 1 else { throw PersistenceError.staleContent }
                if let bytes {
                    try db.execute(sql: "UPDATE note_document_bases SET document = ? WHERE note_id = ?", arguments: [bytes, id])
                    guard db.changesCount == 1 else { throw PersistenceError.staleContent }
                }
            } else {
                guard try !Self.hasDocument(id: id, in: db), let bytes else { throw PersistenceError.staleContent }
                try db.execute(sql: "INSERT INTO note_document_bases (note_id, document) VALUES (?, ?)", arguments: [id, bytes])
                try db.execute(sql: "INSERT INTO note_document_edits (note_id, revision) VALUES (?, 0)", arguments: [id])
            }
            try Note.filter(Note.Columns.id == id).updateAll(db, [
                Note.Columns.content.set(to: document.text),
                Note.Columns.hasImages.set(to: document.hasImages),
                Note.Columns.updatedAt.set(to: Date()),
            ])
            return baseline.map { $0.revision + 1 } ?? 0
        }
        if baseline != nil || document != expected { cachedDocument = (id, document, newRevision) }
    }

    private nonisolated static func hasDocument(id: UUID, in db: Database) throws -> Bool {
        try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM note_document_bases WHERE note_id = ?)", arguments: [id]) ?? false
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
        return try database.write { database in
            guard let note = try Note.filter(Note.Columns.id == id)
                .filter(Note.Columns.deletedAt == nil).fetchOne(database) else {
                throw PersistenceError.staleContent
            }
            let stored = try Self.loadStructured(id: id, in: database)
            let hasImages: Bool
            if let stored {
                guard stored.document.text == note.content, stored.document.hasImages == note.hasImages else { throw PersistenceError.staleContent }
                hasImages = stored.document.hasImages
            } else {
                guard !note.hasImages else { throw PersistenceError.staleContent }
                hasImages = false
            }
            guard hasImages || Self.hasMeaningfulContent(note.content) else {
                throw PersistenceError.emptyContent
            }
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

#if DEBUG
/// Blocks the first repository mutation until `release()` so a test can run the next session operation.
final class NoteRepositoryTestGate: @unchecked Sendable {
    private let entered = DispatchSemaphore(value: 0)
    private let releaseFirst = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var started = 0

    func waitForFirstEntry() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                self.entered.wait()
                continuation.resume()
            }
        }
    }

    func release() {
        releaseFirst.signal()
    }

    fileprivate func enter() {
        lock.lock()
        started += 1
        let isFirst = started == 1
        lock.unlock()
        guard isFirst else { return }
        entered.signal()
        releaseFirst.wait()
    }
}

/// Redirects the test host away from the user's notes and preferences.
/// Release builds do not contain this type. `HOME` is not consulted.
enum TestHostIsolation {
    private final class State: @unchecked Sendable {
        let lock = NSLock()
        var installed = false
        var storageRoot: URL?
        var isolatedDefaults: UserDefaults?
        var suiteName: String?
    }

    private static let state = State()

    static var isInstalled: Bool { state.installed }

    static var isAppTestHost: Bool {
        let environment = ProcessInfo.processInfo.environment
        let underTest = environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestBundlePath"] != nil
        guard underTest else { return false }
        if Bundle.main.bundleIdentifier == "com.rafaeltorres.rasc" { return true }
        let executable = Bundle.main.executableURL?.path ?? ""
        return executable.contains("/Rasc.app/")
    }

    static func installIfNeeded() {
        state.lock.lock()
        defer { state.lock.unlock() }
        guard isAppTestHost, !state.installed else { return }

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RascIsolatedHost", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        } catch {
            fatalError("Could not create isolated Rasc test storage: \(error)")
        }

        let name = "rasc.isolated.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: name) else {
            fatalError("Could not create isolated Rasc preferences")
        }
        swizzleStandardDefaults(to: defaults)

        state.storageRoot = root
        state.isolatedDefaults = defaults
        state.suiteName = name
        state.installed = true
        NotificationCenter.default.addObserver(
            forName: Notification.Name("NSApplicationWillTerminateNotification"),
            object: nil,
            queue: .main
        ) { _ in
            TestHostIsolation.cleanup()
        }
    }

    static func databaseURL() -> URL {
        installIfNeeded()
        guard let storageRoot = state.storageRoot else {
            fatalError("Rasc test host tried to open a database without isolated storage")
        }
        return storageRoot
            .appendingPathComponent("Application Support/Rasc", isDirectory: true)
            .appendingPathComponent("Rasc.sqlite")
    }

    static func assertNotPersonal(_ url: URL) {
        let path = url.standardizedFileURL.path
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        let forbidden = [
            home + "/Library/Application Support/Rasc",
            home + "/Library/Containers/com.rafaeltorres.rasc",
        ]
        for prefix in forbidden where path == prefix || path.hasPrefix(prefix + "/") {
            fatalError("Refusing to open personal Rasc storage during tests: \(path)")
        }
    }

    static func cleanup() {
        state.lock.lock()
        let root = state.storageRoot
        let defaults = state.isolatedDefaults
        let name = state.suiteName
        state.storageRoot = nil
        state.isolatedDefaults = nil
        state.suiteName = nil
        state.lock.unlock()
        if let name, let defaults {
            defaults.removePersistentDomain(forName: name)
        }
        if let root {
            try? FileManager.default.removeItem(at: root)
        }
    }

    private static func swizzleStandardDefaults(to defaults: UserDefaults) {
        let selector = NSSelectorFromString("standardUserDefaults")
        guard let method = class_getClassMethod(UserDefaults.self, selector) else {
            fatalError("Could not isolate UserDefaults.standard")
        }
        let block: @convention(block) (AnyObject) -> UserDefaults = { _ in defaults }
        method_setImplementation(method, imp_implementationWithBlock(block))
    }
}
#endif

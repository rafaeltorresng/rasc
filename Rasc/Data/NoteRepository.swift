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
    }

    private let database: DatabaseQueue
    private var discardReceipts: [UUID: NoteDiscardReceipt] = [:]

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

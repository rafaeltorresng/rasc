import Foundation
import GRDB

private enum Failure: Error { case expectation(String) }

private func check(_ condition: Bool, _ message: String) throws {
    guard condition else { throw Failure.expectation(message) }
}

@main
struct Validate {
    static func main() async throws {
        let sandbox = FileManager.default.temporaryDirectory.appending(path: "rasc-voice-db-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: sandbox) }
        let url = sandbox.appending(path: "synthetic.sqlite")
        let repository = try NoteRepository(databaseURL: url)
        let scratch = try await repository.createScratch(content: "Current unfinished thought.")
        let suite = "com.rasc.research.voice.persistence.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let active = ActiveNoteStore(userDefaults: defaults)
        active.noteID = scratch.id
        let id = UUID()
        let transcript = "Talvez seja uma migração. Não tem certeza."
        async let first = repository.createKeptVoiceCapture(id: id, content: transcript)
        async let repeatSave = repository.createKeptVoiceCapture(id: id, content: transcript)
        let (one, duplicate) = try await (first, repeatSave)
        try check(one == duplicate && one.isKept, "Concurrent replay must return the same row")
        try check(active.noteID == scratch.id, "Voice must leave the active-note pointer in place")
        try await check(repository.fetch(id: scratch.id) != nil, "Unfinished thought must survive")
        let scratchAfter = try await repository.fetch(id: scratch.id)
        try check(scratchAfter?.content == scratch.content && scratchAfter?.isKept == false, "Unfinished thought changed")
        let search = try await repository.search("migração", limit: 10)
        try check(search.map(\.id) == [id], "Search must index the new row exactly once")
        let independent = try NoteRepository(databaseURL: url)
        try await check(independent.fetch(id: id) == one, "Commit must be readable from a second connection")

        do {
            _ = try await repository.createKeptVoiceCapture(id: id, content: "Wrong transcript")
            throw Failure.expectation("Replay with different content should fail")
        } catch NoteRepository.PersistenceError.staleContent { }
        do {
            _ = try await repository.createKeptVoiceCapture(id: UUID(), content: "  \n ")
            throw Failure.expectation("Blank thought should fail")
        } catch NoteRepository.PersistenceError.emptyContent { }

        let db = try DatabaseQueue(path: url.path)
        try await db.write { db in
            try db.execute(sql: """
                CREATE TRIGGER test_fail_voice_save BEFORE INSERT ON notes
                WHEN NEW.content = 'failfixture'
                BEGIN SELECT RAISE(ABORT, 'synthetic write failure'); END
                """)
        }
        let retryID = UUID()
        do {
            _ = try await repository.createKeptVoiceCapture(id: retryID, content: "failfixture")
            throw Failure.expectation("Injected error was ignored")
        } catch is DatabaseError { }
        try await check(repository.fetch(id: retryID) == nil, "Failed insert left a row")
        try await check(repository.search("failfixture", limit: 10).isEmpty, "Failed insert left a search entry")
        try await db.write { try $0.execute(sql: "DROP TRIGGER test_fail_voice_save") }
        try await check(repository.createKeptVoiceCapture(id: retryID, content: "failfixture").isKept, "Retry failed")
        let receipt = try await repository.delete(id: id)
        try check(receipt != nil, "Discard failed")
        do {
            _ = try await repository.createKeptVoiceCapture(id: id, content: transcript)
            throw Failure.expectation("A stale save replay resurrected a discarded capture")
        } catch NoteRepository.PersistenceError.staleContent { }
        let restored = try await repository.restoreDiscard(receipt!)
        try check(restored.isKept && restored.content == one.content && active.noteID == scratch.id,
                  "Restore must preserve lifecycle state and the existing scratch")

        var timings: [Double] = []
        for index in 0..<50 {
            let start = ContinuousClock.now
            _ = try await repository.createKeptVoiceCapture(id: UUID(), content: "Synthetic local timing \(index).")
            let elapsed = start.duration(to: .now).components
            timings.append(Double(elapsed.seconds) * 1000 + Double(elapsed.attoseconds) / 1e15)
        }
        timings.sort()
        print("PASS: concurrent replay, scratch isolation, committed read, FTS, empty/collision rejection, rollback/retry, soft discard/restore, stale replay")
        print("50 serial SQLite commits, milliseconds: p50 \(timings[24]), p95 \(timings[47]), max \(timings.last!)")
    }
}

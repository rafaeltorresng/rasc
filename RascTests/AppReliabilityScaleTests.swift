import Foundation
import Testing
@testable import Rasc

@Suite(.serialized)
struct AppReliabilityScaleTests {
    private struct BenchmarkSample: Codable {
        let noteCount: Int
        let bootstrapMs: Double
        let recentNoteLoadMs: Double
        let searchMs: Double
        let noteSwitchMs: Double
        let autosaveMs: Double
    }

    @Test(arguments: [10, 100, 1_000])
    @MainActor
    func scaleBenchmarksMeetLocalThresholds(noteCount: Int) async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }

        let bootstrapStart = CFAbsoluteTimeGetCurrent()
        let repository = try NoteRepository(databaseURL: fixture.databaseURL)
        let bootstrapMs = milliseconds(since: bootstrapStart)

        let seedStart = CFAbsoluteTimeGetCurrent()
        try await seedNotes(count: noteCount, in: repository)
        let seedMs = milliseconds(since: seedStart)

        let recentStart = CFAbsoluteTimeGetCurrent()
        _ = try await repository.fetchMostRecent()
        let recentNoteLoadMs = milliseconds(since: recentStart)

        let searchStart = CFAbsoluteTimeGetCurrent()
        _ = try await repository.search("retry queue logs", limit: 20)
        let searchMs = milliseconds(since: searchStart)

        let notes = try await repository.fetchAllNonDeleted()
        let suiteName = "RascScale.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let session = ScratchpadSession(repository: repository, userDefaults: defaults)
        #expect(notes.count >= 2)
        _ = try await session.openNote(id: notes[0].id)
        let switchStart = CFAbsoluteTimeGetCurrent()
        let opened = try await session.openNote(id: notes[1].id)
        let noteSwitchMs = milliseconds(since: switchStart)

        #expect(opened)
        #expect(session.text == notes[1].content)

        let autosaveStart = CFAbsoluteTimeGetCurrent()
        if let target = notes.first {
            try await repository.update(id: target.id, content: target.content + " edited")
        }
        let autosaveMs = milliseconds(since: autosaveStart)

        let sample = BenchmarkSample(
            noteCount: noteCount,
            bootstrapMs: bootstrapMs,
            recentNoteLoadMs: recentNoteLoadMs,
            searchMs: searchMs,
            noteSwitchMs: noteSwitchMs,
            autosaveMs: autosaveMs
        )

        print("M13A_BENCHMARK \(String(data: try JSONEncoder().encode(sample), encoding: .utf8) ?? "{}")")

        #expect(bootstrapMs < 2_000)
        #expect(seedMs < Double(noteCount) * 5 + 500)
        #expect(recentNoteLoadMs < 100)
        #expect(searchMs < max(250, Double(noteCount) * 0.5))
        // Session-level switch includes flush and active-note bookkeeping, not just fetch.
        #expect(noteSwitchMs < 100)
        #expect(autosaveMs < 100)
    }

    private func seedNotes(count: Int, in repository: NoteRepository) async throws {
        for index in 0..<count {
            let body = """
            note \(index): revisar retry queue logs amanhã \
            talvez deploy onboarding fila notification \
            \(String(repeating: "context ", count: index % 12))
            """
            _ = try await repository.createScratch(content: body)
        }
    }

    private func makeFixture() throws -> ScaleFixture {
        let databaseURL = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appendingPathExtension("sqlite")
        return ScaleFixture(databaseURL: databaseURL)
    }

    private func milliseconds(since start: CFAbsoluteTime) -> Double {
        (CFAbsoluteTimeGetCurrent() - start) * 1_000
    }
}

private struct ScaleFixture {
    let databaseURL: URL

    func remove() {
        try? FileManager.default.removeItem(at: databaseURL)
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: databaseURL.path + "-shm"))
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: databaseURL.path + "-wal"))
    }
}

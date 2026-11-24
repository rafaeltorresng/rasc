import Foundation
import Testing
@testable import Rasc

struct NoteExportTests {
    @Test
    func scopesAreExplicitAndIncludeImageOnlyThoughts() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let kept = try await fixture.repository.createScratch(document: .init(parts: [Self.image]))
        _ = try await fixture.repository.keep(id: kept.id)
        let draft = try await fixture.repository.createScratch(content: "Still drafting")
        let discarded = try await fixture.repository.createScratch(content: "Do not export")
        _ = try await fixture.repository.delete(id: discarded.id)

        #expect(try await fixture.repository.exportSnapshot(for: .kept).map(\.note.id) == [kept.id])
        #expect(Set(try await fixture.repository.exportSnapshot(for: .all).map(\.note.id)) == [kept.id, draft.id])
        #expect(try await fixture.repository.exportSnapshot(for: .selected([draft.id])).map(\.note.id) == [draft.id])
        await #expect(throws: NoteExportError.thoughtChanged) {
            try await fixture.repository.exportSnapshot(for: .selected([draft.id, discarded.id]))
        }
        await #expect(throws: NoteExportError.empty) {
            try await fixture.repository.exportSnapshot(for: .selected([]))
        }
    }

    @Test
    func plainMarkdownPreservesUTF8AndLineEndingsWithoutMetadata() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let text = "  # Literal?\r\n• café e\u{301}\n\n🙂\t "
        let note = try await fixture.repository.createScratch(content: text)
        let snapshot = try #require(try await fixture.repository.exportSnapshot(for: .selected([note.id])).first)
        let document = try await fixture.repository.documentForExport(snapshot)
        let target = fixture.directory.appending(path: "Thought.md")
        try NoteExportFiles.writeText(document, note: note, to: target)
        #expect(try Data(contentsOf: target) == Data(text.utf8))
    }

    @Test(arguments: [false, true])
    func markdownAndManifestKeepImageOrderAndLatestText(fence: Bool) async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let first: NoteDocument.Part = Self.image
        let second: NoteDocument.Part = .image(data: Self.png + Data([0x00]), typeIdentifier: "public.png")
        let opening = fence ? "title\n```swift\nlet a = 1" : "title\n🇧🇷 é"
        let old = NoteDocument(parts: [.text("old"), first, .text("middle"), second])
        let current = NoteDocument(parts: [.text(opening), first, .text("middle \n"), second, .text("\nafter")])
        let note = try await fixture.repository.createScratch(document: old)
        try await fixture.repository.update(id: note.id, document: current, ifCurrent: old)
        _ = try await fixture.repository.keep(id: note.id)
        let snapshots = try await fixture.repository.exportSnapshot(for: .all)
        let folder = try await NoteExportFiles.writeFolder(snapshots, repository: fixture.repository, in: fixture.directory, named: "Portable")
        let manifest = try Self.readManifest(folder)
        let entry = try #require(manifest.notes.first)
        #expect(entry.id == note.id)
        #expect(entry.keptAt != nil)
        #expect(entry.updatedAt >= entry.createdAt)
        let markdown = try Data(contentsOf: folder.appending(path: entry.file))
        let assets = try #require(entry.parts)
        let restored: [NoteDocument.Part] = try assets.map { part in
            if let offset = part.offset, let length = part.length {
                return .text(String(decoding: markdown[offset..<(offset + length)], as: UTF8.self))
            }
            let relative = try #require(part.image)
            #expect(relative.hasPrefix("assets/"))
            return .image(data: try Data(contentsOf: folder.appending(path: relative)), typeIdentifier: try #require(part.type))
        }
        #expect(restored == current.parts)
        let formatted = try AttributedString(markdown: markdown)
        #expect(formatted.runs.compactMap(\.imageURL).map(\.relativeString) == assets.compactMap(\.image))
    }

    @Test
    func filenamesArePortableAndConflictsKeepPreviousCopies() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        for title in [".. / \\ :", "Foo", "foo", "Fóo", "AGENTS.md", String(repeating: "😊", count: 70)] {
            _ = try await fixture.repository.createScratch(content: title)
        }
        let snapshots = try await fixture.repository.exportSnapshot(for: .all)
        let first = try await NoteExportFiles.writeFolder(snapshots, repository: fixture.repository, in: fixture.directory, named: "Rasc Thoughts")
        let second = try await NoteExportFiles.writeFolder(snapshots, repository: fixture.repository, in: fixture.directory, named: "Rasc Thoughts")
        #expect(first.lastPathComponent == "Rasc Thoughts")
        #expect(second.lastPathComponent == "Rasc Thoughts 2")
        let names = try Self.readManifest(first).notes.map(\.file)
        #expect(names.contains("Thought.md"))
        #expect(names.contains("Thought – AGENTS.md"))
        #expect(names.count == Set(names.map { $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) }).count)
        #expect(names.allSatisfy { $0.utf8.count <= 104 && !$0.contains("/") })
    }

    @Test
    func staleSnapshotDoesNotPublishPartialFiles() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let old = try await fixture.repository.createScratch(content: "Earlier")
        _ = try await fixture.repository.createScratch(content: "Latest")
        let snapshots = try await fixture.repository.exportSnapshot(for: .all)
        try await fixture.repository.update(id: old.id, content: "Changed")
        await #expect(throws: NoteExportError.thoughtChanged) {
            try await NoteExportFiles.writeFolder(snapshots, repository: fixture.repository, in: fixture.directory, named: "Portable")
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.directory.path) == [])
    }

    @Test
    func preCancelledExportLeavesDestinationUntouched() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        _ = try await fixture.repository.createScratch(content: "Cancel me")
        let snapshots = try await fixture.repository.exportSnapshot(for: .all)
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        let task = Task {
            for await _ in stream {}
            return try await NoteExportFiles.writeFolder(snapshots, repository: fixture.repository, in: fixture.directory, named: "Portable")
        }
        task.cancel()
        continuation.finish()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.directory.path) == [])
    }

    @Test
    func bulkExportDoesNotInheritHomeOrSearchLimits() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        for index in 1...1_001 {
            _ = try await fixture.repository.createScratch(content: "Thought \(index)")
        }
        let snapshots = try await fixture.repository.exportSnapshot(for: .all)
        let folder = try await NoteExportFiles.writeFolder(
            snapshots, repository: fixture.repository, in: fixture.directory, named: "Large collection"
        )
        #expect(try Self.readManifest(folder).notes.count == 1_001)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).count == 1_002)
    }

    @MainActor @Test
    func exportWaitsForScratchpadAutosaveAndAnInFlightImageImport() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let suite = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let session = ScratchpadSession(repository: fixture.repository, userDefaults: defaults)
        session.text = "before image"
        let pending = session.beginImageImport(.data(Self.png), selection: NSRange(location: 12, length: 0))
        #expect(pending != nil)
        let id = try #require(try await session.activeThoughtForExport())
        let snapshot = try #require(try await fixture.repository.exportSnapshot(for: .selected([id])).first)
        let exported = try await fixture.repository.documentForExport(snapshot)
        #expect(exported.hasImages)
        #expect(exported.text.contains("before image"))
    }

    private static let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==")!
    private static let image: NoteDocument.Part = .image(data: png, typeIdentifier: "public.png")

    private static func readManifest(_ folder: URL) throws -> NoteExportFiles.Manifest {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let string = try decoder.singleValueContainer().decode(String.self)
            return try Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(string)
        }
        return try decoder.decode(NoteExportFiles.Manifest.self, from: Data(contentsOf: folder.appending(path: "manifest.json")))
    }

    private struct Fixture {
        let root: URL
        let directory: URL
        let repository: NoteRepository

        init() throws {
            root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
            directory = root.appending(path: "Destination", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            repository = try NoteRepository(databaseURL: root.appending(path: "test.sqlite"))
        }

        func remove() {
            try? FileManager.default.removeItem(at: root)
        }
    }
}

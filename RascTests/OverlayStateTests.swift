import Foundation
import Testing
@testable import Rasc

@Suite(.serialized)
@MainActor
struct OverlayStateTests {
    @Test
    func openingSearchClosesCommandPalette() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let session = ScratchpadSession(
            repository: fixture.repository,
            userDefaults: fixture.userDefaults
        )

        session.openCommandPalette()
        #expect(session.surface == .commandPalette)

        try await session.openSearch()

        #expect(session.surface == .search)
        #expect(session.commandPaletteQuery.isEmpty)
    }

    @Test
    func openingCommandPaletteClosesSearch() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let session = ScratchpadSession(
            repository: fixture.repository,
            userDefaults: fixture.userDefaults
        )

        try await session.openSearch()
        session.searchQuery = "queue"

        session.openCommandPalette()

        #expect(session.surface == .commandPalette)
        #expect(session.searchQuery.isEmpty)
    }

    @Test
    func escapeDismissesCommandPaletteBeforeSearch() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let session = ScratchpadSession(
            repository: fixture.repository,
            userDefaults: fixture.userDefaults
        )

        session.openCommandPalette()
        #expect(session.handleEscape())
        #expect(session.surface == .editor)

        try await session.openSearch()
        #expect(session.handleEscape())
        #expect(session.surface == .editor)
    }

    @Test
    func escapeFromEditorDoesNotConsumeEvent() throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let session = ScratchpadSession(
            repository: fixture.repository,
            userDefaults: fixture.userDefaults
        )

        #expect(!session.handleEscape())
        #expect(session.surface == .editor)
    }

    @Test
    func commandPaletteFiltersCommands() throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let session = ScratchpadSession(
            repository: fixture.repository,
            userDefaults: fixture.userDefaults
        )

        session.openCommandPalette()
        session.commandPaletteQuery = "ref"
        session.refreshCommandPalette()

        #expect(session.filteredCommands == [.refine])
    }

    @Test
    func commandPaletteNavigationWrapsWithinFilteredResults() throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let session = ScratchpadSession(
            repository: fixture.repository,
            userDefaults: fixture.userDefaults
        )

        session.openCommandPalette()
        session.commandPaletteQuery = "note"
        session.refreshCommandPalette()

        #expect(session.filteredCommands == [.findNote])
        session.moveCommandSelection(by: 1)
        #expect(session.selectedCommandIndex == 0)
    }

    @Test
    func selectedCommandReturnsCurrentChoice() throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let session = ScratchpadSession(
            repository: fixture.repository,
            userDefaults: fixture.userDefaults
        )

        session.openCommandPalette()
        session.selectCommand(at: 2)

        #expect(session.selectedCommand() == .refine)
    }

    @Test
    func startingRefinementClosesCommandPalette() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let session = ScratchpadSession(
            repository: fixture.repository,
            refinementProvider: ControlledRefinementProvider(),
            userDefaults: fixture.userDefaults
        )
        session.text = "refine this"

        session.openCommandPalette()
        session.startRefinement()

        #expect(session.surface == .refining)
    }

    @Test
    func focusRequestHelpersIncrementCounters() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let session = ScratchpadSession(
            repository: fixture.repository,
            userDefaults: fixture.userDefaults
        )

        session.requestSearchFocus()
        session.requestCommandPaletteFocus()

        #expect(session.searchFocusRequest == 1)
        #expect(session.commandPaletteFocusRequest == 1)
    }

    private func makeFixture() throws -> Fixture {
        let databaseURL = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appendingPathExtension("sqlite")
        let suiteName = "RascTests.\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        userDefaults.removePersistentDomain(forName: suiteName)
        return Fixture(
            databaseURL: databaseURL,
            repository: try NoteRepository(databaseURL: databaseURL),
            userDefaults: userDefaults,
            suiteName: suiteName
        )
    }
}

private struct Fixture {
    let databaseURL: URL
    let repository: NoteRepository
    let userDefaults: UserDefaults
    let suiteName: String

    func remove() {
        userDefaults.removePersistentDomain(forName: suiteName)
    }
}

private struct ControlledRefinementProvider: RefinementProvider {
    let metadata = RefinementMetadata(
        provider: "test",
        modelIdentifier: "test",
        promptVersion: "test"
    )

    func availability(for _: RefinementRequest) async -> RefinementAvailability {
        .available
    }

    func refine(_ request: RefinementRequest) async throws -> RefinementResult {
        try await Task.sleep(for: .milliseconds(50))
        return RefinementResult(
            decision: .changed,
            kind: .messyText,
            text: "Refined \(request.inputText)"
        )
    }
}

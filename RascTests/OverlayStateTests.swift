import Foundation
import Testing
@testable import Rasc

@Suite(.serialized)
@MainActor
struct OverlayStateTests {
    @Test
    func surfaceLayoutKeepsSharedOrbAnchorWithoutUniversalBodyOrigin() {
        #expect(RascSurfaceLayout.horizontalInset == 20)
        #expect(RascSurfaceLayout.topInset == 2)
        #expect(RascSurfaceLayout.orbSize == 20)
        #expect(RascSurfaceLayout.scratchpadContentGap >= 14)
        #expect(RascSurfaceLayout.scratchpadContentGap <= 18)
        #expect(
            RascSurfaceMetrics.editorTopPadding
                == RascSurfaceLayout.topInset
                    + RascSurfaceLayout.orbSize
                    + RascSurfaceLayout.scratchpadContentGap
        )
        #expect(RascSurfaceMetrics.placeholderLeadingInset == RascSurfaceLayout.noteTextLeadingInset)
        #expect(RascSurfaceLayout.orbLeading == 20)
        #expect(RascSurfaceLayout.orbTop == 2)
        #expect(RascSurfaceLayout.orbSize == 20)
        #expect(RascSurfaceLayout.searchFieldOrbVerticalOffset == 6)
    }

    @Test
    func semanticOrbStateStaysOnNoteUnlessRefiningOrSearching() {
        #expect(RascOrbState.resolve(isRefining: false) == .note)
        #expect(RascOrbState.resolve(isRefining: false, isSearching: true) == .searching)
        #expect(RascOrbState.resolve(isRefining: true) == .refining)
        #expect(RascOrbState.resolve(isRefining: true, isSearching: true) == .refining)
    }

    @Test
    func semanticOrbStateOwnsThinkingOrbMappingAndTuning() {
        #expect(RascOrbState.note.thinkingOrbState.rawValue == "solving")
        #expect(RascOrbState.note.speed == 0.5)
        #expect(RascOrbState.searching.thinkingOrbState.rawValue == "searching")
        #expect(RascOrbState.searching.speed == 0.68)
        #expect(RascOrbState.refining.thinkingOrbState.rawValue == "shaping")
        #expect(RascOrbState.refining.speed == 1)
        #expect(!RascOrbState.note.isPaused)
        #expect(!RascOrbState.searching.isPaused)
        #expect(!RascOrbState.refining.isPaused)
    }

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
        #expect(session.filteredCommands == PaletteCommand.allCases)
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
    func commandPaletteListsAllCommands() throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let session = ScratchpadSession(
            repository: fixture.repository,
            userDefaults: fixture.userDefaults
        )

        session.openCommandPalette()

        #expect(session.filteredCommands == PaletteCommand.allCases)
    }

    @Test
    func commandPaletteNavigationStaysWithinAllCommands() throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let session = ScratchpadSession(
            repository: fixture.repository,
            userDefaults: fixture.userDefaults
        )

        session.openCommandPalette()
        session.selectCommand(at: PaletteCommand.allCases.count - 1)

        session.moveCommandSelection(by: 1)
        #expect(session.selectedCommandIndex == PaletteCommand.allCases.count - 1)
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
        session.requestCommandPaletteKeyFocus()

        #expect(session.searchFocusRequest == 1)
        #expect(session.commandPaletteKeyFocusRequest == 1)
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

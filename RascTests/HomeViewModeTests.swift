import Foundation
import Testing
@testable import Rasc

@Suite(.serialized)
struct HomeViewModeTests {
    private func makeRepository() throws -> NoteRepository {
        let databaseURL = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appendingPathExtension("sqlite")
        return try NoteRepository(databaseURL: databaseURL)
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "HomeViewModeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    @Test
    func defaultModeIsListAndUnknownValuesFallBackToList() {
        let store = HomeViewModeStore(userDefaults: makeDefaults())
        #expect(store.load() == .list)

        let defaults = makeDefaults()
        defaults.set("mosaic", forKey: HomeViewModeStore.preferenceKey)
        #expect(HomeViewModeStore(userDefaults: defaults).load() == .list)
    }

    @Test
    func persistsTheChosenMode() {
        let defaults = makeDefaults()
        let store = HomeViewModeStore(userDefaults: defaults)
        store.save(.cards)
        #expect(HomeViewModeStore(userDefaults: defaults).load() == .cards)
        store.save(.list)
        #expect(HomeViewModeStore(userDefaults: defaults).load() == .list)
    }

    @Test
    func gridNavigationMovesByColumnsThenClamps() async throws {
        let repository = try makeRepository()
        for index in 0..<6 {
            _ = try await repository.createScratch(content: "gridnav sharedtoken number \(index) body words")
        }
        let session = await MainActor.run {
            HomeSession(repository: repository)
        }
        await MainActor.run {
            session.searchQuery = "sharedtoken"
        }
        await session.reloadImmediately()

        let ids = await MainActor.run { session.searchResults.map(\.id) }
        #expect(ids.count == 6)
        // A reload selects the first result.
        #expect(await MainActor.run { session.selectedNoteID } == ids[0])

        await MainActor.run {
            session.moveSelection(.right, columns: 3)
        }
        #expect(await MainActor.run { session.selectedNoteID } == ids[1])

        await MainActor.run { session.moveSelection(.right, columns: 3) }
        #expect(await MainActor.run { session.selectedNoteID } == ids[2])

        // Right clamps at the row boundary instead of wrapping.
        await MainActor.run { session.moveSelection(.right, columns: 3) }
        #expect(await MainActor.run { session.selectedNoteID } == ids[2])

        // Down moves one row in a 3-column grid.
        await MainActor.run { session.moveSelection(.down, columns: 3) }
        #expect(await MainActor.run { session.selectedNoteID } == ids[5])

        await MainActor.run { session.moveSelection(.left, columns: 3) }
        #expect(await MainActor.run { session.selectedNoteID } == ids[4])

        await MainActor.run { session.moveSelection(.up, columns: 3) }
        #expect(await MainActor.run { session.selectedNoteID } == ids[1])

        // Up clamps to the first row and keeps the column.
        await MainActor.run { session.moveSelection(.up, columns: 3) }
        #expect(await MainActor.run { session.selectedNoteID } == ids[1])

        await MainActor.run { session.moveSelection(.left, columns: 3) }
        #expect(await MainActor.run { session.selectedNoteID } == ids[0])
    }

    @Test
    func singleColumnNavigationIsRowByRow() async throws {
        let repository = try makeRepository()
        for index in 0..<3 {
            _ = try await repository.createScratch(content: "singlenav sharedtoken number \(index) body words")
        }
        let session = await MainActor.run {
            HomeSession(repository: repository)
        }
        await MainActor.run {
            session.searchQuery = "singlenav"
        }
        await session.reloadImmediately()
        let ids = await MainActor.run { session.searchResults.map(\.id) }
        #expect(ids.count == 3)

        // A reload selects the first result.
        #expect(await MainActor.run { session.selectedNoteID } == ids[0])

        await MainActor.run { session.moveSelection(.down, columns: 1) }
        #expect(await MainActor.run { session.selectedNoteID } == ids[1])

        await MainActor.run { session.moveSelection(.down, columns: 1) }
        #expect(await MainActor.run { session.selectedNoteID } == ids[2])

        // Left/right are inert in the list.
        await MainActor.run { session.moveSelection(.right, columns: 1) }
        #expect(await MainActor.run { session.selectedNoteID } == ids[2])
        await MainActor.run { session.moveSelection(.left, columns: 1) }
        #expect(await MainActor.run { session.selectedNoteID } == ids[2])
    }
}

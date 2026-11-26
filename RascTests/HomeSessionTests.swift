import Foundation
import Testing
@testable import Rasc

@Suite(.serialized)
struct HomeSessionTests {
    @Test
    func searchDelegatesToRepositoryRanking() async throws {
        let repository = try makeRepository()
        let alpha = try await repository.createScratch(content: "alpha deployment checklist")
        let beta = try await repository.createScratch(content: "beta release notes")
        try await repository.update(id: beta.id, content: "beta deployment checklist")

        let repositoryResults = try await repository.search("deployment", limit: HomeSession.searchResultLimit)

        let session = await MainActor.run {
            HomeSession(repository: repository)
        }
        await MainActor.run {
            session.searchQuery = "deployment"
        }
        await session.reloadImmediately()

        let sessionResults = await MainActor.run { session.searchResults }
        #expect(sessionResults.map(\.id) == repositoryResults.map(\.id))
    }

    @Test
    func reloadReflectsUpdatedNoteContent() async throws {
        let repository = try makeRepository()
        let note = try await repository.createScratch(content: "original title line\nbody")
        let session = await MainActor.run {
            HomeSession(repository: repository)
        }
        await session.reloadImmediately()

        try await repository.update(id: note.id, content: "revised title line\nupdated body")
        await session.reloadImmediately()

        let title = await MainActor.run {
            session.browseGroups.flatMap(\.notes).first?.displayTitle
        }
        #expect(title == "revised title line")
    }

    @Test
    func emptiedNoteStaysInHomeWithAReadableTitle() async throws {
        let repository = try makeRepository()
        let note = try await repository.createScratch(content: "queue retry investigation")
        try await repository.update(id: note.id, content: "")

        let session = await MainActor.run {
            HomeSession(repository: repository)
        }
        await session.reloadImmediately()

        let shown = await MainActor.run {
            session.browseGroups.flatMap(\.notes)
        }
        #expect(shown.map(\.id) == [note.id])
        #expect(shown.first?.displayTitle == "Empty thought")
        #expect(shown.first?.isKept == false)

        await MainActor.run {
            session.searchQuery = "queue"
        }
        await session.reloadImmediately()
        let matches = await MainActor.run { session.searchResults.map(\.id) }
        #expect(matches.isEmpty)
    }

    @Test
    func emptiedKeptNoteStaysInTheKeptGroup() async throws {
        let repository = try makeRepository()
        let note = try await repository.createScratch(content: "kept thought")
        _ = try await repository.keep(id: note.id)
        try await repository.update(id: note.id, content: "")

        let session = await MainActor.run {
            HomeSession(repository: repository)
        }
        await session.reloadImmediately()

        let groups = await MainActor.run { session.browseGroups }
        #expect(groups.first?.kind == .kept)
        #expect(groups.first?.notes.map(\.id) == [note.id])
        #expect(groups.first?.notes.first?.displayTitle == "Empty thought")
        #expect(groups.first?.notes.first?.isKept == true)
    }

    @Test
    func discardNoteRemovesNoteFromHome() async throws {
        let repository = try makeRepository()
        let kept = try await repository.createScratch(content: "kept note")
        let discarded = try await repository.createScratch(content: "discarded note")

        let session = await MainActor.run {
            HomeSession(repository: repository)
        }
        await session.reloadImmediately()
        try await session.discardNote(id: discarded.id)

        let noteIDs = await MainActor.run {
            session.browseGroups.flatMap(\.notes).map(\.id)
        }

        #expect(noteIDs == [kept.id])
    }

    @Test
    func duplicateNoteCreatesNewUnfinishedNoteWithSameContent() async throws {
        let repository = try makeRepository()
        let source = try await repository.createScratch(content: "source title\nsource body")
        try await repository.keep(id: source.id)

        let session = await MainActor.run {
            HomeSession(repository: repository)
        }
        await session.reloadImmediately()

        let duplicate = try await session.duplicateNote(id: source.id)

        #expect(duplicate.id != source.id)
        #expect(duplicate.content == source.content)
        #expect(duplicate.keptAt == nil)

        let noteIDs = await MainActor.run {
            session.browseGroups.flatMap(\.notes).map(\.id)
        }
        #expect(noteIDs.contains(duplicate.id))
        #expect(noteIDs.contains(source.id))

        let selectedID = await MainActor.run { session.selectedNoteID }
        #expect(selectedID == duplicate.id)
    }

    @Test
    func unkeepNoteMovesKeptNoteOutOfKeptSection() async throws {
        let repository = try makeRepository()
        let kept = try await repository.createScratch(content: "kept note")
        _ = try await repository.keep(id: kept.id)

        let session = await MainActor.run {
            HomeSession(repository: repository)
        }
        await session.reloadImmediately()

        let keptSectionCount = await MainActor.run {
            session.browseGroups.filter {
                if case .kept = $0.kind { return true }
                return false
            }.flatMap(\.notes).count
        }
        #expect(keptSectionCount == 1)

        try await session.unkeepNote(id: kept.id)

        let keptSectionCountAfter = await MainActor.run {
            session.browseGroups.filter {
                if case .kept = $0.kind { return true }
                return false
            }.flatMap(\.notes).count
        }
        let noteIDs = await MainActor.run {
            session.browseGroups.flatMap(\.notes).map(\.id)
        }

        #expect(keptSectionCountAfter == 0)
        #expect(noteIDs.contains(kept.id))
        #expect(try await repository.fetch(id: kept.id)?.keptAt == nil)
    }

    @Test
    func excludesDeletedNotesFromChronologicalHome() async throws {
        let repository = try makeRepository()
        let kept = try await repository.createScratch(content: "kept note")
        let deleted = try await repository.createScratch(content: "deleted note")
        try await repository.delete(id: deleted.id)

        let session = await MainActor.run {
            HomeSession(repository: repository)
        }
        await session.reloadImmediately()

        let noteIDs = await MainActor.run {
            session.browseGroups.flatMap(\.notes).map(\.id)
        }

        #expect(noteIDs == [kept.id])
    }

    @Test
    @MainActor
    func arrowNavigationFollowsGridRowsWithoutHorizontalWrapping() async throws {
        let repository = try makeRepository()
        for index in 0..<8 { _ = try await repository.createScratch(content: "thought \(index)") }
        let session = HomeSession(repository: repository)
        await session.reloadImmediately()
        let notes = session.displayedNotes
        session.selectNote(notes[1].id)
        session.moveSelection(.down, columns: 3)
        #expect(session.selectedNoteID == notes[4].id)
        session.moveSelection(.down, columns: 3)
        #expect(session.selectedNoteID == notes[7].id)
        session.moveSelection(.right, columns: 3)
        #expect(session.selectedNoteID == notes[7].id)
        session.moveSelection(.up, columns: 3)
        #expect(session.selectedNoteID == notes[4].id)
        session.selectNote(notes[3].id)
        session.moveSelection(.left, columns: 3)
        #expect(session.selectedNoteID == notes[3].id)
        session.moveSelection(.down, columns: 1)
        #expect(session.selectedNoteID == notes[4].id)
    }

    @Test(arguments: [13, 50])
    @MainActor
    func keptThoughtsCanBeRevealedAndDiscardCanBeUndone(count: Int) async throws {
        let repository = try makeRepository()
        for index in 0..<count {
            let note = try await repository.createScratch(content: "kept thought \(index)")
            _ = try await repository.keep(id: note.id)
        }
        let session = HomeSession(repository: repository)
        await session.reloadImmediately()
        #expect(session.keptCount == count)
        #expect(session.displayedNotes.count == 12)
        session.toggleKeptVisibility()
        #expect(session.displayedNotes.count == count)
        let original = try #require(session.displayedNotes.last)
        try await session.discardNote(id: original.id)
        #expect(session.displayedNotes.count == count - 1)
        await session.undoDiscard()
        let restored = try #require(try await repository.fetch(id: original.id))
        #expect(restored == original)
        #expect(session.displayedNotes.count == count)
        #expect(session.selectedNoteID == original.id)
        #expect(session.lastDiscard == nil)
    }

    @Test
    func discardReceiptCannotRestoreALaterDiscard() async throws {
        let repository = try makeRepository()
        let original = try await repository.createScratch(content: "do not lose this thought")
        let first = try #require(try await repository.delete(id: original.id))
        _ = try await repository.restoreDiscard(first)
        let second = try #require(try await repository.delete(id: original.id))
        await #expect(throws: NoteRepository.PersistenceError.self) { try await repository.restoreDiscard(first) }
        #expect(try await repository.fetch(id: original.id) == nil)
        #expect(try await repository.restoreDiscard(second).content == original.content)
    }

    @Test
    func searchSnippetIncludesMatchBeyondTheOpeningLine() {
        let text = "Planning the handoff\n" + String(repeating: "background context ", count: 15) + "accessibility audit before shipping"
        let note = Note(id: UUID(), content: text, createdAt: Date(), updatedAt: Date(), deletedAt: nil, keptAt: nil)
        #expect(note.retrievalSnippet(matching: "accessibility")?.contains("accessibility audit") == true)
        #expect(note.retrievalSnippet(matching: "accessibility")?.hasPrefix("…") == true)
    }

    @Test(arguments: [1, 2, 3, 4])
    @MainActor
    func navigationCrossesSectionBoundariesInActualColumns(columns: Int) async throws {
        let repository = try makeRepository()
        for index in 0..<5 {
            let note = try await repository.createScratch(content: "kept \(index)")
            _ = try await repository.keep(id: note.id)
        }
        for index in 0..<4 { _ = try await repository.createScratch(content: "unfinished \(index)") }
        let session = HomeSession(repository: repository)
        await session.reloadImmediately()
        let notes = session.displayedNotes
        let lastKeptColumn = 4 % columns
        session.selectNote(notes[4].id)
        session.moveSelection(.down, columns: columns)
        #expect(session.selectedNoteID == notes[5 + lastKeptColumn].id)
        session.moveSelection(.up, columns: columns)
        #expect(session.selectedNoteID == notes[4].id)
    }

    @Test
    @MainActor
    func retrievalCapsExplainOmittedMatches() async throws {
        let repository = try makeRepository()
        for index in 0..<501 { _ = try await repository.createScratch(content: "matching thought \(index)") }
        let home = HomeSession(repository: repository)
        home.searchQuery = "matching"
        await home.reloadImmediately()
        #expect(home.searchResults.count == 500)
        #expect(home.hasMoreSearchResults)
        let suite = "RascSearch.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let scratch = ScratchpadSession(repository: repository, userDefaults: defaults)
        try await scratch.openSearch()
        scratch.searchQuery = "matching"
        try await scratch.refreshSearch()
        #expect(scratch.searchResults.count == 12)
        #expect(scratch.hasMoreSearchResults)
        home.searchQuery = "nomatch"
        await home.reloadImmediately()
        #expect(!home.hasMoreSearchResults)
    }

    @Test
    @MainActor
    func copyIncludesTheFullImageDocument() async throws {
        let repository = try makeRepository()
        let image = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==")!
        let document = NoteDocument(parts: [.text("mixed"), .image(data: image, typeIdentifier: "public.png")])
        let mixed = try await repository.createScratch(document: document)
        let plain = try await repository.createScratch(content: "plain")
        let session = HomeSession(repository: repository)
        #expect(try await session.documentForCopy(id: plain.id) == NoteDocument(parts: [.text("plain")]))
        #expect(try await session.documentForCopy(id: mixed.id) == document)
        #expect(try await repository.fetchDocument(id: mixed.id) == document)
    }

    @Test
    @MainActor
    func duplicateWaitsForImagePasteAndCopiesTheCurrentDocument() async throws {
        let repository = try makeRepository()
        let note = try await repository.createScratch(content: "active thought")
        let suite = "RascDuplicate.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let scratch = ScratchpadSession(repository: repository, userDefaults: defaults)
        #expect(try await scratch.openNote(id: note.id))
        let image = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==")!
        let pending = try #require(scratch.beginImageImport(.data(image), selection: NSRange(location: 6, length: 0)))
        let home = HomeSession(repository: repository, prepareForDuplicate: { id in try await scratch.flushIfActiveNote(id: id) })
        let copy = try await home.duplicateNote(id: note.id)
        #expect(try await pending.value != nil)
        let source = try #require(try await repository.fetchDocument(id: note.id))
        #expect(source.hasImages)
        #expect(try await repository.fetchDocument(id: copy.id) == source)
    }

    @Test
    @MainActor
    func duplicateStopsWhenActiveSaveFails() async throws {
        let repository = try makeRepository()
        let note = try await repository.createScratch(content: "original")
        let home = HomeSession(repository: repository, prepareForDuplicate: { _ in throw NoteRepository.PersistenceError.staleContent })
        await #expect(throws: NoteRepository.PersistenceError.staleContent) { try await home.duplicateNote(id: note.id) }
        #expect(try await repository.fetchAllNonDeleted().map(\.id) == [note.id])
    }

    @Test
    @MainActor
    func historyHintNeedsEnoughNotesAndHomeVisits() async throws {
        let repository = try makeRepository()
        let suite = "RascDiscovery.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = OnboardingStore(userDefaults: defaults)
        let session = HomeSession(repository: repository, discoveryStore: store)

        _ = try await repository.createScratch(content: "first thought")
        await session.reloadImmediately()
        session.recordHomeVisit()
        #expect(!session.showsHistoryHint)

        _ = try await repository.createScratch(content: "second thought")
        _ = try await repository.createScratch(content: "third thought")
        await session.reloadImmediately()
        #expect(!session.showsHistoryHint)

        session.recordHomeVisit()
        #expect(session.showsHistoryHint)
        #expect(store.homeVisitCount == 2)

        session.dismissHistoryHint()
        #expect(!session.showsHistoryHint)
        #expect(store.historyHintDismissed)

        await session.reloadImmediately()
        #expect(!session.showsHistoryHint)
    }

    private func makeRepository() throws -> NoteRepository {
        let databaseURL = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appendingPathExtension("sqlite")
        return try NoteRepository(databaseURL: databaseURL)
    }

    @MainActor
    @Test
    func multiSelectionCommandClickTogglesAndShiftClickRanges() async throws {
        let repository = try makeRepository()
        var ids: [UUID] = []
        for index in 0..<5 { ids.append(try await repository.createScratch(content: "note \(index)").id) }
        let session = HomeSession(repository: repository)
        await session.reloadImmediately()

        #expect(session.selectedCount == 0)
        session.toggleSelection(ids[1])
        #expect(session.selectedNoteIDs == [ids[1]])
        session.toggleSelection(ids[3])
        #expect(session.selectedNoteIDs == [ids[1], ids[3]])
        session.toggleSelection(ids[1])
        #expect(session.selectedNoteIDs == [ids[3]])

        session.selectNote(ids[0])
        session.toggleSelection(ids[0]) // anchor
        session.extendSelectionTo(ids[4])
        #expect(session.selectedNoteIDs.contains(ids[4]))
        #expect(session.selectedNoteIDs.isSubset(of: Set(ids)))

        session.clearSelection()
        #expect(session.selectedCount == 0)
        #expect(!session.isSelectionMode)
    }

    @MainActor
    @Test
    func selectAllVisibleSelectsFilteredSet() async throws {
        let repository = try makeRepository()
        _ = try await repository.createScratch(content: "apple pie")
        _ = try await repository.createScratch(content: "apple crumble")
        _ = try await repository.createScratch(content: "banana bread")
        let session = HomeSession(repository: repository)
        session.searchQuery = "apple"
        await session.reloadImmediately()

        session.selectAllVisible()
        #expect(session.selectedCount == session.displayedNotes.count)
        #expect(session.selectedCount == 2)
        #expect(session.isSelectionMode)

        session.searchQuery = "banana"
        await session.reloadImmediately()
        #expect(session.selectedCount == 0) // pruned to visible
    }

    @MainActor
    @Test
    func batchCopyJoinsSelectedInVisibleOrder() async throws {
        let repository = try makeRepository()
        let first = try await repository.createScratch(content: "first thought")
        let second = try await repository.createScratch(content: "second thought")
        let session = HomeSession(repository: repository)
        await session.reloadImmediately()

        session.toggleSelection(first.id)
        session.toggleSelection(second.id)
        let text = try await session.copySelectedText()
        #expect(text.contains("first thought"))
        #expect(text.contains("second thought"))
        #expect(text.contains("\n\n---\n\n"))
    }

    @MainActor
    @Test
    func batchDiscardIsSingleTransactionAndRestoresAllWithUndo() async throws {
        let repository = try makeRepository()
        var ids: [UUID] = []
        for index in 0..<3 { ids.append(try await repository.createScratch(content: "note \(index)").id) }
        let session = HomeSession(repository: repository)
        await session.reloadImmediately()
        for id in ids { session.toggleSelection(id) }

        try await session.discardSelected()
        #expect(session.selectedCount == 0)
        #expect(try await repository.fetchAllNonDeleted().isEmpty)
        #expect(session.lastDiscardBatch.count == 3)
        #expect(session.hasUndoableDiscard)

        await session.undoDiscardBatch()
        let restored = try await repository.fetchAllNonDeleted()
        #expect(restored.count == 3)
        #expect(session.lastDiscardBatch.isEmpty)
    }

    @MainActor
    @Test
    func repositoryBatchDeleteIsAtomicAndRestoresAtomically() async throws {
        let repository = try makeRepository()
        var ids: Set<UUID> = []
        for index in 0..<4 { ids.insert(try await repository.createScratch(content: "note \(index)").id) }
        let receipts = try await repository.delete(ids: ids)
        #expect(receipts.count == 4)
        #expect(try await repository.fetchAllNonDeleted().isEmpty)
        let restored = try await repository.restoreDiscards(receipts)
        #expect(restored.count == 4)
        #expect(try await repository.fetchAllNonDeleted().count == 4)
        var rethrown = false
        do { _ = try await repository.restoreDiscards(receipts) } catch { rethrown = true }
        #expect(rethrown)
    }

    @MainActor
    @Test
    func emptySearchClearsSelectionAndSelectionMode() async throws {
        let repository = try makeRepository()
        let note = try await repository.createScratch(content: "alpha thought")
        let session = HomeSession(repository: repository)
        await session.reloadImmediately()

        session.toggleSelection(note.id)
        #expect(session.isSelectionMode)
        #expect(session.selectedCount == 1)

        session.searchQuery = "zzznomatch"
        await session.reloadImmediately()
        #expect(session.displayedNotes.isEmpty)
        #expect(session.selectedCount == 0)
        #expect(session.selectionAnchorID == nil)
        #expect(!session.isSelectionMode)
    }

    @MainActor
    @Test
    func toggleKeptVisibilityPrunesNewlyHiddenKeptNotesFromSelection() async throws {
        let repository = try makeRepository()
        for index in 0..<(HomeLifecycleGrouping.keptSectionLimit + 2) {
            let note = try await repository.createScratch(content: "kept \(index)")
            _ = try await repository.keep(id: note.id)
        }
        let session = HomeSession(repository: repository)
        session.showsAllKept = true
        await session.reloadImmediately()
        session.selectAllVisible()
        #expect(session.selectedCount == HomeLifecycleGrouping.keptSectionLimit + 2)

        session.toggleKeptVisibility()
        #expect(!session.showsAllKept)
        #expect(session.selectedCount == HomeLifecycleGrouping.keptSectionLimit)
        #expect(session.selectedNoteIDs == Set(session.displayedNotes.map(\.id)))
    }

    @MainActor
    @Test
    func shiftClickAnchorsOnFirstCallAndSelectsExactVisibleRange() async throws {
        let repository = try makeRepository()
        var ids: [UUID] = []
        for index in 0..<5 { ids.append(try await repository.createScratch(content: "note \(index)").id) }
        let session = HomeSession(repository: repository)
        await session.reloadImmediately()
        let orderedIDs = session.displayedNotes.map(\.id)

        session.selectNote(orderedIDs[1])
        session.extendSelectionTo(orderedIDs[3])
        #expect(session.selectionAnchorID == orderedIDs[1])
        #expect(session.selectedNoteIDs == Set(orderedIDs[1...3]))

        // Extending from the original anchor in the opposite direction includes [0...1] as well.
        session.extendSelectionTo(orderedIDs[0])
        #expect(session.selectedNoteIDs == Set(orderedIDs[0...3]))
    }

    @MainActor
    @Test
    func keyboardShiftArrowExtendsSelectionAlongVisibleOrder() async throws {
        let repository = try makeRepository()
        for index in 0..<4 { _ = try await repository.createScratch(content: "note \(index)") }
        let session = HomeSession(repository: repository)
        await session.reloadImmediately()
        let orderedIDs = session.displayedNotes.map(\.id)

        session.selectNote(orderedIDs[0])
        session.extendSelection(.down, columns: 1)
        #expect(session.selectedNoteIDs == Set(orderedIDs[0...1]))
        session.extendSelection(.down, columns: 1)
        #expect(session.selectedNoteIDs == Set(orderedIDs[0...2]))
        #expect(session.selectedNoteID == orderedIDs[2])
        #expect(session.isSelectionMode)
    }

    @MainActor
    @Test
    func singleDiscardAfterBatchDiscardClearsStaleBatchUndo() async throws {
        let repository = try makeRepository()
        let a = try await repository.createScratch(content: "first")
        let b = try await repository.createScratch(content: "second")
        let c = try await repository.createScratch(content: "third")
        let session = HomeSession(repository: repository)
        await session.reloadImmediately()

        session.toggleSelection(a.id)
        session.toggleSelection(b.id)
        let batchReceipts = try await session.discardSelected()
        #expect(batchReceipts.count == 2)
        #expect(session.lastDiscardBatch.count == 2)

        try await session.discardNote(id: c.id)
        #expect(session.lastDiscardBatch.isEmpty)
        #expect(session.lastDiscard?.noteID == c.id)

        await session.undoDiscard()
        let remaining = try await repository.fetchAllNonDeleted()
        #expect(remaining.map(\.id) == [c.id])
    }

    @MainActor
    @Test
    func undoDiscardBatchRestoresKeptNotesBeyondCapAndRestoresSelectionMode() async throws {
        let repository = try makeRepository()
        var keptIDs: [UUID] = []
        for index in 0..<(HomeLifecycleGrouping.keptSectionLimit + 2) {
            let note = try await repository.createScratch(content: "kept \(index)")
            _ = try await repository.keep(id: note.id)
            keptIDs.append(note.id)
        }
        let session = HomeSession(repository: repository)
        await session.reloadImmediately()

        let visibleSubset = Array(session.displayedNotes.prefix(2))
        for note in visibleSubset { session.toggleSelection(note.id) }
        try await session.discardSelected()
        #expect(session.selectedCount == 0)

        await session.undoDiscardBatch()
        #expect(session.showsAllKept)
        #expect(session.isSelectionMode)
        #expect(session.selectedNoteIDs == Set(visibleSubset.map(\.id)))
        #expect(session.selectedNoteID != nil)
    }

    @MainActor
    @Test
    func repositoryRestoreDiscardsRollsBackAtomicallyOnStaleReceipt() async throws {
        let repository = try makeRepository()
        let a = try await repository.createScratch(content: "alpha")
        let b = try await repository.createScratch(content: "beta")
        let receipts = try await repository.delete(ids: [a.id, b.id])
        let staleReceipt = NoteDiscardReceipt(noteID: b.id, deletedAt: .distantPast)

        var threw = false
        do {
            _ = try await repository.restoreDiscards([receipts[0], staleReceipt])
        } catch {
            threw = true
        }
        #expect(threw)
        // Neither note should be restored if one receipt in the batch is stale.
        #expect(try await repository.fetchAllNonDeleted().isEmpty)
        // Original valid receipts remain intact and restorable.
        let restored = try await repository.restoreDiscards(receipts)
        #expect(restored.count == 2)
        #expect(try await repository.fetchAllNonDeleted().count == 2)
    }

    @MainActor
    @Test
    func batchCopyPayloadHandlesMixedNotesAndSingleImageSelection() async throws {
        let repository = try makeRepository()
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==")!
        let imageOnly = try await repository.createScratch(document: .init(parts: [.image(data: png, typeIdentifier: "public.png")]))
        let textFirst = try await repository.createScratch(content: "alpha")
        let textSecond = try await repository.createScratch(content: "beta")
        let session = HomeSession(repository: repository)
        await session.reloadImmediately()

        // Single image-only selection preserves singleDocument for rich copy.
        session.toggleSelection(imageOnly.id)
        let singlePayload = try await session.batchCopyPayload()
        #expect(singlePayload.noteCount == 1)
        #expect(singlePayload.includesImages)
        #expect(singlePayload.singleDocument?.hasImages == true)

        // Multi-note selection strips empty image-only fragments and separates text notes cleanly.
        session.toggleSelection(textFirst.id)
        session.toggleSelection(textSecond.id)
        let multiPayload = try await session.batchCopyPayload()
        #expect(multiPayload.noteCount == 3)
        #expect(multiPayload.includesImages)
        #expect(multiPayload.singleDocument == nil)
        #expect(!multiPayload.text.hasPrefix("\n\n---\n\n"))
        #expect(!multiPayload.text.hasSuffix("\n\n---\n\n"))
        #expect(multiPayload.text.contains("alpha"))
        #expect(multiPayload.text.contains("beta"))
        #expect(multiPayload.text.components(separatedBy: "\n\n---\n\n").count == 2)
    }
}

@Suite
struct NoteSnippetTests {
    private func makeNote(_ content: String) -> Note {
        Note(
            id: UUID(),
            content: content,
            createdAt: Date(),
            updatedAt: Date(),
            deletedAt: nil,
            keptAt: nil
        )
    }

    @Test
    func matchInViewAtWordBoundaryWhenTheCutLandsInsideAWord() {
        let content = "alpha beta gamma delta epsilon zeta eta theta pricing tail"
        let snippet = makeNote(content).retrievalSnippet(matching: "pricing")
        #expect(snippet?.contains("pricing") == true)
        #expect(snippet?.hasPrefix("…delta epsilon") == true)
    }

    @Test
    func matchAtStartHasNoLeadingEllipsis() {
        let content = "pricing is the note"
        let snippet = makeNote(content).retrievalSnippet(matching: "pricing")
        #expect(snippet?.hasPrefix("…") == false)
        #expect(snippet == "pricing is the note")
    }

    @Test
    func matchAtEndHasNoTrailingEllipsis() {
        let content = "Alpha beta\nGamma delta\npricing"
        let snippet = makeNote(content).retrievalSnippet(matching: "pricing")
        #expect(snippet == "Alpha beta Gamma delta pricing")
    }

    @Test
    func multibyteContentKeepsGraphemeClustersIntact() {
        let content = "Draft the handoff\n" + String(repeating: "contexto ", count: 8)
            + "👩🏽‍💻 pricing numbers for Marta and José"
        let snippet = makeNote(content).retrievalSnippet(matching: "pricing")
        #expect(snippet?.contains("pricing") == true)
        #expect(snippet?.contains("👩🏽‍💻") == true)
    }

    @Test
    func diacriticInsensitiveMatchKeepsAccentedWord() {
        let content = "Assinatura do preço e da proposta e pricing final"
        let snippet = makeNote(content).retrievalSnippet(matching: "preco")
        #expect(snippet?.contains("preço") == true)
    }

    @Test
    func wordWindowTrimsAtAWordBoundaryInsteadOfCuttingAWordInHalf() {
        let filler = String(repeating: "context ", count: 34)
        let content = filler + "pricing updates for everyone on the team and then some more words to push past the limit for sure yes indeed"
        let snippet = makeNote(content).retrievalSnippet(matching: "pricing") ?? ""
        #expect(snippet.contains("pricing") == true)
        #expect(snippet.hasSuffix("…") == true)
        let trimmed = String(snippet.dropLast(1))
        #expect(trimmed.last?.isWhitespace == false)
        let lastWord = trimmed.split(separator: " ").last.map(String.init) ?? ""
        #expect(content.contains(lastWord) == true)
    }

    @Test
    func unbrokenTokenStillKeepsTheMatchInView() {
        let content = String(repeating: "a", count: 90) + " pricing " + String(repeating: "b", count: 20)
        let snippet = makeNote(content).retrievalSnippet(matching: "pricing")
        #expect(snippet?.contains("pricing") == true)
        #expect(snippet?.hasPrefix("…") == true)
    }

    @Test
    @MainActor
    func releasingHiddenWindowCacheDropsNotesWhilePreservingUndoAndQuery() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "HomeHiddenRelease.\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let repo = try NoteRepository(databaseURL: dir.appending(path: "rasc.sqlite"))
        defer { try? repo.closeForTesting() }

        let n1 = try await repo.createScratch(content: "First cached thought")
        let n2 = try await repo.createScratch(content: "Second cached thought")
        let suite = "HomeHiddenRelease.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let session = HomeSession(repository: repo, discoveryStore: OnboardingStore(userDefaults: defaults))
        await session.reloadImmediately()
        #expect(session.noteCount == 2)

        session.toggleSelection(n1.id)
        _ = try await session.discardSelected(undoManager: UndoManager())
        #expect(session.hasUndoableDiscard)

        session.searchQuery = "Second"
        await session.reloadImmediately()
        #expect(session.searchResults.map(\.id) == [n2.id])

        session.releaseCachedNotesForHiddenWindow()
        #expect(session.browseGroups.isEmpty)
        #expect(session.searchResults.isEmpty)
        #expect(!session.hasMoreSearchResults)
        #expect(session.searchQuery == "Second")
        #expect(session.hasUndoableDiscard)

        await session.reloadImmediately()
        #expect(session.searchResults.map(\.id) == [n2.id])
    }
}

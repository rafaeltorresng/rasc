import Foundation
import Observation

@MainActor
@Observable
final class HomeSession {
    enum NavigationDirection: Equatable { case left, right, up, down }
    static let searchResultLimit = 500

    var searchQuery = "" {
        didSet {
            guard searchQuery != oldValue else { return }
            scheduleReload()
        }
    }

    private(set) var browseGroups: [HomeBrowseGroup] = []
    private(set) var searchResults: [Note] = []
    private(set) var selectedNoteID: UUID?
    private(set) var isLoading = false
    private(set) var loadErrorMessage: String?
    var showsAllKept = false
    var actionErrorMessage: String?
    private(set) var lastDiscard: NoteDiscardReceipt?
    private var discardUndoRegistrations: [UUID: DiscardUndoRegistration] = [:]
    private(set) var hasMoreSearchResults = false

    private let repository: NoteRepository
    private let calendar: Calendar
    private var reloadTask: Task<Void, Never>?
    private var now: Date

    init(
        repository: NoteRepository,
        calendar: Calendar = .current,
        now: Date = Date()
    ) {
        self.repository = repository
        self.calendar = calendar
        self.now = now
    }

    var isSearching: Bool {
        !normalizedSearchQuery.isEmpty
    }

    var emptyStateOrbState: RascOrbState {
        .connecting
    }

    var hasNotes: Bool {
        !browseGroups.isEmpty || !searchResults.isEmpty
    }

    var showsEmptyHome: Bool {
        !isSearching && browseGroups.isEmpty && loadErrorMessage == nil && !isLoading
    }

    var showsNoSearchResults: Bool {
        isSearching && searchResults.isEmpty && loadErrorMessage == nil && !isLoading
    }

    var displayedNotes: [Note] {
        isSearching ? searchResults : visibleBrowseGroups.flatMap(\.notes)
    }

    var keptCount: Int {
        browseGroups.first { $0.kind == .kept }?.notes.count ?? 0
    }

    var visibleBrowseGroups: [HomeBrowseGroup] {
        browseGroups.map { group in
            guard group.kind == .kept, !showsAllKept else { return group }
            return HomeBrowseGroup(kind: .kept, notes: Array(group.notes.prefix(HomeLifecycleGrouping.keptSectionLimit)))
        }
    }

    func toggleKeptVisibility() {
        showsAllKept.toggle()
        reconcileSelection()
    }

    /// Each section starts a new visual row. Horizontal navigation does not wrap.
    func moveSelection(_ direction: NavigationDirection, columns: Int) {
        let width = max(1, columns)
        let sections = isSearching ? [searchResults] : visibleBrowseGroups.map(\.notes)
        let rows = sections.flatMap { notes in
            stride(from: 0, to: notes.count, by: width).map { start in
                Array(notes[start..<min(start + width, notes.count)])
            }
        }
        guard !rows.isEmpty else { selectedNoteID = nil; return }
        guard let row = rows.firstIndex(where: { $0.contains { $0.id == selectedNoteID } }),
              let column = rows[row].firstIndex(where: { $0.id == selectedNoteID }) else {
            selectedNoteID = rows[0][0].id
            return
        }
        switch direction {
        case .left:
            selectedNoteID = rows[row][max(0, column - 1)].id
        case .right:
            selectedNoteID = rows[row][min(rows[row].count - 1, column + 1)].id
        case .up, .down:
            let nextRow = min(max(row + (direction == .up ? -1 : 1), 0), rows.count - 1)
            selectedNoteID = rows[nextRow][min(column, rows[nextRow].count - 1)].id
        }
    }

    func reloadImmediately() async {
        reloadTask?.cancel()
        reloadTask = nil
        await performReload()
    }

    func scheduleReload() {
        reloadTask?.cancel()
        let query = searchQuery

        reloadTask = Task { [weak self] in
            guard let self else { return }

            do {
                try await Task.sleep(for: .milliseconds(75))
                guard !Task.isCancelled, searchQuery == query else { return }
                await performReload()
            } catch is CancellationError {
            } catch {
            }
        }
    }

    func selectNote(_ noteID: UUID?) {
        selectedNoteID = noteID
    }

    func moveSelection(by offset: Int) {
        let notes = displayedNotes
        guard !notes.isEmpty else {
            selectedNoteID = nil
            return
        }

        let currentIndex = notes.firstIndex { $0.id == selectedNoteID } ?? 0
        let nextIndex = min(max(currentIndex + offset, 0), notes.count - 1)
        selectedNoteID = notes[nextIndex].id
    }

    func selectedNote() -> Note? {
        guard let selectedNoteID else { return nil }
        return displayedNotes.first { $0.id == selectedNoteID }
    }

    func discardNote(id: UUID, undoManager: UndoManager? = nil) async throws {
        let receipt = try await repository.delete(id: id)
        lastDiscard = receipt
        if let receipt, let undoManager {
            let registration = DiscardUndoRegistration(manager: undoManager) { [weak self] in
                Task { await self?.undoDiscard(receipt) }
            }
            discardUndoRegistrations[receipt.id] = registration
            registration.register()
        }
        await reloadImmediately()
    }

    func undoDiscard(_ receipt: NoteDiscardReceipt? = nil) async {
        guard let receipt = receipt ?? lastDiscard else { return }
        do {
            let note = try await repository.restoreDiscard(receipt)
            discardUndoRegistrations.removeValue(forKey: receipt.id)?.invalidate()
            if lastDiscard == receipt { lastDiscard = nil }
            actionErrorMessage = nil
            selectedNoteID = note.id
            if note.isKept { showsAllKept = true }
            await reloadImmediately()
        } catch {
            actionErrorMessage = "Couldn't restore this thought. Try Undo again."
        }
    }

    func duplicateNote(id: UUID) async throws -> Note {
        guard let source = try await repository.fetch(id: id) else {
            throw NoteRepository.PersistenceError.staleContent
        }

        let duplicate = try await repository.createScratch(content: source.content)
        selectedNoteID = duplicate.id
        await reloadImmediately()
        return duplicate
    }

    func unkeepNote(id: UUID) async throws {
        _ = try await repository.unkeep(id: id)
        await reloadImmediately()
    }

    func formattedTimestamp(for note: Note) -> String {
        if note.isKept, let keptAt = note.keptAt {
            return HomeNoteTimestampFormatter.format(keptAt, calendar: calendar, now: now)
        }
        return HomeNoteTimestampFormatter.format(note.updatedAt, calendar: calendar, now: now)
    }

    private var normalizedSearchQuery: String {
        searchQuery.precomposedStringWithCanonicalMapping
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func performReload() async {
        now = Date()
        isLoading = true
        loadErrorMessage = nil
        let query = normalizedSearchQuery

        do {
            if query.isEmpty {
                let notes = try await repository.fetchAllNonDeleted()
                guard !Task.isCancelled, normalizedSearchQuery == query else { return }
                browseGroups = HomeLifecycleGrouping.browseGroups(
                    from: notes,
                    calendar: calendar,
                    now: now
                )
                searchResults = []
                hasMoreSearchResults = false
            } else {
                let results = try await repository.search(query, limit: Self.searchResultLimit + 1)
                guard !Task.isCancelled, normalizedSearchQuery == query else { return }
                hasMoreSearchResults = results.count > Self.searchResultLimit
                searchResults = Array(results.prefix(Self.searchResultLimit))
                browseGroups = []
            }

            reconcileSelection()
            isLoading = false
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            browseGroups = []
            searchResults = []
            selectedNoteID = nil
            loadErrorMessage = "Couldn't load notes."
            isLoading = false
        }
    }

    private func reconcileSelection() {
        let notes = displayedNotes
        guard !notes.isEmpty else {
            selectedNoteID = nil
            return
        }

        if let selectedNoteID, notes.contains(where: { $0.id == selectedNoteID }) {
            return
        }

        selectedNoteID = notes.first?.id
    }
}

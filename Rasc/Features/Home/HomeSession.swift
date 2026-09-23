import Foundation
import Observation

@MainActor
@Observable
final class HomeSession {
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
        isSearching ? searchResults : browseGroups.flatMap(\.notes)
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

    func discardNote(id: UUID) async throws {
        try await repository.delete(id: id)
        await reloadImmediately()
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
            } else {
                let results = try await repository.search(query, limit: Self.searchResultLimit)
                guard !Task.isCancelled, normalizedSearchQuery == query else { return }
                searchResults = results
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

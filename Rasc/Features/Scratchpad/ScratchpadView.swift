import Observation
import SwiftUI

@MainActor
@Observable
final class ScratchpadSession {
    enum Surface: Equatable {
        case editor
        case search
    }

    var text = ""
    private(set) var surface = Surface.editor
    var searchQuery = ""
    private(set) var searchResults: [Note] = []
    private(set) var selectedSearchIndex = 0
    private(set) var focusRequest = 0
    private(set) var searchFocusRequest = 0
    private(set) var saveErrorMessage: String?
    private(set) var searchErrorMessage: String?

    private let repository: NoteRepository
    private let activeNoteStore: ActiveNoteStore
    private var noteID: UUID?
    private var autosaveTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?

    init(repository: NoteRepository, userDefaults: UserDefaults = .standard) {
        self.repository = repository
        activeNoteStore = ActiveNoteStore(userDefaults: userDefaults)
    }

    func requestEditorFocus() {
        focusRequest &+= 1
    }

    func restore() async throws {
        resetSearchState()

        if !activeNoteStore.hasEstablishedState {
            if let note = try await repository.fetchMostRecent() {
                noteID = note.id
                text = note.content
                activeNoteStore.noteID = note.id
            } else {
                noteID = nil
                text = ""
                activeNoteStore.noteID = nil
            }
            return
        }

        guard let activeNoteID = activeNoteStore.noteID else {
            activeNoteStore.noteID = nil
            noteID = nil
            text = ""
            return
        }

        guard let note = try await repository.fetch(id: activeNoteID) else {
            activeNoteStore.noteID = nil
            noteID = nil
            text = ""
            return
        }

        noteID = note.id
        text = note.content
    }

    func scheduleAutosave() {
        let previousAutosave = autosaveTask
        previousAutosave?.cancel()
        let snapshot = text

        autosaveTask = Task { [weak self] in
            await previousAutosave?.value

            do {
                try await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled else { return }
                try await self?.persist(snapshot)
            } catch is CancellationError {
                return
            } catch {
                self?.saveErrorMessage = "Couldn't save locally."
            }
        }
    }

    func flush() async throws {
        let pendingAutosave = autosaveTask
        autosaveTask = nil
        pendingAutosave?.cancel()
        await pendingAutosave?.value

        do {
            try await persist(text)
        } catch {
            saveErrorMessage = "Couldn't save locally."
            throw error
        }
    }

    func startNewScratch() async throws {
        try await flush()
        resetSearchState()
        noteID = nil
        activeNoteStore.noteID = nil
        text = ""
    }

    func openSearch() async throws {
        searchTask?.cancel()
        searchTask = nil
        surface = .search
        searchQuery = ""
        searchErrorMessage = nil
        searchFocusRequest &+= 1

        do {
            try await refreshSearch()
        } catch {
            searchResults = []
            selectedSearchIndex = 0
            searchErrorMessage = "Couldn't search local notes."
            throw error
        }
    }

    func scheduleSearch() {
        searchTask?.cancel()
        let query = searchQuery
        searchResults = []
        selectedSearchIndex = 0
        searchErrorMessage = nil

        searchTask = Task { [weak self] in
            guard let self else { return }

            do {
                let results = try await repository.search(query, limit: 12)
                guard !Task.isCancelled,
                      surface == .search,
                      searchQuery == query
                else {
                    return
                }
                applySearchResults(results)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, surface == .search, searchQuery == query else { return }
                searchErrorMessage = "Couldn't search local notes."
            }
        }
    }

    func refreshSearch() async throws {
        let query = searchQuery
        let results = try await repository.search(query, limit: 12)
        guard surface == .search, searchQuery == query else { return }
        applySearchResults(results)
    }

    func moveSearchSelection(by offset: Int) {
        guard !searchResults.isEmpty else {
            selectedSearchIndex = 0
            return
        }

        selectedSearchIndex = min(
            max(selectedSearchIndex + offset, 0),
            searchResults.count - 1
        )
    }

    func selectSearchResult(at index: Int) {
        guard searchResults.indices.contains(index) else { return }
        selectedSearchIndex = index
    }

    @discardableResult
    func openSelectedSearchResult() async throws -> Bool {
        guard surface == .search,
              searchResults.indices.contains(selectedSearchIndex)
        else {
            return false
        }

        let selectedNoteID = searchResults[selectedSearchIndex].id
        let selectedQuery = searchQuery
        try await flush()
        guard surface == .search, searchQuery == selectedQuery else { return false }

        guard let selectedNote = try await repository.fetch(id: selectedNoteID) else {
            try await refreshSearch()
            return false
        }
        guard surface == .search, searchQuery == selectedQuery else { return false }

        noteID = selectedNote.id
        activeNoteStore.noteID = selectedNote.id
        text = selectedNote.content
        resetSearchState()
        requestEditorFocus()
        return true
    }

    func closeSearch() {
        guard surface == .search else { return }
        resetSearchState()
        requestEditorFocus()
    }

    private func persist(_ content: String) async throws {
        if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let noteID {
                try await repository.delete(id: noteID)
                self.noteID = nil
            }
            activeNoteStore.noteID = nil
            return
        }

        if let noteID {
            try await repository.update(id: noteID, content: content)
            activeNoteStore.noteID = noteID
        } else {
            noteID = try await repository.createScratch(content: content).id
            activeNoteStore.noteID = noteID
        }
        saveErrorMessage = nil
    }

    private func applySearchResults(_ results: [Note]) {
        searchResults = results
        selectedSearchIndex = 0
        searchErrorMessage = nil
    }

    private func resetSearchState() {
        searchTask?.cancel()
        searchTask = nil
        surface = .editor
        searchQuery = ""
        searchResults = []
        selectedSearchIndex = 0
        searchErrorMessage = nil
    }
}

struct ScratchpadView: View {
    @Bindable var session: ScratchpadSession
    @FocusState private var editorIsFocused: Bool

    let onEscape: () -> Void

    var body: some View {
        Group {
            switch session.surface {
            case .editor:
                TextEditor(text: $session.text)
                    .font(.system(size: 14, design: .monospaced))
                    .padding(20)
                    .focused($editorIsFocused)
                    .onChange(of: session.focusRequest, initial: true) {
                        requestEditorFocus()
                    }
                    .onChange(of: session.text) {
                        session.scheduleAutosave()
                    }
                    .onExitCommand(perform: onEscape)
            case .search:
                HistorySearchView(session: session)
            }
        }
        .overlay(alignment: .bottomLeading) {
            if let saveErrorMessage = session.saveErrorMessage {
                Text(saveErrorMessage)
                    .foregroundStyle(.red)
                    .padding(12)
            }
        }
    }

    private func requestEditorFocus() {
        Task { @MainActor in
            editorIsFocused = true
        }
    }
}

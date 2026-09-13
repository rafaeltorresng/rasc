import Observation
import SwiftUI

@MainActor
@Observable
final class ScratchpadSession {
    var text = ""
    private(set) var focusRequest = 0
    private(set) var saveErrorMessage: String?

    private let repository: NoteRepository
    private let activeNoteStore: ActiveNoteStore
    private var noteID: UUID?
    private var autosaveTask: Task<Void, Never>?

    init(repository: NoteRepository, userDefaults: UserDefaults = .standard) {
        self.repository = repository
        activeNoteStore = ActiveNoteStore(userDefaults: userDefaults)
    }

    func requestEditorFocus() {
        focusRequest &+= 1
    }

    func restore() async throws {
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
        noteID = nil
        activeNoteStore.noteID = nil
        text = ""
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
}

struct ScratchpadView: View {
    @Bindable var session: ScratchpadSession
    @FocusState private var editorIsFocused: Bool

    let onEscape: () -> Void

    var body: some View {
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

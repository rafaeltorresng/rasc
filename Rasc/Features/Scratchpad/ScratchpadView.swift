import Observation
import SwiftUI

@MainActor
@Observable
final class ScratchpadSession {
    var text = ""
    private(set) var focusRequest = 0
    private(set) var saveErrorMessage: String?

    private let repository: NoteRepository
    private var noteID: UUID?
    private var autosaveTask: Task<Void, Never>?

    init(repository: NoteRepository) {
        self.repository = repository
    }

    func requestEditorFocus() {
        focusRequest &+= 1
    }

    func restore() async throws {
        guard let note = try await repository.fetchMostRecent() else {
            return
        }

        noteID = note.id
        text = note.content
    }

    func scheduleAutosave() {
        autosaveTask?.cancel()
        let snapshot = text

        autosaveTask = Task { [weak self] in
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
        autosaveTask?.cancel()
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
        text = ""
    }

    private func persist(_ content: String) async throws {
        if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let noteID {
                try await repository.delete(id: noteID)
                self.noteID = nil
            }
            return
        }

        if let noteID {
            try await repository.update(id: noteID, content: content)
        } else {
            noteID = try await repository.createScratch(content: content).id
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

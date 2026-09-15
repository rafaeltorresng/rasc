import Observation
import SwiftUI

#if DEBUG
import OSLog
#endif

@MainActor
@Observable
final class ScratchpadSession {
    private enum RefinementRejectionReason: String {
        case providerError = "provider_error"
        case staleResult = "stale_result"
        case cancelled
        case runawayExpansion = "runaway_expansion"
        case contextLeak = "context_leak"
        case invalidReplacement = "invalid_replacement"
        case unavailable
        case noChange = "no_change"
    }

    enum Surface: Equatable {
        case editor
        case search
        case refining
        case refinementPreview
        case message
    }

    var text = "" {
        didSet {
            guard text != oldValue else { return }
            contentRevision &+= 1
            if isApplyingAcceptedRefinement { return }
            if activeRefinementID != nil {
                cancelRefinement()
            } else if surface == .message {
                clearMessage(returnToEditor: true)
            }
        }
    }
    private(set) var contentRevision = 0
    private(set) var surface = Surface.editor
    var searchQuery = ""
    private(set) var searchResults: [Note] = []
    private(set) var selectedSearchIndex = 0
    private(set) var focusRequest = 0
    private(set) var searchFocusRequest = 0
    private(set) var saveErrorMessage: String?
    private(set) var searchErrorMessage: String?
    private(set) var activeRefinementRequest: RefinementRequest?
    private(set) var refinementPreview: RefinementPreview?
    private(set) var message: RefinementMessage?
    private(set) var editorSelection: Range<String.Index>?
    private var editorHasMultipleSelections = false

    private let repository: NoteRepository
    private let refinementProvider: (any RefinementProvider)?
    private let activeNoteStore: ActiveNoteStore
    private var noteID: UUID?
    private var autosaveTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?
    private var refinementTask: Task<Void, Never>?
    private var acceptanceTask: Task<Void, Error>?
    private var messageTask: Task<Void, Never>?
    private var activeRefinementID: UUID?
    private var isApplyingAcceptedRefinement = false

    #if DEBUG
    private static let refinementLogger = Logger(
        subsystem: "com.rasc.app",
        category: "Refinement"
    )
    #endif

    init(
        repository: NoteRepository,
        refinementProvider: (any RefinementProvider)? = nil,
        userDefaults: UserDefaults = .standard
    ) {
        self.repository = repository
        self.refinementProvider = refinementProvider
        activeNoteStore = ActiveNoteStore(userDefaults: userDefaults)
    }

    func requestEditorFocus() {
        focusRequest &+= 1
    }

    func restore() async throws {
        try await acceptanceTask?.value
        cancelRefinement()
        clearMessage(returnToEditor: false)
        editorSelection = nil
        editorHasMultipleSelections = false
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
        try await acceptanceTask?.value

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
        cancelRefinement()
        clearMessage(returnToEditor: false)
        editorSelection = nil
        editorHasMultipleSelections = false
        try await flush()
        resetSearchState()
        noteID = nil
        activeNoteStore.noteID = nil
        text = ""
    }

    func openSearch() async throws {
        try await acceptanceTask?.value
        cancelRefinement()
        clearMessage(returnToEditor: false)
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
        cancelRefinement()
        try await flush()
        guard surface == .search, searchQuery == selectedQuery else { return false }

        guard let selectedNote = try await repository.fetch(id: selectedNoteID) else {
            try await refreshSearch()
            return false
        }
        guard surface == .search, searchQuery == selectedQuery else { return false }

        noteID = selectedNote.id
        activeNoteStore.noteID = selectedNote.id
        editorSelection = nil
        editorHasMultipleSelections = false
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

    func updateEditorSelection(
        _ selection: Range<String.Index>?,
        hasMultipleSelections: Bool = false
    ) {
        editorHasMultipleSelections = hasMultipleSelections
        editorSelection = NoteSnapshot(
            noteID: noteID ?? UUID(),
            revision: contentRevision,
            text: text,
            selection: selection
        ).selection
    }

    func startRefinement() {
        startRefinement(selection: editorSelection)
    }

    func startRefinement(selection: Range<String.Index>?) {
        guard surface != .search, acceptanceTask == nil else { return }

        cancelRefinement()
        clearMessage(returnToEditor: false)

        guard !editorHasMultipleSelections else {
            showMessage(.multipleSelection)
            return
        }

        let capturedText = text
        guard !capturedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            showMessage(.nothingToRefine)
            return
        }

        let requestID = UUID()
        let normalizedSelection = NoteSnapshot(
            noteID: UUID(),
            revision: contentRevision,
            text: capturedText,
            selection: selection
        ).selection
        let draft = PendingRefinement(
            requestID: requestID,
            revision: contentRevision,
            text: capturedText,
            selection: normalizedSelection
        )

        activeRefinementID = requestID
        surface = .refining
        refinementTask = Task { [weak self] in
            await self?.performRefinement(draft)
        }
    }

    @discardableResult
    func handleEscape() -> Bool {
        switch surface {
        case .refining, .refinementPreview:
            cancelRefinement()
            return true
        case .message:
            clearMessage(returnToEditor: true)
            requestEditorFocus()
            return true
        case .search:
            closeSearch()
            return true
        case .editor:
            return false
        }
    }

    func cancelRefinement() {
        guard acceptanceTask == nil else { return }
        let wasRefining = surface == .refining || surface == .refinementPreview
        if wasRefining {
            logRefinementRejection(.cancelled)
        }
        activeRefinementID = nil
        activeRefinementRequest = nil
        refinementPreview = nil
        refinementTask?.cancel()
        refinementTask = nil
        if wasRefining {
            surface = .editor
            requestEditorFocus()
        }
    }

    func acceptRefinement(undoManager: UndoManager? = nil) async throws {
        if let acceptanceTask {
            try await acceptanceTask.value
            return
        }
        guard surface == .refinementPreview,
              let preview = refinementPreview,
              isCurrent(preview.request)
        else {
            return
        }

        let task = Task { [weak self] in
            guard let self else { return }
            defer { acceptanceTask = nil }
            try await commitRefinement(preview, undoManager: undoManager)
        }
        acceptanceTask = task
        try await task.value
    }

    private func commitRefinement(
        _ preview: RefinementPreview,
        undoManager: UndoManager?
    ) async throws {
        let beforeContent = preview.request.snapshot.text
        var afterContent = beforeContent
        let acceptedSelection: Range<String.Index>?
        if let selection = preview.request.snapshot.selection {
            let lowerOffset = beforeContent.distance(
                from: beforeContent.startIndex,
                to: selection.lowerBound
            )
            afterContent.replaceSubrange(selection, with: preview.result.text)
            let lowerBound = afterContent.index(afterContent.startIndex, offsetBy: lowerOffset)
            acceptedSelection = lowerBound..<afterContent.index(
                lowerBound,
                offsetBy: preview.result.text.count
            )
        } else {
            afterContent = preview.result.text
            acceptedSelection = nil
        }

        guard afterContent != beforeContent else {
            finishRefinement(with: .alreadyUseful)
            return
        }

        let pendingAutosave = autosaveTask
        autosaveTask = nil
        pendingAutosave?.cancel()
        await pendingAutosave?.value
        guard isCurrent(preview.request) else { return }

        do {
            _ = try await repository.acceptRefinement(
                noteID: preview.request.snapshot.noteID,
                beforeContent: beforeContent,
                afterContent: afterContent,
                metadata: preview.metadata
            )
        } catch {
            guard isCurrent(preview.request) else { return }
            finishRefinement(with: .couldNotSaveRefinement)
            throw error
        }

        guard isCurrent(preview.request) else { return }
        activeRefinementID = nil
        activeRefinementRequest = nil
        refinementPreview = nil
        refinementTask = nil
        if let undoManager {
            registerUndo(
                with: undoManager,
                restoring: beforeContent,
                inverse: afterContent
            )
        }
        isApplyingAcceptedRefinement = true
        text = afterContent
        isApplyingAcceptedRefinement = false
        editorSelection = acceptedSelection
        editorHasMultipleSelections = false
        surface = .editor
        requestEditorFocus()
    }

    private func registerUndo(
        with undoManager: UndoManager,
        restoring content: String,
        inverse: String
    ) {
        undoManager.registerUndo(withTarget: self) { session in
            session.registerUndo(
                with: undoManager,
                restoring: inverse,
                inverse: content
            )
            session.text = content
            session.requestEditorFocus()
        }
        undoManager.setActionName("Refine")
    }

    private func performRefinement(_ draft: PendingRefinement) async {
        let pendingAutosave = autosaveTask
        autosaveTask = nil
        pendingAutosave?.cancel()
        await pendingAutosave?.value

        guard isCurrent(draft) else {
            logRefinementRejection(Task.isCancelled ? .cancelled : .staleResult)
            return
        }

        do {
            try await persist(draft.text)
            guard isCurrent(draft), let noteID else {
                logRefinementRejection(Task.isCancelled ? .cancelled : .staleResult)
                return
            }

            let request = RefinementRequest(
                requestID: draft.requestID,
                snapshot: NoteSnapshot(
                    noteID: noteID,
                    revision: draft.revision,
                    text: draft.text,
                    selection: draft.selection
                )
            )
            activeRefinementRequest = request

            guard let refinementProvider else {
                logRefinementRejection(.unavailable)
                finishRefinement(with: .unavailable(.unsupportedEnvironment))
                return
            }

            let availability = await refinementProvider.availability(for: request)
            guard isCurrent(request), !Task.isCancelled else {
                logRefinementRejection(Task.isCancelled ? .cancelled : .staleResult)
                return
            }
            guard case .available = availability else {
                if case let .unavailable(reason) = availability {
                    logRefinementRejection(.unavailable)
                    finishRefinement(with: .unavailable(reason))
                }
                return
            }

            let result = try await refinementProvider.refine(request)
            guard isCurrent(request), !Task.isCancelled else {
                logRefinementRejection(Task.isCancelled ? .cancelled : .staleResult)
                return
            }

            switch result.decision {
            case .noChange:
                logRefinementRejection(.noChange)
                finishRefinement(with: .alreadyUseful)
            case .changed:
                guard !result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    rejectRefinementResult(request, reason: .invalidReplacement)
                    return
                }
                guard request.allowsChangedText(result.text) else {
                    rejectRefinementResult(request, reason: .runawayExpansion)
                    return
                }
                guard request.isReplacementOnly(result.text) else {
                    rejectRefinementResult(request, reason: .contextLeak)
                    return
                }
                guard result.text != request.inputText else {
                    logRefinementRejection(.noChange)
                    finishRefinement(with: .alreadyUseful)
                    return
                }
                refinementPreview = RefinementPreview(
                    request: request,
                    result: result,
                    metadata: refinementProvider.metadata
                )
                surface = .refinementPreview
                refinementTask = nil
            }
        } catch is CancellationError {
            logRefinementRejection(.cancelled)
            return
        } catch let error as RefinementError {
            guard isCurrent(draft), !Task.isCancelled else {
                logRefinementRejection(Task.isCancelled ? .cancelled : .staleResult)
                return
            }
            switch error {
            case .contextTooLarge:
                logRefinementRejection(.providerError)
                finishRefinement(with: .contextTooLarge)
            case let .unavailable(reason):
                logRefinementRejection(.unavailable)
                finishRefinement(with: .unavailable(reason))
            case .unsupportedLanguage, .invalidOutput, .providerFailure:
                logRefinementRejection(.providerError)
                finishRefinement(with: .couldNotRefine)
            }
        } catch {
            guard isCurrent(draft), !Task.isCancelled else {
                logRefinementRejection(Task.isCancelled ? .cancelled : .staleResult)
                return
            }
            logRefinementRejection(.providerError)
            finishRefinement(with: .couldNotRefine)
        }
    }

    private func isCurrent(_ draft: PendingRefinement) -> Bool {
        activeRefinementID == draft.requestID
            && contentRevision == draft.revision
            && text == draft.text
    }

    private func isCurrent(_ request: RefinementRequest) -> Bool {
        guard let noteID else { return false }
        return activeRefinementID == request.requestID
            && request.isCurrent(
                noteID: noteID,
                revision: contentRevision,
                requestID: request.requestID
            )
            && text == request.snapshot.text
    }

    private func finishRefinement(with message: RefinementMessage) {
        activeRefinementID = nil
        activeRefinementRequest = nil
        refinementPreview = nil
        refinementTask = nil
        showMessage(message)
    }

    private func rejectRefinementResult(
        _ request: RefinementRequest,
        reason: RefinementRejectionReason
    ) {
        logRefinementRejection(reason)
        finishRefinement(with: request.scope == .selection
            ? .couldNotSafelyRefineSelection
            : .couldNotRefine)
    }

    private func logRefinementRejection(_ reason: RefinementRejectionReason) {
        #if DEBUG
        Self.refinementLogger.debug("\(reason.rawValue, privacy: .public)")
        #endif
    }

    private func showMessage(_ message: RefinementMessage) {
        messageTask?.cancel()
        self.message = message
        surface = .message
        messageTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, self?.message == message else { return }
            self?.clearMessage(returnToEditor: true)
        }
    }

    private func clearMessage(returnToEditor: Bool) {
        messageTask?.cancel()
        messageTask = nil
        message = nil
        if returnToEditor, surface == .message {
            surface = .editor
        }
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

private struct PendingRefinement: Sendable {
    let requestID: UUID
    let revision: Int
    let text: String
    let selection: Range<String.Index>?
}

struct ScratchpadView: View {
    @Bindable var session: ScratchpadSession
    @FocusState private var editorIsFocused: Bool
    @Environment(\.undoManager) private var undoManager

    let onEscape: () -> Void

    var body: some View {
        Group {
            switch session.surface {
            case .editor, .message:
                if #available(macOS 15.0, *) {
                    SelectableScratchEditor(session: session, onEscape: handleEscape)
                } else {
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
                        .onExitCommand(perform: handleEscape)
                }
            case .search:
                HistorySearchView(session: session)
            case .refining:
                TextEditor(text: .constant(session.text))
                    .font(.system(size: 14, design: .monospaced))
                    .padding(20)
                    .disabled(true)
                    .onExitCommand(perform: handleEscape)
                    .overlay(alignment: .bottomLeading) {
                        Text("refining…")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .padding(12)
                    }
            case .refinementPreview:
                VStack(alignment: .leading, spacing: 0) {
                    Text("refined")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                    ScrollView {
                        Text(session.refinementPreview?.result.text ?? "")
                            .font(.system(size: 14, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .padding(20)
                    }
                    HStack {
                        Button("Esc cancel") {
                            _ = session.handleEscape()
                        }
                        .buttonStyle(.plain)
                        .keyboardShortcut(.cancelAction)
                        Spacer()
                        Button("↵ accept") {
                            Task {
                                try? await session.acceptRefinement(undoManager: undoManager)
                            }
                        }
                        .buttonStyle(.plain)
                        .keyboardShortcut(.defaultAction)
                    }
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .padding(12)
                }
                .onExitCommand(perform: handleEscape)
            }
        }
        .overlay(alignment: .bottomLeading) {
            if let saveErrorMessage = session.saveErrorMessage {
                Text(saveErrorMessage)
                    .foregroundStyle(.red)
                    .padding(12)
            } else if let message = session.message {
                Text(message.text)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .padding(12)
            }
        }
    }

    private func requestEditorFocus() {
        Task { @MainActor in
            editorIsFocused = true
        }
    }

    private func handleEscape() {
        if !session.handleEscape() {
            onEscape()
        }
    }
}

@available(macOS 15.0, *)
private struct SelectableScratchEditor: View {
    @Bindable var session: ScratchpadSession
    @State private var selection: TextSelection?
    @FocusState private var isFocused: Bool

    let onEscape: () -> Void

    init(session: ScratchpadSession, onEscape: @escaping () -> Void) {
        self.session = session
        self.onEscape = onEscape
        _selection = State(initialValue: session.editorSelection.map { TextSelection(range: $0) })
    }

    var body: some View {
        TextEditor(text: $session.text, selection: $selection)
            .font(.system(size: 14, design: .monospaced))
            .padding(20)
            .focused($isFocused)
            .onChange(of: session.focusRequest, initial: true) {
                Task { @MainActor in
                    isFocused = true
                }
            }
            .onChange(of: selection, initial: true) {
                session.updateEditorSelection(
                    singleSelectionRange,
                    hasMultipleSelections: selectionIsMultiple
                )
            }
            .onChange(of: session.text) {
                session.updateEditorSelection(
                    singleSelectionRange,
                    hasMultipleSelections: selectionIsMultiple
                )
                session.scheduleAutosave()
            }
            .onExitCommand(perform: onEscape)
    }

    private var singleSelectionRange: Range<String.Index>? {
        guard let selection else { return nil }
        switch selection.indices {
        case let .selection(range):
            return range.isEmpty ? nil : range
        case let .multiSelection(ranges):
            guard ranges.ranges.count == 1,
                  let range = ranges.ranges.first,
                  !range.isEmpty
            else {
                return nil
            }
            return range
        @unknown default:
            return nil
        }
    }

    private var selectionIsMultiple: Bool {
        guard let selection else { return false }
        if case let .multiSelection(ranges) = selection.indices {
            return ranges.ranges.count > 1
        }
        return false
    }
}

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
        case selectionDuplicateContextLeak = "selectionDuplicateContextLeak"
        case invalidReplacement = "invalid_replacement"
        case unavailable
        case noChange = "no_change"
    }

    enum Surface: Equatable {
        case editor
        case search
        case commandPalette
        case refining
        case refinementPreview
        case message
    }

    enum ThoughtCompletionOutcome: Equatable {
        case keptShouldHide
        case none
    }

    var text = "" {
        didSet {
            guard text != oldValue else { return }
            contentRevision &+= 1
            onTextDidChange?(text)
            if isApplyingAcceptedRefinement { return }
            if activeRefinementID != nil {
                cancelRefinement()
            } else if surface == .message {
                clearMessage(returnToEditor: true)
            }
        }
    }
    private(set) var contentRevision = 0
    private(set) var surface = Surface.editor {
        didSet {
            guard oldValue != surface else { return }
            onSurfaceDidChange?(surface)
        }
    }

    var scratchpadGuidance = OnboardingScratchpadGuidance.inactive
    var onTextDidChange: ((String) -> Void)?
    var onSurfaceDidChange: ((Surface) -> Void)?
    var onMessageDidShow: ((RefinementMessage?) -> Void)?

    var surfaceDiagnosticLabel: String {
        switch surface {
        case .editor: "editor"
        case .search: "search"
        case .commandPalette: "command_palette"
        case .refining: "refining"
        case .refinementPreview: "refinement_preview"
        case .message: "message"
        }
    }
    var searchQuery = ""
    private(set) var searchResults: [Note] = []
    private(set) var selectedSearchIndex = 0
    private(set) var focusRequest = 0
    private(set) var searchFocusRequest = 0
    private(set) var settingsPresentationRequest = 0
    private(set) var filteredCommands: [PaletteCommand] = PaletteCommand.availableCommands(
        isKept: false,
        hasPersistableContent: false,
        canPerformCompletion: true
    )
    private(set) var selectedCommandIndex = 0
    private(set) var commandPaletteKeyFocusRequest = 0
    private(set) var saveErrorMessage: String?
    private(set) var searchErrorMessage: String?
    private(set) var activeNoteKeptAt: Date?
    private(set) var transientFeedback: String?
    private(set) var activeRefinementRequest: RefinementRequest?
    private(set) var refinementPreview: RefinementPreview?
    private(set) var message: RefinementMessage?
    private(set) var editorSelection: Range<String.Index>?
    private var editorHasMultipleSelections = false

    private let repository: NoteRepository
    private let refinementProvider: (any RefinementProvider)?
    private let activeNoteStore: ActiveNoteStore
    private let languageSettings: RefineLanguageSettingsStore
    private var noteID: UUID?
    private var autosaveTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?
    private var refinementTask: Task<Void, Never>?
    private var acceptanceTask: Task<Void, Error>?
    private var messageTask: Task<Void, Never>?
    private var feedbackTask: Task<Void, Never>?
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
        userDefaults: UserDefaults = .standard,
        languageSettings: RefineLanguageSettingsStore? = nil
    ) {
        self.repository = repository
        self.refinementProvider = refinementProvider
        activeNoteStore = ActiveNoteStore(userDefaults: userDefaults)
        self.languageSettings = languageSettings ?? RefineLanguageSettingsStore(userDefaults: userDefaults)
    }

    func requestEditorFocus() {
        focusRequest &+= 1
    }

    func requestSearchFocus() {
        searchFocusRequest &+= 1
    }

    func requestCommandPaletteKeyFocus() {
        commandPaletteKeyFocusRequest &+= 1
    }

    func requestSettingsPresentation() {
        settingsPresentationRequest &+= 1
    }

    func markLoadFailed() {
        saveErrorMessage = "Couldn't load local notes."
    }

    var hasPersistableContent: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var isActiveNoteKept: Bool {
        activeNoteKeptAt != nil
    }

    var canPerformThoughtCompletion: Bool {
        acceptanceTask == nil && (surface == .editor || surface == .message)
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
                activeNoteKeptAt = note.keptAt
                activeNoteStore.noteID = note.id
            } else {
                noteID = nil
                text = ""
                activeNoteKeptAt = nil
                activeNoteStore.noteID = nil
            }
            return
        }

        guard let activeNoteID = activeNoteStore.noteID else {
            activeNoteStore.noteID = nil
            noteID = nil
            text = ""
            activeNoteKeptAt = nil
            return
        }

        guard let note = try await repository.fetch(id: activeNoteID) else {
            activeNoteStore.noteID = nil
            noteID = nil
            text = ""
            activeNoteKeptAt = nil
            return
        }

        noteID = note.id
        text = note.content
        activeNoteKeptAt = note.keptAt
    }

    func keepActiveNote() async throws -> ThoughtCompletionOutcome {
        guard canPerformThoughtCompletion, !isActiveNoteKept else { return .none }
        try await prepareForThoughtCompletionAction()
        guard hasPersistableContent, let noteID else { return .none }

        _ = try await repository.keep(id: noteID)
        clearActiveScratchSession()
        showTransientFeedback("Kept")
        return .keptShouldHide
    }

    func unkeepActiveNote() async throws {
        guard canPerformThoughtCompletion, isActiveNoteKept, let noteID else { return }
        try await prepareForThoughtCompletionAction()

        let note = try await repository.unkeep(id: noteID)
        activeNoteKeptAt = note.keptAt
        showTransientFeedback("Unkept")
    }

    func copyActiveNoteText() async throws -> String? {
        guard canPerformThoughtCompletion else { return nil }
        try await prepareForThoughtCompletionAction()
        guard hasPersistableContent else { return nil }
        return text
    }

    func discardActiveNote() async throws {
        guard canPerformThoughtCompletion else { return }
        try await prepareForThoughtCompletionAction()

        if let noteID {
            try await repository.delete(id: noteID)
        }
        clearActiveScratchSession()
        showTransientFeedback("Discarded")
    }

    func abandonActiveNoteIfMatching(id: UUID) async {
        guard noteID == id else { return }

        try? await acceptanceTask?.value
        autosaveTask?.cancel()
        await autosaveTask?.value
        autosaveTask = nil
        cancelRefinement()
        clearMessage(returnToEditor: false)
        clearActiveScratchSession()
    }

    func refreshActiveNoteIfMatching(id: UUID) async {
        guard noteID == id else { return }
        guard let note = try? await repository.fetch(id: id) else { return }
        activeNoteKeptAt = note.keptAt
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
        dismissTransientSurfaces(except: nil)
        editorSelection = nil
        editorHasMultipleSelections = false
        try await flush()
        resetSearchState()
        resetCommandPaletteState()
        noteID = nil
        activeNoteKeptAt = nil
        activeNoteStore.noteID = nil
        text = ""
    }

    func openSearch() async throws {
        try await acceptanceTask?.value
        dismissTransientSurfaces(except: .search)
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
        searchErrorMessage = nil

        searchTask = Task { [weak self] in
            guard let self else { return }

            do {
                try await Task.sleep(for: .milliseconds(75))
                guard !Task.isCancelled,
                      surface == .search,
                      searchQuery == query
                else {
                    return
                }

                let startedAt = ContinuousClock.now
                let results = try await repository.search(query, limit: 12)
                let durationMs = Int((ContinuousClock.now - startedAt).components.attoseconds / 1_000_000_000_000_000)
                guard !Task.isCancelled,
                      surface == .search,
                      searchQuery == query
                else {
                    return
                }
                applySearchResults(results)
                AppDiagnostics.searchCompleted(
                    queryLength: query.count,
                    resultCount: results.count,
                    durationMs: max(durationMs, 0)
                )
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

        return try await openNote(id: searchResults[selectedSearchIndex].id, fromSearchQuery: searchQuery)
    }

    @discardableResult
    func openNote(id: UUID) async throws -> Bool {
        try await openNote(id: id, fromSearchQuery: nil)
    }

    @discardableResult
    private func openNote(id: UUID, fromSearchQuery: String?) async throws -> Bool {
        if fromSearchQuery != nil {
            guard surface == .search else { return false }
        } else {
            dismissTransientSurfaces(except: nil)
        }

        cancelRefinement()
        try await flush()

        if let fromSearchQuery {
            guard surface == .search, searchQuery == fromSearchQuery else { return false }
        }

        guard let selectedNote = try await repository.fetch(id: id) else {
            if fromSearchQuery != nil {
                try await refreshSearch()
            }
            return false
        }

        if let fromSearchQuery {
            guard surface == .search, searchQuery == fromSearchQuery else { return false }
        }

        noteID = selectedNote.id
        activeNoteStore.noteID = selectedNote.id
        activeNoteKeptAt = selectedNote.keptAt
        editorSelection = nil
        editorHasMultipleSelections = false
        text = selectedNote.content
        resetSearchState()
        surface = .editor
        requestEditorFocus()
        return true
    }

    func closeSearch() {
        guard surface == .search else { return }
        resetSearchState()
        requestEditorFocus()
    }

    func openCommandPalette() {
        guard acceptanceTask == nil else { return }
        dismissTransientSurfaces(except: .commandPalette)
        surface = .commandPalette
        refreshPaletteCommands()
        selectedCommandIndex = 0
        requestCommandPaletteKeyFocus()
    }

    func closeCommandPalette() {
        guard surface == .commandPalette else { return }
        resetCommandPaletteState()
        requestEditorFocus()
    }

    func moveCommandSelection(by offset: Int) {
        guard !filteredCommands.isEmpty else {
            selectedCommandIndex = 0
            return
        }

        selectedCommandIndex = min(
            max(selectedCommandIndex + offset, 0),
            filteredCommands.count - 1
        )
    }

    func selectCommand(at index: Int) {
        guard filteredCommands.indices.contains(index) else { return }
        selectedCommandIndex = index
    }

    func selectedCommand() -> PaletteCommand? {
        guard filteredCommands.indices.contains(selectedCommandIndex) else { return nil }
        return filteredCommands[selectedCommandIndex]
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

        if surface == .commandPalette {
            resetCommandPaletteState()
        }
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
        case .commandPalette:
            closeCommandPalette()
            return true
        case .search:
            closeSearch()
            return true
        case .refining, .refinementPreview:
            cancelRefinement()
            return true
        case .message:
            clearMessage(returnToEditor: true)
            requestEditorFocus()
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
            session.scheduleAutosave()
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

            let languagePolicy = languageSettings.resolveEffectivePreference().effectivePolicy
            let request = RefinementRequest(
                requestID: draft.requestID,
                snapshot: NoteSnapshot(
                    noteID: noteID,
                    revision: draft.revision,
                    text: draft.text,
                    selection: draft.selection
                ),
                languagePolicy: languagePolicy
            )
            activeRefinementRequest = request

            if RefinementPreflightPolicy.result(for: request) != nil {
                logRefinementRejection(.noChange)
                finishRefinement(with: .alreadyUseful)
                return
            }

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

            let providerResult = try await refinementProvider.refine(request)
            guard isCurrent(request), !Task.isCancelled else {
                logRefinementRejection(Task.isCancelled ? .cancelled : .staleResult)
                return
            }
            let exactLiteralResult = RefineProtectedLiteralValidator.finalize(providerResult, for: request)
            let moneyResult = RefineMoneyLiteralValidator.finalize(exactLiteralResult, for: request)
            let percentageResult = RefinePercentageLiteralValidator.finalize(moneyResult, for: request)
            let result = RefineTimeLiteralValidator.finalize(percentageResult, for: request)

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
                guard !request.hasDuplicateContextLeak(result.text) else {
                    rejectRefinementResult(request, reason: .selectionDuplicateContextLeak)
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
        onMessageDidShow?(message)
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

    private func resetCommandPaletteState() {
        surface = .editor
        refreshPaletteCommands()
        selectedCommandIndex = 0
    }

    private func refreshPaletteCommands() {
        filteredCommands = paletteCommandsForCurrentState()
    }

    private func paletteCommandsForCurrentState() -> [PaletteCommand] {
        PaletteCommand.availableCommands(
            isKept: isActiveNoteKept,
            hasPersistableContent: hasPersistableContent,
            canPerformCompletion: canPerformThoughtCompletion
        )
    }

    private func prepareForThoughtCompletionAction() async throws {
        try await acceptanceTask?.value
        cancelRefinement()
        clearMessage(returnToEditor: true)
        try await flush()
    }

    private func clearActiveScratchSession() {
        noteID = nil
        activeNoteKeptAt = nil
        activeNoteStore.noteID = nil
        text = ""
        editorSelection = nil
        editorHasMultipleSelections = false
        surface = .editor
    }

    private func showTransientFeedback(_ message: String) {
        feedbackTask?.cancel()
        transientFeedback = message
        feedbackTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, self?.transientFeedback == message else { return }
            self?.transientFeedback = nil
        }
    }

    private func dismissTransientSurfaces(except retained: Surface?) {
        if retained != .search {
            if surface == .search {
                resetSearchState()
            } else {
                searchTask?.cancel()
                searchTask = nil
                searchQuery = ""
                searchResults = []
                selectedSearchIndex = 0
                searchErrorMessage = nil
            }
        }

        if retained != .commandPalette, surface == .commandPalette {
            resetCommandPaletteState()
        }

        cancelRefinement()
        clearMessage(returnToEditor: false)
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
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let onEscape: () -> Void
    let onPaletteCommand: (PaletteCommand) -> Void
    let onOpenHome: () -> Void
    let onKeep: () -> Void
    let onUnkeep: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            if showsScratchpadChrome {
                scratchpadChrome
            }

            surfaceBodyContent
                .padding(.top, showsScratchpadChrome ? RascSurfaceLayout.scratchpadChromeToBodyGap : 0)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .id(session.surface)
                .transition(RascMotion.bodyContentTransition(reduceMotion: reduceMotion))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(RascMotion.bodyContentAnimation(reduceMotion: reduceMotion), value: session.surface)
        .scratchpadCanvas()
        .registersSettingsOpenAction()
        .presentsSettings(on: session.settingsPresentationRequest)
        .animation(RascMotion.micro(reduceMotion: reduceMotion), value: session.message)
        .overlay(alignment: .bottomLeading) {
            if session.scratchpadGuidance.isActive {
                OnboardingScratchpadOverlay(
                    guidance: session.scratchpadGuidance,
                    editorText: session.text
                )
            } else if let saveErrorMessage = session.saveErrorMessage {
                Text(saveErrorMessage)
                    .foregroundStyle(.red)
                    .padding(12)
            }
        }
    }

    private var showsScratchpadChrome: Bool {
        switch session.surface {
        case .editor, .refining, .refinementPreview, .message:
            true
        case .search, .commandPalette:
            false
        }
    }

    private var showsHomeAffordance: Bool {
        switch session.surface {
        case .editor, .message:
            true
        case .search, .commandPalette, .refining, .refinementPreview:
            false
        }
    }

    private var showsRefineAction: Bool {
        session.surface == .editor
            && session.hasPersistableContent
            && session.canPerformThoughtCompletion
    }

    private var scratchpadChrome: some View {
        HStack(alignment: .center, spacing: RascSurfaceLayout.orbToAccessoryGap) {
            RascOrb(state: resolvedOrbState, size: .inline, decorative: true)
                .frame(width: RascSurfaceLayout.orbSize, height: RascSurfaceLayout.orbSize)

            if let statusText {
                Text(statusText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(RascSurfacePalette.homeSupportingText(for: colorScheme))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            scratchpadTrailingActions
        }
        .padding(.horizontal, RascSurfaceLayout.horizontalInset)
        .padding(.top, RascSurfaceLayout.topInset)
        .padding(.bottom, RascSurfaceLayout.scratchpadChromeBottomPadding)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var scratchpadTrailingActions: some View {
        HStack(spacing: 2) {
            if showsRefineAction {
                ScratchpadChromeButton(
                    title: "Refine",
                    shortcut: "⌘J",
                    action: { session.startRefinement() }
                )
                .keyboardShortcut("j", modifiers: .command)
                .accessibilityLabel("Refine")
                .help("Refine note")
                .transition(.opacity)
            }

            if session.surface == .editor, session.canPerformThoughtCompletion {
                if session.isActiveNoteKept {
                    ScratchpadChromeButton(title: "Unkeep", action: onUnkeep)
                        .accessibilityLabel("Unkeep")
                } else if session.hasPersistableContent {
                    ScratchpadChromeButton(
                        title: "Keep",
                        shortcut: "⇧⌘K",
                        action: onKeep
                    )
                    .keyboardShortcut("k", modifiers: [.command, .shift])
                    .accessibilityLabel("Keep")
                    .help("Keep note")
                }
            }

            if showsHomeAffordance {
                scratchpadHomeButton
            }
        }
        .animation(RascMotion.micro(reduceMotion: reduceMotion), value: showsRefineAction)
    }

    private var scratchpadHomeButton: some View {
        ScratchpadChromeIconButton(
            systemName: "house",
            action: onOpenHome
        )
        .help("Open Home (⌘⌥\\)")
        .accessibilityLabel("Open Rasc Home")
    }

    @ViewBuilder
    private var surfaceBodyContent: some View {
        switch session.surface {
        case .editor, .message:
            editorSurface
        case .search:
            HistorySearchView(session: session)
        case .commandPalette:
            CommandPaletteView(session: session, onExecute: onPaletteCommand)
        case .refining:
            refiningSurface
        case .refinementPreview:
            refinementPreviewSurface
        }
    }

    private var resolvedOrbState: RascOrbState {
        session.surface == .refining ? .refining : .composing
    }

    @ViewBuilder
    private var editorSurface: some View {
        ZStack(alignment: .topLeading) {
            if #available(macOS 15.0, *) {
                SelectableScratchEditor(session: session, onEscape: handleEscape)
            } else {
                TextEditor(text: $session.text)
                    .scrollContentBackground(.hidden)
                    .background(.clear)
                    .font(.system(
                        size: RascSurfaceMetrics.noteFontSize,
                        weight: .regular,
                        design: .monospaced
                    ))
                    .lineSpacing(RascSurfaceMetrics.noteLineSpacing)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, RascSurfaceMetrics.editorHorizontalPadding)
                    .padding(.top, RascSurfaceMetrics.editorTopPadding)
                    .focused($editorIsFocused)
                    .onChange(of: session.focusRequest, initial: true) {
                        requestEditorFocus()
                    }
                    .onChange(of: session.text) {
                        session.scheduleAutosave()
                    }
                    .onExitCommand(perform: handleEscape)
            }

            if session.surface == .editor, session.text.isEmpty {
                ScratchpadEmptyState()
                    .transition(.opacity)
            }
        }
    }

    private var refiningSurface: some View {
        TextEditor(text: .constant(session.text))
            .scrollContentBackground(.hidden)
            .background(.clear)
            .font(.system(
                size: RascSurfaceMetrics.noteFontSize,
                weight: .regular,
                design: .monospaced
            ))
            .lineSpacing(RascSurfaceMetrics.noteLineSpacing)
            .foregroundStyle(.primary.opacity(0.78))
            .padding(.horizontal, RascSurfaceMetrics.editorHorizontalPadding)
            .padding(.top, RascSurfaceMetrics.editorTopPadding)
            .disabled(true)
            .accessibilityLabel("Scratch editor")
            .accessibilityValue("Refining note")
            .onExitCommand(perform: handleEscape)
    }

    private var refinementPreviewSurface: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                Text(session.refinementPreview?.result.text ?? "")
                    .font(.system(
                        size: RascSurfaceMetrics.noteFontSize,
                        weight: .regular,
                        design: .monospaced
                    ))
                    .lineSpacing(RascSurfaceMetrics.noteLineSpacing)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(.horizontal, RascSurfaceLayout.noteTextLeadingInset)
                    .padding(.top, RascSurfaceMetrics.editorTopPadding)
                    .padding(.bottom, 20)
            }
            .accessibilityLabel("Refined preview")

            Rectangle()
                .fill(.primary.opacity(0.07))
                .frame(height: 1)

            HStack(spacing: 12) {
                Button {
                    _ = session.handleEscape()
                } label: {
                    RefinementActionLabel(title: "Cancel", shortcut: "Esc")
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel("Cancel refinement")

                Spacer()

                Button {
                    Task {
                        try? await session.acceptRefinement(undoManager: undoManager)
                    }
                } label: {
                    RefinementActionLabel(title: "Accept", shortcut: "↵", isPrimary: true)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
                .accessibilityLabel("Accept refinement")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Refinement preview")
        .onExitCommand(perform: handleEscape)
    }

    private var statusText: String? {
        switch session.surface {
        case .refining:
            "Refining…"
        case .refinementPreview:
            "Refined"
        case .message:
            session.message == .alreadyUseful ? "Already useful" : session.message?.text
        case .editor, .search, .commandPalette:
            if let transientFeedback = session.transientFeedback {
                transientFeedback
            } else if session.isActiveNoteKept {
                "Kept"
            } else {
                nil
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
            .scrollContentBackground(.hidden)
            .background(.clear)
            .font(.system(
                size: RascSurfaceMetrics.noteFontSize,
                weight: .regular,
                design: .monospaced
            ))
            .lineSpacing(RascSurfaceMetrics.noteLineSpacing)
            .foregroundStyle(.primary)
            .padding(.horizontal, RascSurfaceMetrics.editorHorizontalPadding)
            .padding(.top, RascSurfaceMetrics.editorTopPadding)
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

private struct ScratchpadEmptyState: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: RascSurfaceMetrics.scratchpadEmptySupportingGap) {
            Text("Write something unfinished…")
                .font(.system(size: RascSurfaceMetrics.scratchpadPlaceholderFontSize, weight: .regular))
                .foregroundStyle(scratchpadPlaceholderText)

            Text("Thoughts, tasks, messages, ideas. Anything goes.")
                .font(.system(size: 13.5, weight: .regular))
                .foregroundStyle(scratchpadSupportingText)
        }
        .padding(.leading, RascSurfaceMetrics.placeholderLeadingInset)
        .padding(.top, RascSurfaceMetrics.placeholderTopInset)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var scratchpadPlaceholderText: Color {
        colorScheme == .dark
            ? Color.secondary.opacity(0.76)
            : Color.primary.opacity(0.38)
    }

    private var scratchpadSupportingText: Color {
        RascSurfacePalette.homeSupportingText(for: colorScheme)
            .opacity(colorScheme == .dark ? 0.86 : 0.88)
    }
}

private struct ScratchpadChromeIconButton: View {
    let systemName: String
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.tertiary)
                .frame(width: 26, height: 26)
                .background {
                    if isHovered {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(RascSurfacePalette.subtleFill(for: colorScheme))
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

private struct ScratchpadChromeButton: View {
    let title: String
    var shortcut: String?
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let shortcut {
                    Text(shortcut)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }

                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background {
                if isHovered {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(RascSurfacePalette.subtleFill(for: colorScheme))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

private struct RefinementActionLabel: View {
    let title: String
    let shortcut: String
    var isPrimary = false

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 7) {
            Text(shortcut)
                .font(.caption2.monospaced().weight(.medium))
                .foregroundStyle(
                    isPrimary
                        ? RascSurfacePalette.actionAccent(for: colorScheme)
                        : Color.secondary
                )

            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(
                    isPrimary
                        ? RascSurfacePalette.actionAccent(for: colorScheme)
                        : Color.secondary
                )
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background {
            if isPrimary {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(RascSurfacePalette.actionAccent(for: colorScheme).opacity(0.10))
            }
        }
        .overlay {
            if isPrimary {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        RascSurfacePalette.actionAccent(for: colorScheme).opacity(0.22),
                        lineWidth: 1
                    )
            }
        }
        .contentShape(Rectangle())
    }
}

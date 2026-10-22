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

    enum CompletionFailure: Equatable {
        case keep, unkeep, discard, copy, share
        var text: String {
            switch self {
            case .keep: "Couldn't keep this thought. Your text is still here."
            case .unkeep: "Couldn't unkeep this thought. Try again."
            case .discard: "Couldn't discard this thought. It is still available."
            case .copy: "Couldn't prepare this thought for copying. Try again."
            case .share: "Couldn't prepare this thought for sharing. Try again."
            }
        }
        var command: PaletteCommand {
            switch self {
            case .keep: .keep
            case .unkeep: .unkeep
            case .discard: .discardNote
            case .copy: .copyNote
            case .share: .shareNote
            }
        }
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
    private(set) var hasMoreSearchResults = false
    private(set) var lastDiscard: NoteDiscardReceipt?
    private var discardUndoRegistrations: [UUID: DiscardUndoRegistration] = [:]
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
    private(set) var commandPaletteQuery = ""
    private(set) var commandPaletteKeyFocusRequest = 0
    private(set) var saveErrorMessage: String?
    private(set) var completionFailure: CompletionFailure?
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

    func reportCompletionFailure(_ failure: CompletionFailure) { completionFailure = failure }
    func dismissCompletionFailure() { completionFailure = nil }

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

    func discardActiveNote(undoManager: UndoManager? = nil) async throws {
        guard canPerformThoughtCompletion else { return }
        try await prepareForThoughtCompletionAction()

        if let noteID {
            lastDiscard = try await repository.delete(id: noteID)
            if let receipt = lastDiscard, let undoManager {
                let registration = DiscardUndoRegistration(manager: undoManager) { [weak self] in
                    Task { await self?.undoDiscard(receipt) }
                }
                discardUndoRegistrations[receipt.id] = registration
                registration.register()
            }
        }
        clearActiveScratchSession()
        showTransientFeedback("Discarded")
    }

    func undoDiscard(_ receipt: NoteDiscardReceipt? = nil) async {
        guard let receipt = receipt ?? lastDiscard else { return }
        do {
            let restored = try await repository.restoreDiscard(receipt)
            if noteID == nil, !hasPersistableContent {
                noteID = restored.id
                text = restored.content
                activeNoteKeptAt = restored.keptAt
                activeNoteStore.noteID = restored.id
                requestEditorFocus()
            }
            discardUndoRegistrations.removeValue(forKey: receipt.id)?.invalidate()
            if lastDiscard == receipt { lastDiscard = nil }
            saveErrorMessage = nil
            showTransientFeedback("Restored. Available in Home.")
        } catch {
            saveErrorMessage = "Couldn't restore this thought. Try Undo again."
        }
    }

    func retrySave() async {
        do { try await flush() }
        catch { saveErrorMessage = "Couldn't save locally. Your text is still here. Try again." }
    }

    func dismissRefinementMessage() {
        clearMessage(returnToEditor: true)
        requestEditorFocus()
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
        requestEditorFocus()
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
                let results = try await repository.search(query, limit: 13)
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
        let results = try await repository.search(query, limit: 13)
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
        commandPaletteQuery = ""
        refreshPaletteCommands()
        selectedCommandIndex = 0
        requestCommandPaletteKeyFocus()
    }

    func insertCommandPaletteText(_ text: String) {
        guard surface == .commandPalette, !text.isEmpty else { return }
        commandPaletteQuery += text
        refreshPaletteCommands()
        selectedCommandIndex = 0
    }

    func deleteCommandPaletteText() {
        guard surface == .commandPalette, !commandPaletteQuery.isEmpty else { return }
        commandPaletteQuery.removeLast()
        refreshPaletteCommands()
        selectedCommandIndex = 0
    }

    func refreshCommandsForShortcutChange() {
        guard surface == .commandPalette else { return }
        refreshPaletteCommands()
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
        guard message.isTransient else { messageTask = nil; return }
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
        hasMoreSearchResults = results.count > 12
        searchResults = Array(results.prefix(12))
        selectedSearchIndex = 0
        searchErrorMessage = nil
    }

    private func resetSearchState() {
        searchTask?.cancel()
        searchTask = nil
        surface = .editor
        searchQuery = ""
        searchResults = []
        hasMoreSearchResults = false
        selectedSearchIndex = 0
        searchErrorMessage = nil
    }

    private func resetCommandPaletteState() {
        surface = .editor
        commandPaletteQuery = ""
        refreshPaletteCommands()
        selectedCommandIndex = 0
    }

    private func refreshPaletteCommands() {
        filteredCommands = PaletteCommand.filtered(
            by: commandPaletteQuery,
            in: paletteCommandsForCurrentState()
        )
        if !filteredCommands.indices.contains(selectedCommandIndex) {
            selectedCommandIndex = 0
        }
    }

    private func paletteCommandsForCurrentState() -> [PaletteCommand] {
        PaletteCommand.availableCommands(
            isKept: isActiveNoteKept,
            hasPersistableContent: hasPersistableContent,
            canPerformCompletion: canPerformThoughtCompletion
        )
    }

    private func prepareForThoughtCompletionAction() async throws {
        completionFailure = nil
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


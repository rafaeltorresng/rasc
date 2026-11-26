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
    private(set) var lastDiscardBatch: [NoteDiscardReceipt] = []
    private(set) var selectedNoteIDs: Set<UUID> = []
    private(set) var selectionAnchorID: UUID?
    private(set) var isSelectionMode = false
    private var discardUndoRegistrations: [UUID: DiscardUndoRegistration] = [:]
    private(set) var hasMoreSearchResults = false

    private(set) var showsHistoryHint = false

    private let repository: NoteRepository
    private let prepareForDuplicate: @MainActor (UUID) async throws -> Void
    private let discoveryStore: OnboardingStore
    private let calendar: Calendar
    private var reloadTask: Task<Void, Never>?
    private var now: Date

    init(
        repository: NoteRepository,
        prepareForDuplicate: @escaping @MainActor (UUID) async throws -> Void = { _ in },
        discoveryStore: OnboardingStore = OnboardingStore(),
        calendar: Calendar = .current,
        now: Date = Date()
    ) {
        self.repository = repository
        self.prepareForDuplicate = prepareForDuplicate
        self.discoveryStore = discoveryStore
        self.calendar = calendar
        self.now = now
    }

    var isSearching: Bool {
        !normalizedSearchQuery.isEmpty
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

    var noteCount: Int {
        browseGroups.reduce(0) { $0 + $1.notes.count }
    }

    func recordHomeVisit() {
        discoveryStore.recordHomeVisit()
        refreshHistoryHint()
    }

    func dismissHistoryHint() {
        discoveryStore.dismissHistoryHint()
        showsHistoryHint = false
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

    // MARK: Multi-selection

    struct BatchCopyResult: Equatable {
        let text: String
        let noteCount: Int
        let includesImages: Bool
        let singleDocument: NoteDocument?
    }

    var selectedCount: Int { selectedNoteIDs.count }

    /// Selected notes in visible order.
    var selectedNotes: [Note] { displayedNotes.filter { selectedNoteIDs.contains($0.id) } }

    var hasUndoableDiscard: Bool { lastDiscard != nil || !lastDiscardBatch.isEmpty }

    /// Toggle a note in the multi-selection (Command-click). Does not open it.
    func toggleSelection(_ noteID: UUID) {
        if selectedNoteIDs.contains(noteID) { selectedNoteIDs.remove(noteID) }
        else { selectedNoteIDs.insert(noteID) }
        selectedNoteID = noteID
        selectionAnchorID = noteID
        if !selectedNoteIDs.isEmpty { isSelectionMode = true }
    }

    /// Range selection from the anchor to `noteID` within visible order (Shift-click).
    func extendSelectionTo(_ noteID: UUID) {
        let notes = displayedNotes
        let anchor = selectionAnchorID ?? selectedNoteID ?? noteID
        if selectionAnchorID == nil { selectionAnchorID = anchor }
        guard let start = notes.firstIndex(where: { $0.id == anchor }),
              let end = notes.firstIndex(where: { $0.id == noteID }) else {
            selectedNoteIDs.insert(noteID)
            selectedNoteID = noteID
            isSelectionMode = true
            return
        }
        let range = notes[min(start, end)...max(start, end)]
        selectedNoteIDs.formUnion(range.map(\.id))
        selectedNoteID = noteID
        isSelectionMode = true
    }

    /// Keyboard range selection (Shift+Arrow) anchored at the current anchor or focus.
    func extendSelection(_ direction: NavigationDirection, columns: Int) {
        let anchor = selectionAnchorID ?? selectedNoteID ?? displayedNotes.first?.id
        if selectionAnchorID == nil { selectionAnchorID = anchor }
        if let anchor { selectedNoteIDs.insert(anchor) }
        moveSelection(direction, columns: columns)
        guard let target = selectedNoteID else { return }
        extendSelectionTo(target)
    }

    /// Select every visible/filtered note (Command-A).
    func selectAllVisible() {
        let notes = displayedNotes
        guard !notes.isEmpty else { return }
        selectedNoteIDs = Set(notes.map(\.id))
        selectionAnchorID = notes.first?.id
        if selectedNoteID == nil { selectedNoteID = notes.first?.id }
        isSelectionMode = true
    }

    /// Clear multi-selection and leave selection mode (Esc / explicit clear).
    func clearSelection() {
        selectedNoteIDs = []
        selectionAnchorID = nil
        isSelectionMode = false
    }

    func setSelectionMode(_ mode: Bool) {
        if mode {
            isSelectionMode = true
            if selectedNoteIDs.isEmpty, let id = selectedNoteID { selectedNoteIDs.insert(id); selectionAnchorID = id }
        } else {
            clearSelection()
        }
    }

    func toggleSelectionMode() { setSelectionMode(!isSelectionMode) }

    func batchCopyPayload() async throws -> BatchCopyResult {
        let notes = selectedNotes
        guard !notes.isEmpty else {
            return BatchCopyResult(text: "", noteCount: 0, includesImages: false, singleDocument: nil)
        }
        var documents: [NoteDocument] = []
        for note in notes {
            let document = try await repository.fetchDocument(id: note.id)
                ?? NoteDocument(parts: [.text(note.content)])
            documents.append(document)
        }
        let includesImages = documents.contains(where: \.hasImages)
        let parts = documents
            .map(\.text)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let text = parts.joined(separator: "\n\n---\n\n")
        return BatchCopyResult(
            text: text,
            noteCount: documents.count,
            includesImages: includesImages,
            singleDocument: documents.count == 1 ? documents[0] : nil
        )
    }

    /// Batch copy: selected note text in visible order, separated by a rule.
    func copySelectedText() async throws -> String {
        try await batchCopyPayload().text
    }

    /// Discard every selected note in a single transaction, preserving Undo.
    @discardableResult
    func discardSelected(undoManager: UndoManager? = nil) async throws -> [NoteDiscardReceipt] {
        let ids = selectedNoteIDs
        guard !ids.isEmpty else { return [] }
        let receipts = try await repository.delete(ids: ids)
        guard !receipts.isEmpty else {
            clearSelection()
            await reloadImmediately()
            return []
        }
        lastDiscardBatch = receipts
        lastDiscard = nil
        if let undoManager {
            let actionName = receipts.count == 1 ? "Discard Thought" : "Discard \(receipts.count) Thoughts"
            let registration = DiscardUndoRegistration(manager: undoManager, actionName: actionName) { [weak self] in
                Task { await self?.undoDiscardBatch(receipts) }
            }
            for receipt in receipts { discardUndoRegistrations[receipt.id] = registration }
            registration.register()
        }
        clearSelection()
        await reloadImmediately()
        return receipts
    }

    func undoDiscardBatch(_ receipts: [NoteDiscardReceipt]? = nil) async {
        let batch = receipts ?? lastDiscardBatch
        guard !batch.isEmpty else { return }
        do {
            let restored = try await repository.restoreDiscards(batch)
            for receipt in batch { discardUndoRegistrations.removeValue(forKey: receipt.id)?.invalidate() }
            if lastDiscardBatch == batch { lastDiscardBatch = [] }
            actionErrorMessage = nil
            if restored.contains(where: \.isKept) { showsAllKept = true }
            selectedNoteIDs = Set(restored.map(\.id))
            selectedNoteID = restored.first?.id
            selectionAnchorID = restored.first?.id
            isSelectionMode = !restored.isEmpty
            await reloadImmediately()
        } catch {
            actionErrorMessage = "Couldn't restore these thoughts. Try Undo again."
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
        if let receipt {
            lastDiscard = receipt
            lastDiscardBatch = []
            selectedNoteIDs.remove(id)
            if selectionAnchorID == id { selectionAnchorID = nil }
            if let undoManager {
                let registration = DiscardUndoRegistration(manager: undoManager) { [weak self] in
                    Task { await self?.undoDiscard(receipt) }
                }
                discardUndoRegistrations[receipt.id] = registration
                registration.register()
            }
        }
        await reloadImmediately()
    }

    func undoDiscard(_ receipt: NoteDiscardReceipt? = nil) async {
        if receipt == nil, !lastDiscardBatch.isEmpty { await undoDiscardBatch(); return }
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

    func documentForCopy(id: UUID) async throws -> NoteDocument {
        guard let document = try await repository.fetchDocument(id: id) else {
            throw NoteRepository.PersistenceError.staleContent
        }
        return document
    }

    func duplicateNote(id: UUID) async throws -> Note {
        try await prepareForDuplicate(id)
        let duplicate = try await repository.duplicate(id: id)
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
                refreshHistoryHint()
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

    private func refreshHistoryHint() {
        showsHistoryHint = FeatureDiscoveryPolicy.shouldShowHistoryHint(
            noteCount: noteCount,
            homeVisitCount: discoveryStore.homeVisitCount,
            dismissed: discoveryStore.historyHintDismissed
        )
    }

    private func reconcileSelection() {
        let notes = displayedNotes
        guard !notes.isEmpty else {
            selectedNoteID = nil
            selectedNoteIDs = []
            selectionAnchorID = nil
            isSelectionMode = false
            return
        }

        // Multi-selection follows reloads; drop notes that are no longer visible.
        let visible = Set(notes.map(\.id))
        let pruned = selectedNoteIDs.intersection(visible)
        if pruned != selectedNoteIDs {
            selectedNoteIDs = pruned
            if pruned.isEmpty { selectionAnchorID = nil }
        }
        if let anchor = selectionAnchorID, !visible.contains(anchor) {
            selectionAnchorID = pruned.isEmpty ? nil : notes.first { pruned.contains($0.id) }?.id
        }

        if let selectedNoteID, notes.contains(where: { $0.id == selectedNoteID }) {
            return
        }

        selectedNoteID = notes.first?.id
    }
}

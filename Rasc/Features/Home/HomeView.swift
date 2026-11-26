import AppKit
import SwiftUI

private enum HomeLayout {
    static let contentMaxWidth: CGFloat = 1_200
    static let readingColumnMaxWidth: CGFloat = 760
    static let horizontalPadding: CGFloat = 32
    static let actionZoneTopPadding: CGFloat = 18
    static let actionZoneBottomPadding: CGFloat = 14
    static let contentTopPadding: CGFloat = 12
    static let contentBottomPadding: CGFloat = 44
    static let temporalGroupSpacing: CGFloat = 24
    static let temporalLabelSpacing: CGFloat = 8
    static let keptToTemporalExtraSpacing: CGFloat = 4
    static let searchMinWidth: CGFloat = 200
    static let searchMaxWidth: CGFloat = 400
    static let identitySpacing: CGFloat = 9
    static let actionZoneSpacing: CGFloat = 14
    static let quietStateMinHeight: CGFloat = 240
    static let emptyStateMaxWidth: CGFloat = 360
    static let emptyStateSpacing: CGFloat = 14
    static let emptyStateCTACornerRadius: CGFloat = 10
    static let gridItemMinWidth: CGFloat = 300
    static let gridSpacing: CGFloat = 12
    static let gridItemCornerRadius: CGFloat = 10
    static let cardExcerptLineLimit = 4
    static let cardTitleFontSize: CGFloat = 15
    static let cardExcerptFontSize: CGFloat = 12.5
}

struct HomeView: View {
    @Bindable var session: HomeSession
    let onOpenNote: (UUID) -> Void
    let onNewScratch: () -> Void
    let onNoteDiscarded: (UUID) -> Void
    let onNoteUnkept: (UUID) -> Void
    let onExportThought: (UUID) -> Void
    /// Batch export of an explicit selection.
    var onExportSelected: (Set<UUID>) -> Void = { _ in }
    @Environment(\.rascPalette) private var palette
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.undoManager) private var undoManager
    @ObservedObject private var internalShortcuts = InternalShortcutStore.shared
    @FocusState private var searchIsFocused: Bool
    @FocusState private var listIsFocused: Bool
    private var activeGridColumns: Int {
        viewMode == .cards ? max(1, gridColumns) : 1
    }

    /// Fixed column set derived solely from `gridColumns`, so keyboard navigation
    /// and rendering can never disagree — one formula, one source of truth. The
    /// flexible cells fill the width the window gives the grid.
    private var cardGridItems: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: HomeLayout.gridSpacing),
            count: activeGridColumns
        )
    }
    @State private var retryAction: (() -> Void)?
    @State private var copyFeedback: String?
    @State private var copyFeedbackTask: Task<Void, Never>?
    @State private var viewMode: HomeViewMode = HomeViewModeStore().load()
    /// Column count for cards mode, measured from the content width (see the
    /// zero-height GeometryReader in the content column). Also drives keyboard
    /// navigation, so grid rendering and arrow keys always agree.
    @State private var gridColumns: Int = 3

    var body: some View {
        VStack(spacing: 0) {
            homeContentColumn {
                actionZone
                    .padding(.top, HomeLayout.actionZoneTopPadding)
                    .padding(.bottom, HomeLayout.actionZoneBottomPadding)
            }

            if session.showsEmptyHome {
                homeContentColumn {
                    emptyHomeState
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { scrollProxy in
                    ScrollView {
                        homeContentColumn {
                            VStack(spacing: 0) {
                                GeometryReader { proxy in
                                    Color.clear
                                        .onChange(of: proxy.size.width, initial: true) { _, width in
                                            let columns = max(
                                                1,
                                                Int((width + HomeLayout.gridSpacing) / (HomeLayout.gridItemMinWidth + HomeLayout.gridSpacing))
                                            )
                                            if columns != gridColumns {
                                                gridColumns = columns
                                            }
                                        }
                                }
                                .frame(height: 0)

                                if session.showsHistoryHint, !session.isSearching {
                                    historyHint
                                        .padding(.top, HomeLayout.contentTopPadding)
                                        .transition(
                                            RascMotion.headerAccessoryTransition(reduceMotion: reduceMotion)
                                        )
                                }

                                contentBody
                                    .frame(
                                        maxWidth: viewMode == .cards ? HomeLayout.contentMaxWidth : HomeLayout.readingColumnMaxWidth,
                                        alignment: .leading
                                    )
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.top, HomeLayout.contentTopPadding)
                                    .padding(.bottom, HomeLayout.contentBottomPadding)
                            }
                        }
                    }
                    .focusable()
                    // Clicking empty space focuses the scroll view; without this,
                    // its focus ring draws two stray accent-colored lines across the window.
                    .focusEffectDisabled()
                    .focused($listIsFocused)
                    .onChange(of: session.selectedNoteID) { _, noteID in
                        guard let noteID else { return }
                        scrollProxy.scrollTo(noteID)
                    }
                }
            }
            if session.selectedCount > 0 {
                homeContentColumn {
                    HomeBatchActionsBar(
                        session: session,
                        undoManager: undoManager,
                        onNoteDiscarded: onNoteDiscarded,
                        onExportSelected: { ids in onExportSelected(ids) },
                        onCopy: { message in
                            session.actionErrorMessage = nil
                            retryAction = nil
                            copyFeedback = message
                            copyFeedbackTask?.cancel()
                            copyFeedbackTask = Task { @MainActor in
                                try? await Task.sleep(for: .seconds(3))
                                guard !Task.isCancelled else { return }
                                copyFeedback = nil
                            }
                        },
                        onDiscardSucceeded: {
                            session.actionErrorMessage = nil
                            retryAction = nil
                        },
                        onError: { message in session.actionErrorMessage = message }
                    )
                }
                .padding(.bottom, 8)
            }
            if let error = session.actionErrorMessage {
                HStack(spacing: 12) {
                    Text(error).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    if let retryAction { Button("Retry", action: retryAction) }
                    else if session.hasUndoableDiscard { Button("Undo") { Task { await session.undoDiscard() } } }
                    Button("Dismiss") { session.actionErrorMessage = nil; retryAction = nil }
                }
                .font(.callout)
                .padding(.horizontal, HomeLayout.horizontalPadding)
                .padding(.vertical, 12)
                .accessibilityElement(children: .contain)
            } else if session.hasUndoableDiscard {
                HStack {
                    Text(session.lastDiscardBatch.count > 1 ? "\(session.lastDiscardBatch.count) thoughts discarded." : "Thought discarded.")
                        .foregroundStyle(palette.secondaryText(for: colorScheme))
                    Spacer()
                    Button("Undo") { Task { await session.undoDiscard() } }
                }
                .font(.callout)
                .padding(.horizontal, HomeLayout.horizontalPadding)
                .padding(.vertical, 12)
            } else if let copyFeedback {
                Text(copyFeedback)
                    .font(.callout)
                    .foregroundStyle(palette.secondaryText(for: colorScheme))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, HomeLayout.horizontalPadding)
                    .padding(.vertical, 12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .rascWindowSurface()
        .onAppear { DispatchQueue.main.async { searchIsFocused = true } }
        .onChange(of: viewMode) { _, mode in
            HomeViewModeStore().save(mode)
        }
        .animation(RascMotion.surface(reduceMotion: reduceMotion), value: session.showsHistoryHint)
        .onChange(of: session.actionErrorMessage) { _, message in
            if let message { RascAccessibility.announce(message) }
        }
        .onChange(of: copyFeedback) { _, message in
            if let message { RascAccessibility.announce(message) }
        }
        .onChange(of: session.selectedCount) { oldCount, count in
            if count > 0 {
                RascAccessibility.announce("\(count) selected")
            } else if oldCount > 0 && !session.hasUndoableDiscard {
                RascAccessibility.announce("Selection cleared")
            }
        }
        .onChange(of: session.lastDiscard) { _, receipt in
            if receipt != nil { RascAccessibility.announce("Thought discarded. Undo is available.") }
        }
        .onChange(of: session.lastDiscardBatch) { _, batch in
            guard !batch.isEmpty else { return }
            let message = batch.count == 1
                ? "Thought discarded. Undo is available."
                : "\(batch.count) thoughts discarded. Undo is available."
            RascAccessibility.announce(message)
        }
        .onKeyPress(keys: [.upArrow, .downArrow, .leftArrow, .rightArrow], phases: .down) { press in
            guard !searchIsFocused else { return .ignored }
            let direction: HomeSession.NavigationDirection? = switch press.key {
            case .upArrow: .up
            case .downArrow: .down
            case .leftArrow: .left
            case .rightArrow: .right
            default: nil
            }
            guard let direction else { return .ignored }
            listIsFocused = true
            if press.modifiers.contains(.shift) {
                session.extendSelection(direction, columns: activeGridColumns)
            } else {
                session.moveSelection(direction, columns: activeGridColumns)
            }
            return .handled
        }
        .onKeyPress(.space, phases: .down) { press in
            guard !searchIsFocused,
                  listIsFocused,
                  session.isSelectionMode || session.selectedCount > 0,
                  press.modifiers.isEmpty,
                  let id = session.selectedNoteID else { return .ignored }
            session.toggleSelection(id)
            return .handled
        }
        .onKeyPress(.return) {
            guard !searchIsFocused, listIsFocused else { return .ignored }
            openSelectedNote()
            return .handled
        }
        .onKeyPress(KeyEquivalent("a"), phases: .down) { press in
            guard !searchIsFocused, press.modifiers == .command else { return .ignored }
            listIsFocused = true
            session.selectAllVisible()
            return .handled
        }
        .onExitCommand {
            guard session.selectedCount > 0 || session.isSelectionMode else { return }
            session.clearSelection()
        }
    }

    private func homeContentColumn<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: HomeLayout.contentMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, HomeLayout.horizontalPadding)
    }

    private var actionZone: some View {
        HStack(alignment: .center, spacing: HomeLayout.actionZoneSpacing) {
            HStack(spacing: HomeLayout.identitySpacing) {
                RascLogo(size: RascLogo.compactSize)
                    .frame(width: RascLogo.compactSize, height: RascLogo.compactSize)

                Text("Rasc")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary.opacity(0.92))
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Rasc")

            ThoughtSearchField(text: $session.searchQuery, isFocused: $searchIsFocused)
                .onSubmit { searchIsFocused = false; listIsFocused = true }
                .onKeyPress(.downArrow) {
                    searchIsFocused = false
                    listIsFocused = true
                    return .handled
                }
                .frame(minWidth: HomeLayout.searchMinWidth, maxWidth: HomeLayout.searchMaxWidth)

            Spacer(minLength: 12)

            HomeViewModeToggle(mode: $viewMode)

            if session.hasNotes {
                HomeSelectionToggle(isOn: session.isSelectionMode) { session.toggleSelectionMode() }
            }

            HomeNewScratchButton(style: .header, action: onNewScratch)

            RascSettingsLink {
                Image(systemName: "gearshape")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(palette.secondaryText(for: colorScheme))
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
            .help("Settings")
        }
    }

    private var historyHint: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Text("Search thoughts in Rasc")
                ShortcutKeycapView(
                    label: internalShortcuts.displayString(for: .search),
                    style: .compact
                )
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                "Search thoughts in Rasc with \(internalShortcuts.displayString(for: .search))"
            )

            Spacer(minLength: 8)

            Button {
                session.dismissHistoryHint()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(palette.secondaryText(for: colorScheme))
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle().inset(by: -3))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss search tip")
            .help("Dismiss")
        }
        .font(.callout)
        .foregroundStyle(palette.secondaryText(for: colorScheme))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(palette.subtleFill(for: colorScheme))
        }
    }

    @ViewBuilder
    private var contentBody: some View {
        if let loadErrorMessage = session.loadErrorMessage {
            quietStateLabel(loadErrorMessage)
        } else if session.showsNoSearchResults {
            quietStateLabel("No thoughts found.")
        } else if session.isSearching {
            searchResultsList
        } else {
            chronologicalList
        }
    }

    private var emptyHomeState: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            VStack(spacing: HomeLayout.emptyStateSpacing) {
                Text("Your thoughts")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.homeSectionLabel(for: colorScheme))
                    .accessibilityAddTraits(.isHeader)

                VStack(spacing: 8) {
                    Text("Nothing here yet.")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.primary.opacity(0.9))

                    Text("Your thoughts appear here as you write.")
                        .font(.system(size: 13))
                        .foregroundStyle(palette.homeSupportingText(for: colorScheme))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HomeNewScratchButton(style: .prominent, action: onNewScratch)
                    .keyboardShortcut(.defaultAction)
                    .padding(.top, 6)
            }
            .frame(maxWidth: HomeLayout.emptyStateMaxWidth)
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(.bottom, HomeLayout.actionZoneTopPadding)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Nothing here yet. Your thoughts appear here as you write.")
    }

    private var chronologicalList: some View {
        VStack(alignment: .leading, spacing: HomeLayout.temporalGroupSpacing) {
            ForEach(Array(session.visibleBrowseGroups.enumerated()), id: \.element.id) { index, group in
                VStack(alignment: .leading, spacing: HomeLayout.temporalLabelSpacing) {
                    sectionTitle(for: group)

                    notesBody(
                        for: group.notes,
                        showsKeptIndicator: !isKeptSection(group)
                    )
                    if isKeptSection(group), session.keptCount > HomeLifecycleGrouping.keptSectionLimit {
                        Button {
                            session.toggleKeptVisibility()
                        } label: {
                            if session.showsAllKept {
                                Text("Show fewer")
                            } else {
                                Text("Show all \(session.keptCount) kept thoughts")
                                    .monospacedDigit()
                            }
                        }
                        .buttonStyle(.link)
                        .padding(.top, 4)
                    }
                }
                .padding(.top, sectionTopInset(for: group, at: index))
            }
        }
        .animation(RascMotion.bodyContentAnimation(reduceMotion: reduceMotion), value: session.browseGroups.map(\.id))
    }

    private var searchResultsList: some View {
        VStack(alignment: .leading, spacing: 12) {
            notesBody(for: session.searchResults)
            if session.hasMoreSearchResults {
                Text("Showing the first 500 matches. Narrow your search to find more.")
                    .font(.callout)
                    .foregroundStyle(palette.secondaryText(for: colorScheme))
            }
        }
            .animation(RascMotion.bodyContentAnimation(reduceMotion: reduceMotion), value: session.searchResults.map(\.id))
    }

    @ViewBuilder
    private func notesBody(
        for notes: [Note],
        showsKeptIndicator: Bool = true
    ) -> some View {
        if viewMode == .cards {
            noteCardGrid(for: notes, showsKeptIndicator: showsKeptIndicator)
        } else {
            noteList(for: notes, showsKeptIndicator: showsKeptIndicator)
        }
    }

    private func noteCardGrid(
        for notes: [Note],
        showsKeptIndicator: Bool = true
    ) -> some View {
        let showSelectionIndicators = session.isSelectionMode || session.selectedCount > 0
        return LazyVGrid(
            columns: cardGridItems,
            alignment: .leading,
            spacing: HomeLayout.gridSpacing
        ) {
            ForEach(Array(notes.enumerated()), id: \.element.id) { _, note in
                let multiSelected = session.selectedNoteIDs.contains(note.id)
                let keyboardFocused = session.selectedNoteID == note.id
                HomeNoteCardView(
                    note: note,
                    isSelected: showSelectionIndicators ? multiSelected : keyboardFocused,
                    isKeyboardFocused: keyboardFocused,
                    isSelectionMode: session.isSelectionMode,
                    showsSelectionIndicator: showSelectionIndicators,
                    showsKeptIndicator: showsKeptIndicator,
                    timestamp: session.formattedTimestamp(for: note),
                    searchQuery: session.searchQuery,
                    onOpen: { onOpenNote(note.id) },
                    onSelect: { session.selectNote(note.id) },
                    onToggleSelection: { session.toggleSelection(note.id) },
                    onExtendSelection: { session.extendSelectionTo(note.id) },
                    onCopy: { copyNote(note.id) },
                    onExport: { onExportThought(note.id) },
                    onDuplicate: { duplicateNote(note.id) },
                    onUnkeep: { unkeepNote(note.id) },
                    onDiscard: { discardNote(note.id) }
                )
                .id(note.id)
            }
        }
    }

    private func noteList(
        for notes: [Note],
        showsKeptIndicator: Bool = true
    ) -> some View {
        let showSelectionIndicators = session.isSelectionMode || session.selectedCount > 0
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(notes.enumerated()), id: \.element.id) { index, note in
                let multiSelected = session.selectedNoteIDs.contains(note.id)
                let keyboardFocused = session.selectedNoteID == note.id
                HomeNoteRowView(
                    note: note,
                    isSelected: showSelectionIndicators ? multiSelected : keyboardFocused,
                    isKeyboardFocused: keyboardFocused,
                    isSelectionMode: session.isSelectionMode,
                    showsSelectionIndicator: showSelectionIndicators,
                    showsKeptIndicator: showsKeptIndicator,
                    timestamp: session.formattedTimestamp(for: note),
                    searchQuery: session.searchQuery,
                    onOpen: { onOpenNote(note.id) },
                    onSelect: { session.selectNote(note.id) },
                    onToggleSelection: { session.toggleSelection(note.id) },
                    onExtendSelection: { session.extendSelectionTo(note.id) },
                    onCopy: { copyNote(note.id) },
                    onExport: { onExportThought(note.id) },
                    onDuplicate: { duplicateNote(note.id) },
                    onUnkeep: { unkeepNote(note.id) },
                    onDiscard: { discardNote(note.id) }
                )
                .id(note.id)

                if index < notes.count - 1 {
                    Rectangle()
                        .fill(.primary.opacity(0.055))
                        .frame(height: 1)
                }
            }
        }
    }

    private func quietStateLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 15))
            .foregroundStyle(palette.secondaryText(for: colorScheme))
            .frame(
                maxWidth: .infinity,
                minHeight: HomeLayout.quietStateMinHeight,
                alignment: .center
            )
            .accessibilityLabel(text)
    }

    private func openSelectedNote() {
        guard let note = session.selectedNote() else { return }
        onOpenNote(note.id)
    }

    private func copyNote(_ noteID: UUID) {
        Task {
            do {
                let document = try await session.documentForCopy(id: noteID)
                try await NoteHandoff.copy(document)
                session.actionErrorMessage = nil
                retryAction = nil
                if document.hasImages {
                    let imageCount = document.parts.filter { if case .image = $0 { true } else { false } }.count
                    let imageOnly = imageCount == 1 && document.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    copyFeedback = imageOnly ? "Image copied." : "Copied with images. Paste into a rich-text app."
                    copyFeedbackTask?.cancel()
                    copyFeedbackTask = Task { @MainActor in
                        try? await Task.sleep(for: .seconds(3))
                        guard !Task.isCancelled else { return }
                        copyFeedback = nil
                    }
                }
            } catch {
                session.actionErrorMessage = "Couldn't copy this thought. Try again."
                retryAction = { copyNote(noteID) }
            }
        }
    }

    private func duplicateNote(_ noteID: UUID) {
        Task {
            do {
                _ = try await session.duplicateNote(id: noteID)
                session.actionErrorMessage = nil
                retryAction = nil
            } catch {
                session.actionErrorMessage = "Couldn't duplicate this thought. The original is safe."
                retryAction = { duplicateNote(noteID) }
            }
        }
    }

    private func unkeepNote(_ noteID: UUID) {
        Task {
            do {
                try await session.unkeepNote(id: noteID)
                onNoteUnkept(noteID)
                session.actionErrorMessage = nil
                retryAction = nil
            } catch {
                session.actionErrorMessage = "Couldn't unkeep this thought. Try again."
                retryAction = { unkeepNote(noteID) }
            }
        }
    }

    private func discardNote(_ noteID: UUID) {
        Task {
            do {
                try await session.discardNote(id: noteID, undoManager: undoManager)
                onNoteDiscarded(noteID)
                session.actionErrorMessage = nil
                retryAction = nil
            } catch {
                session.actionErrorMessage = "Couldn't discard this thought. It is still available."
                retryAction = { discardNote(noteID) }
            }
        }
    }

    private func isKeptSection(_ group: HomeBrowseGroup) -> Bool {
        if case .kept = group.kind {
            return true
        }
        return false
    }

    private func sectionTitle(for group: HomeBrowseGroup) -> some View {
        HStack(spacing: 8) {
            Text(group.sectionTitle.uppercased())
                .font(.system(size: 10.5, weight: .semibold))
                .tracking(0.8)

            if case .kept = group.kind {
                Text("\(session.keptCount)")
                    .font(.system(size: 10.5, weight: .semibold))
                    .monospacedDigit()
            }
        }
        .foregroundStyle(palette.homeSectionLabel(for: colorScheme))
        .accessibilityAddTraits(.isHeader)
    }

    private func sectionTopInset(for group: HomeBrowseGroup, at index: Int) -> CGFloat {
        guard index > 0 else { return 0 }
        let previous = session.browseGroups[index - 1]
        if isKeptSection(previous), !isKeptSection(group) {
            return HomeLayout.keptToTemporalExtraSpacing
        }
        return 0
    }
}

struct ThoughtSearchField: View {
    @Binding var text: String
    let isFocused: FocusState<Bool>.Binding

    @Environment(\.rascPalette) private var palette
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.noteTextSize) private var noteTextSize

    var body: some View {
        RascTransientInputShell(isFocused: isFocused.wrappedValue) {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(palette.metadataText(for: colorScheme))

                TextField(
                    "",
                    text: $text,
                    prompt: Text("Search thoughts…")
                        .foregroundStyle(palette.metadataText(for: colorScheme))
                )
                .textFieldStyle(.plain)
                .font(.system(size: noteTextSize.points(13.5)))
                .focused(isFocused)

                if !text.isEmpty {
                    Button {
                        text = ""
                        isFocused.wrappedValue = true
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(palette.secondaryText(for: colorScheme))
                            .frame(width: 26, height: 26)
                            .contentShape(Rectangle().inset(by: -3))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                    .help("Clear search")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Search thoughts")
    }
}

private struct HomeNoteRowView: View {
    let note: Note
    let isSelected: Bool
    var isKeyboardFocused: Bool = false
    var isSelectionMode: Bool = false
    var showsSelectionIndicator: Bool = false
    let showsKeptIndicator: Bool
    let timestamp: String
    let searchQuery: String
    let onOpen: () -> Void
    let onSelect: () -> Void
    var onToggleSelection: () -> Void = {}
    var onExtendSelection: () -> Void = {}
    let onCopy: () -> Void
    let onExport: () -> Void
    let onDuplicate: () -> Void
    let onUnkeep: () -> Void
    let onDiscard: () -> Void

    @Environment(\.rascPalette) private var palette
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.noteTextSize) private var noteTextSize
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false
    @FocusState private var rowIsFocused: Bool

    private var showsTrailingActions: Bool {
        isHovered || isSelected
    }

    private var rowExcerpt: String? {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return note.displayHomeExcerpt
        }
        return note.retrievalSnippet(matching: searchQuery)
    }

    private var matchMark: Color {
        palette.searchMark(for: colorScheme, increasedContrast: colorSchemeContrast == .increased)
    }

    var body: some View {
        Button {
            handleClick()
        } label: {
            rowContent
        }
        .buttonStyle(.plain)
        .focused($rowIsFocused)
        .onChange(of: rowIsFocused) { _, focused in if focused { onSelect() } }
        .contextMenu {
            noteActionsMenuContent
        }
        .onHover { isHovered = $0 }
        .animation(RascMotion.micro(reduceMotion: reduceMotion), value: isHovered)
        .animation(RascMotion.selection(reduceMotion: reduceMotion), value: isSelected)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(showsSelectionIndicator ? "Press Space to select or deselect" : "Press Return to open")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var rowContent: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            if showsSelectionIndicator {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isSelected ? Color.primary : palette.metadataText(for: colorScheme))
                    .accessibilityHidden(true)
                    .frame(width: 16)
            }

            Image(systemName: "bookmark.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(palette.metadataText(for: colorScheme))
                .opacity(note.isKept && showsKeptIndicator ? 1 : 0)
                .accessibilityHidden(true)
                .frame(width: 14)

            VStack(alignment: .leading, spacing: 1) {
                Text(RascSearchMatch.highlighted(note.displayTitle, query: searchQuery, mark: matchMark, tokenStartOnly: true, underline: palette.preset == .custom))
                    .font(.system(size: noteTextSize.points(13.5), weight: .medium))
                    .foregroundStyle(palette.noteText(for: colorScheme, fallback: .primary.opacity(0.92)))
                    .lineLimit(1)
                    .multilineTextAlignment(.leading)
                    .truncationMode(.tail)

                if let excerpt = rowExcerpt {
                    Text(RascSearchMatch.highlighted(excerpt, query: searchQuery, mark: matchMark, tokenStartOnly: true, underline: palette.preset == .custom))
                        .font(.system(size: noteTextSize.points(12)))
                        .foregroundStyle(palette.noteText(for: colorScheme, fallback: palette.secondaryText(for: colorScheme)))
                        .lineLimit(1)
                        .multilineTextAlignment(.leading)
                        .truncationMode(.tail)
                }
            }

            Spacer(minLength: 16)

            Text(timestamp)
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(palette.metadataText(for: colorScheme))
                .lineLimit(1)

            noteActionsMenu
                .opacity(showsTrailingActions ? 1 : 0)
                .allowsHitTesting(showsTrailingActions)
                .disabled(!showsTrailingActions)
                .accessibilityHidden(!showsTrailingActions)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: noteTextSize == .large ? 52 : 46, alignment: .center)
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .background {
            if isSelected {
                RascTransientSelectionBackground(cornerRadius: 8)
            } else if isHovered {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(palette.subtleFill(for: colorScheme))
            }
        }
        .overlay {
            if showsSelectionIndicator && isKeyboardFocused && !isSelected {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(palette.focus(for: colorScheme).opacity(0.7), lineWidth: 1.25)
                    .allowsHitTesting(false)
            }
        }
    }

    private var noteActionsMenu: some View {
        Menu {
            noteActionsMenuContent
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(palette.secondaryText(for: colorScheme))
                .symbolRenderingMode(.monochrome)
                .frame(width: 26, height: 26, alignment: .trailing)
                .contentShape(Rectangle().inset(by: -3))
                .background {
                    if isHovered {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(palette.subtleFill(for: colorScheme))
                    }
                }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .tint(.secondary)
        .accessibilityLabel("Note actions")
        .help("Note actions")
    }

    @ViewBuilder
    private var noteActionsMenuContent: some View {
        if note.isKept {
            Button("Unkeep", action: onUnkeep)
        }
        Button("Copy content", action: onCopy)
        Button("Export Thought…", action: onExport)
        Button("Duplicate", action: onDuplicate)
            .disabled(!note.hasMeaningfulContent)
        Button("Discard Note", role: .destructive, action: onDiscard)
    }

    private func handleClick() {
        let flags = NSApp.currentEvent?.modifierFlags.intersection(.deviceIndependentFlagsMask) ?? []
        if flags.contains(.command) { onToggleSelection(); return }
        if flags.contains(.shift) { onExtendSelection(); return }
        if isSelectionMode { onToggleSelection(); return }
        onSelect()
        onOpen()
    }

    private var accessibilityLabel: String {
        var components = [note.displayTitle]
        if note.isKept {
            components.append("Kept")
        }
        if let excerpt = rowExcerpt {
            components.append(excerpt)
        }
        components.append(timestamp)
        return components.joined(separator: ", ")
    }
}

private struct HomeNewScratchButton: View {
    enum Style {
        case header
        case prominent

        var fontSize: CGFloat {
            switch self {
            case .header: 12.5
            case .prominent: 13
            }
        }

        var horizontalPadding: CGFloat {
            switch self {
            case .header: 11
            case .prominent: 14
            }
        }

        var verticalPadding: CGFloat {
            switch self {
            case .header: 7
            case .prominent: 8
            }
        }
    }

    let style: Style
    let action: () -> Void

    @Environment(\.rascPalette) private var palette
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Label("New Scratch", systemImage: "plus")
                .font(.system(size: style.fontSize, weight: .semibold))
                .foregroundStyle(labelColor)
                .padding(.horizontal, style.horizontalPadding)
                .padding(.vertical, style.verticalPadding)
                .background(buttonBackground)
                .overlay(buttonBorder)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(RascMotion.micro(reduceMotion: reduceMotion), value: isHovered)
        .accessibilityLabel("New Scratch")
    }

    private var labelColor: Color {
        style == .prominent
            ? palette.actionPrimaryLabel(for: colorScheme)
            : Color.primary
    }

    @ViewBuilder
    private var buttonBackground: some View {
        RoundedRectangle(
            cornerRadius: HomeLayout.emptyStateCTACornerRadius,
            style: .continuous
        )
        .fill(
            style == .prominent
                ? palette.actionPrimaryFill(for: colorScheme)
                : palette.homeCardFill(for: colorScheme)
        )
        .overlay {
            if style == .header {
                RoundedRectangle(
                    cornerRadius: HomeLayout.emptyStateCTACornerRadius,
                    style: .continuous
                )
                .strokeBorder(
                    palette.innerHighlight(for: colorScheme),
                    lineWidth: 1
                )
            }
        }
        .overlay {
            if isHovered {
                RoundedRectangle(
                    cornerRadius: HomeLayout.emptyStateCTACornerRadius,
                    style: .continuous
                )
                .fill(
                    style == .prominent
                        ? palette.actionPrimaryLabel(for: colorScheme).opacity(0.08)
                        : palette.subtleFill(for: colorScheme)
                )
            }
        }
    }

    @ViewBuilder
    private var buttonBorder: some View {
        if style == .header {
            RoundedRectangle(
                cornerRadius: HomeLayout.emptyStateCTACornerRadius,
                style: .continuous
            )
            .strokeBorder(
                palette.homeCardBorder(
                    for: colorScheme,
                    isHovered: isHovered,
                    increasedContrast: colorSchemeContrast == .increased
                ),
                lineWidth: 0.85
            )
        }
    }
}

/// Two-option Home view switch. Neutral selection on a quiet capsule, never copper;
/// SF Symbols keep it instantly scannable without adding chrome.
private struct HomeViewModeToggle: View {
    @Binding var mode: HomeViewMode

    @Environment(\.rascPalette) private var palette
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        HStack(spacing: 2) {
            ForEach(HomeViewMode.allCases) { option in
                let isSelected = mode == option
                Button {
                    mode = option
                } label: {
                    Image(systemName: option == .list ? "list.bullet" : "square.grid.2x2")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(
                            isSelected
                                ? Color.primary
                                : palette.metadataText(for: colorScheme)
                        )
                        .frame(width: 26, height: 26)
                        .background {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(palette.selectionFill(for: colorScheme))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .strokeBorder(
                                                palette.selectionStroke(for: colorScheme),
                                                lineWidth: contrast == .increased ? 1.5 : 1
                                            )
                                    }
                            }
                        }
                        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous).inset(by: -3))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.accessibilityLabel)
                .accessibilityHint("Switch Home between list and card rendering")
                .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
                .help(option == .list ? "List view" : "Card view")
            }
        }
        .padding(2)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(palette.subtleFill(for: colorScheme))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(palette.border(for: colorScheme).opacity(contrast == .increased ? 1 : 0.66), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
    }
}

/// Home card: the same note, same actions and same selection semantics as the list
/// row, rendered as a stable solid surface that shows a multi-line excerpt.
private struct HomeNoteCardView: View {
    let note: Note
    let isSelected: Bool
    var isKeyboardFocused: Bool = false
    var isSelectionMode: Bool = false
    var showsSelectionIndicator: Bool = false
    let showsKeptIndicator: Bool
    let timestamp: String
    let searchQuery: String
    let onOpen: () -> Void
    let onSelect: () -> Void
    var onToggleSelection: () -> Void = {}
    var onExtendSelection: () -> Void = {}
    let onCopy: () -> Void
    let onExport: () -> Void
    let onDuplicate: () -> Void
    let onUnkeep: () -> Void
    let onDiscard: () -> Void

    @Environment(\.rascPalette) private var palette
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.noteTextSize) private var noteTextSize
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    private var matchMark: Color {
        palette.searchMark(for: colorScheme, increasedContrast: colorSchemeContrast == .increased)
    }

    private var cardExcerpt: String? {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return note.displayHomeExcerpt
        }
        return note.retrievalSnippet(matching: searchQuery)
    }

    private var showsTrailingActions: Bool {
        isHovered || isSelected
    }

    var body: some View {
        Button {
            handleClick()
        } label: {
            cardContent
        }
        .buttonStyle(.plain)
        .contextMenu {
            noteActionsMenuContent
        }
        .onHover { isHovered = $0 }
        .animation(RascMotion.micro(reduceMotion: reduceMotion), value: isHovered)
        .animation(RascMotion.selection(reduceMotion: reduceMotion), value: isSelected)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(showsSelectionIndicator ? "Press Space to select or deselect" : "Press Return to open")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var cardContent: some View {
        HStack(alignment: .top, spacing: 9) {
            if showsSelectionIndicator {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isSelected ? Color.primary : palette.metadataText(for: colorScheme))
                    .frame(width: 16)
                    .padding(.top, 1.5)
                    .accessibilityHidden(true)
            }

            Image(systemName: "bookmark.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(palette.metadataText(for: colorScheme))
                .opacity(note.isKept && showsKeptIndicator ? 1 : 0)
                .frame(width: 14)
                .padding(.top, 3.5)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(RascSearchMatch.highlighted(note.displayTitle, query: searchQuery, mark: matchMark, tokenStartOnly: true, underline: palette.preset == .custom))
                    .font(.system(size: noteTextSize.points(HomeLayout.cardTitleFontSize), weight: .semibold))
                    .foregroundStyle(palette.noteText(for: colorScheme, fallback: .primary.opacity(0.92)))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .truncationMode(.tail)

                if let excerpt = cardExcerpt {
                    Text(RascSearchMatch.highlighted(excerpt, query: searchQuery, mark: matchMark, tokenStartOnly: true, underline: palette.preset == .custom))
                        .font(.system(size: noteTextSize.points(HomeLayout.cardExcerptFontSize)))
                        .foregroundStyle(palette.noteText(for: colorScheme, fallback: palette.secondaryText(for: colorScheme)))
                        .lineLimit(HomeLayout.cardExcerptLineLimit)
                        .multilineTextAlignment(.leading)
                        .truncationMode(.tail)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
                Text(timestamp)
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(palette.metadataText(for: colorScheme))
                    .lineLimit(1)

                noteActionsMenu
                    .opacity(showsTrailingActions ? 1 : 0)
                    .allowsHitTesting(showsTrailingActions)
                    .disabled(!showsTrailingActions)
                    .accessibilityHidden(!showsTrailingActions)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .contentShape(RoundedRectangle(cornerRadius: HomeLayout.gridItemCornerRadius, style: .continuous))
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: HomeLayout.gridItemCornerRadius, style: .continuous)
                    .fill(palette.homeCardFill(for: colorScheme))
                    .overlay {
                        RoundedRectangle(cornerRadius: HomeLayout.gridItemCornerRadius, style: .continuous)
                            .strokeBorder(
                                palette.homeCardBorder(
                                    for: colorScheme,
                                    isHovered: isHovered,
                                    increasedContrast: colorSchemeContrast == .increased
                                ),
                                lineWidth: 0.85
                            )
                    }

                if isSelected {
                    // Behind the content, matching the row rendering; this is
                    // decoration and must never intercept touches.
                    RascTransientSelectionBackground(cornerRadius: HomeLayout.gridItemCornerRadius)
                        .allowsHitTesting(false)
                } else if showsSelectionIndicator && isKeyboardFocused {
                    RoundedRectangle(cornerRadius: HomeLayout.gridItemCornerRadius, style: .continuous)
                        .strokeBorder(palette.focus(for: colorScheme).opacity(0.7), lineWidth: 1.25)
                        .allowsHitTesting(false)
                }
            }
        }
    }

    private var noteActionsMenu: some View {
        Menu {
            noteActionsMenuContent
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(palette.secondaryText(for: colorScheme))
                .symbolRenderingMode(.monochrome)
                .frame(width: 26, height: 26, alignment: .trailing)
                .contentShape(Rectangle().inset(by: -3))
                .background {
                    if isHovered {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(palette.subtleFill(for: colorScheme))
                    }
                }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .tint(.secondary)
        .accessibilityLabel("Note actions")
        .help("Note actions")
    }

    @ViewBuilder
    private var noteActionsMenuContent: some View {
        if note.isKept {
            Button("Unkeep", action: onUnkeep)
        }
        Button("Copy content", action: onCopy)
        Button("Export Thought…", action: onExport)
        Button("Duplicate", action: onDuplicate)
            .disabled(!note.hasMeaningfulContent)
        Button("Discard Note", role: .destructive, action: onDiscard)
    }

    private func handleClick() {
        let flags = NSApp.currentEvent?.modifierFlags.intersection(.deviceIndependentFlagsMask) ?? []
        if flags.contains(.command) { onToggleSelection(); return }
        if flags.contains(.shift) { onExtendSelection(); return }
        if isSelectionMode { onToggleSelection(); return }
        onSelect()
        onOpen()
    }

    private var accessibilityLabel: String {
        var components = [note.displayTitle]
        if note.isKept {
            components.append("Kept")
        }
        if let excerpt = cardExcerpt {
            components.append(excerpt)
        }
        components.append(timestamp)
        return components.joined(separator: ", ")
    }
}

/// Explicit selection mode toggle. Neutral, never copper; keyboard-first.
private struct HomeSelectionToggle: View {
    let isOn: Bool
    let action: () -> Void

    @Environment(\.rascPalette) private var palette
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Button(action: action) {
            Image(systemName: isOn ? "checkmark.circle.fill" : "checkmark.circle")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isOn ? Color.primary : palette.metadataText(for: colorScheme))
                .frame(width: 26, height: 26)
                .background {
                    if isOn {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(palette.selectionFill(for: colorScheme))
                            .overlay {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .strokeBorder(palette.selectionStroke(for: colorScheme), lineWidth: contrast == .increased ? 1.5 : 1)
                            }
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous).inset(by: -3))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isOn ? "Selection mode on" : "Selection mode")
        .accessibilityAddTraits(isOn ? [.isSelected, .isButton] : .isButton)
        .help(isOn ? "Selection mode on. Click to clear." : "Select multiple thoughts")
    }
}

/// Batch actions shown when one or more notes are selected. No folders or tags.
struct HomeBatchActionsBar: View {
    let session: HomeSession
    let undoManager: UndoManager?
    let onNoteDiscarded: (UUID) -> Void
    let onExportSelected: (Set<UUID>) -> Void
    let onCopy: (String) -> Void
    var onDiscardSucceeded: () -> Void = {}
    let onError: (String) -> Void

    @Environment(\.rascPalette) private var palette
    @Environment(\.colorScheme) private var colorScheme
    @State private var isWorking = false

    var body: some View {
        HStack(spacing: 10) {
            Text("\(session.selectedCount) selected")
                .font(.callout.weight(.semibold))
                .monospacedDigit()
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 8)

            Button("Copy") { copySelected() }
                .disabled(isWorking)
            Button("Export…") { onExportSelected(session.selectedNoteIDs) }
                .disabled(isWorking)
            Button("Discard", role: .destructive) { discardSelected() }
                .disabled(isWorking)
            Button("Clear") { session.clearSelection() }
                .keyboardShortcut(.cancelAction)
                .disabled(isWorking)
        }
        .font(.callout)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(palette.subtleFill(for: colorScheme))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(palette.border(for: colorScheme).opacity(0.66), lineWidth: 1)
                }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Batch actions, \(session.selectedCount) selected")
    }

    private func copySelected() {
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                let payload = try await session.batchCopyPayload()
                guard payload.noteCount > 0 else { return }
                if let single = payload.singleDocument, single.hasImages {
                    try await NoteHandoff.copy(single)
                    let imageCount = single.parts.filter { if case .image = $0 { true } else { false } }.count
                    let imageOnly = imageCount == 1 && single.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    onCopy(imageOnly ? "Image copied." : "Copied with images. Paste into a rich-text app.")
                    return
                }
                guard !payload.text.isEmpty else {
                    if payload.includesImages {
                        onError("Selected thoughts contain only images. Copy or export individually.")
                    }
                    return
                }
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                guard pasteboard.setString(payload.text, forType: .string) else {
                    onError("Couldn't copy the selected thoughts.")
                    return
                }
                if payload.includesImages {
                    onCopy("Copied text from \(payload.noteCount) thoughts (images omitted).")
                } else {
                    onCopy(payload.noteCount == 1 ? "Copied." : "Copied \(payload.noteCount) thoughts.")
                }
            } catch {
                onError("Couldn't copy the selected thoughts.")
            }
        }
    }

    private func discardSelected() {
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                let receipts = try await session.discardSelected(undoManager: undoManager)
                for receipt in receipts { onNoteDiscarded(receipt.noteID) }
                onDiscardSucceeded()
            } catch {
                onError("Couldn't discard the selected thoughts. They are still available.")
            }
        }
    }
}

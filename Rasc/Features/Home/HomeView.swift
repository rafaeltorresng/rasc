import AppKit
import SwiftUI

private enum HomeLayout {
    static let contentMaxWidth: CGFloat = 1_200
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
}

struct HomeView: View {
    @Bindable var session: HomeSession
    let onOpenNote: (UUID) -> Void
    let onNewScratch: () -> Void
    let onNoteDiscarded: (UUID) -> Void
    let onNoteUnkept: (UUID) -> Void
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.undoManager) private var undoManager
    @ObservedObject private var internalShortcuts = InternalShortcutStore.shared
    @FocusState private var searchIsFocused: Bool
    @FocusState private var listIsFocused: Bool
    @State private var retryAction: (() -> Void)?
    @State private var copyFeedback: String?
    @State private var copyFeedbackTask: Task<Void, Never>?

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
                                if session.showsHistoryHint, !session.isSearching {
                                    historyHint
                                        .padding(.top, HomeLayout.contentTopPadding)
                                        .transition(
                                            RascMotion.headerAccessoryTransition(reduceMotion: reduceMotion)
                                        )
                                }

                                contentBody
                                    .padding(.top, HomeLayout.contentTopPadding)
                                    .padding(.bottom, HomeLayout.contentBottomPadding)
                            }
                        }
                    }
                    .focusable()
                    .focused($listIsFocused)
                    .onChange(of: session.selectedNoteID) { _, noteID in
                        guard let noteID else { return }
                        scrollProxy.scrollTo(noteID)
                    }
                }
            }
            if let error = session.actionErrorMessage {
                HStack(spacing: 12) {
                    Text(error).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    if let retryAction { Button("Retry", action: retryAction) }
                    else if session.lastDiscard != nil { Button("Undo") { Task { await session.undoDiscard() } } }
                    Button("Dismiss") { session.actionErrorMessage = nil; retryAction = nil }
                }
                .font(.callout)
                .padding(.horizontal, HomeLayout.horizontalPadding)
                .padding(.vertical, 12)
                .accessibilityElement(children: .contain)
            } else if session.lastDiscard != nil {
                HStack {
                    Text("Thought discarded.")
                        .foregroundStyle(RascSurfacePalette.secondaryText(for: colorScheme))
                    Spacer()
                    Button("Undo") { Task { await session.undoDiscard() } }
                }
                .font(.callout)
                .padding(.horizontal, HomeLayout.horizontalPadding)
                .padding(.vertical, 12)
            } else if let copyFeedback {
                Text(copyFeedback)
                    .font(.callout)
                    .foregroundStyle(RascSurfacePalette.secondaryText(for: colorScheme))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, HomeLayout.horizontalPadding)
                    .padding(.vertical, 12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .rascWindowSurface()
        .animation(RascMotion.surface(reduceMotion: reduceMotion), value: session.showsHistoryHint)
        .onChange(of: session.actionErrorMessage) { _, message in
            if let message { RascAccessibility.announce(message) }
        }
        .onChange(of: copyFeedback) { _, message in
            if let message { RascAccessibility.announce(message) }
        }
        .onChange(of: session.lastDiscard) { _, receipt in
            if receipt != nil { RascAccessibility.announce("Thought discarded. Undo is available.") }
        }
        .onKeyPress(.upArrow) {
            guard !searchIsFocused else { return .ignored }
            listIsFocused = true
            session.moveSelection(.up, columns: 1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            guard !searchIsFocused else { return .ignored }
            listIsFocused = true
            session.moveSelection(.down, columns: 1)
            return .handled
        }
        .onKeyPress(.leftArrow) {
            guard !searchIsFocused else { return .ignored }
            listIsFocused = true
            session.moveSelection(.left, columns: 1)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            guard !searchIsFocused else { return .ignored }
            listIsFocused = true
            session.moveSelection(.right, columns: 1)
            return .handled
        }
        .onKeyPress(.return) {
            guard !searchIsFocused, listIsFocused else { return .ignored }
            openSelectedNote()
            return .handled
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

            HomeSearchField(text: $session.searchQuery, isFocused: $searchIsFocused)
                .onSubmit { searchIsFocused = false; listIsFocused = true }
                .onKeyPress(.downArrow) {
                    searchIsFocused = false
                    listIsFocused = true
                    return .handled
                }
                .frame(minWidth: HomeLayout.searchMinWidth, maxWidth: HomeLayout.searchMaxWidth)

            Spacer(minLength: 12)

            HomeNewScratchButton(style: .header, action: onNewScratch)

            RascSettingsLink {
                Image(systemName: "gearshape")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(RascSurfacePalette.secondaryText(for: colorScheme))
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
                Text("Search from anywhere with")
                ShortcutKeycapView(
                    label: internalShortcuts.displayString(for: .search),
                    style: .compact
                )
                Text("Search thoughts")
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                "Search from anywhere with \(internalShortcuts.displayString(for: .search)). Search thoughts."
            )

            Spacer(minLength: 8)

            Button {
                session.dismissHistoryHint()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(RascSurfacePalette.secondaryText(for: colorScheme))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss search tip")
            .help("Dismiss")
        }
        .font(.callout)
        .foregroundStyle(RascSurfacePalette.secondaryText(for: colorScheme))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(RascSurfacePalette.subtleFill(for: colorScheme))
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
                RascOrb(state: session.emptyStateOrbState, size: .hero, decorative: true)
                    .padding(.bottom, 2)

                Text("Your thoughts")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(RascSurfacePalette.homeSectionLabel(for: colorScheme))
                    .accessibilityAddTraits(.isHeader)

                VStack(spacing: 8) {
                    Text("Nothing here yet.")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.primary.opacity(0.9))

                    Text("Your thoughts will appear here as you use Rasc.")
                        .font(.system(size: 13))
                        .foregroundStyle(RascSurfacePalette.homeSupportingText(for: colorScheme))
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
        .accessibilityLabel("Nothing here yet. Your thoughts will appear here as you use Rasc.")
    }

    private var chronologicalList: some View {
        VStack(alignment: .leading, spacing: HomeLayout.temporalGroupSpacing) {
            ForEach(Array(session.visibleBrowseGroups.enumerated()), id: \.element.id) { index, group in
                VStack(alignment: .leading, spacing: HomeLayout.temporalLabelSpacing) {
                    sectionTitle(for: group)

                    noteList(
                        for: group.notes,
                        showsKeptIndicator: !isKeptSection(group)
                    )
                    if isKeptSection(group), session.keptCount > HomeLifecycleGrouping.keptSectionLimit {
                        Button(session.showsAllKept ? "Show fewer" : "Show all \(session.keptCount) kept thoughts") {
                            session.toggleKeptVisibility()
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
            noteList(for: session.searchResults)
            if session.hasMoreSearchResults {
                Text("Showing the first 500 matches. Narrow your search to find more.")
                    .font(.callout)
                    .foregroundStyle(RascSurfacePalette.secondaryText(for: colorScheme))
            }
        }
            .animation(RascMotion.bodyContentAnimation(reduceMotion: reduceMotion), value: session.searchResults.map(\.id))
    }

    private func noteList(
        for notes: [Note],
        showsKeptIndicator: Bool = true
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(notes.enumerated()), id: \.element.id) { index, note in
                HomeNoteRowView(
                    note: note,
                    isSelected: session.selectedNoteID == note.id,
                    showsKeptIndicator: showsKeptIndicator,
                    timestamp: session.formattedTimestamp(for: note),
                    searchQuery: session.searchQuery,
                    onOpen: { onOpenNote(note.id) },
                    onSelect: { session.selectNote(note.id) },
                    onCopy: { copyNote(note.id) },
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
            .foregroundStyle(RascSurfacePalette.secondaryText(for: colorScheme))
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
        .foregroundStyle(RascSurfacePalette.homeSectionLabel(for: colorScheme))
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

private struct HomeSearchField: View {
    @Binding var text: String
    let isFocused: FocusState<Bool>.Binding

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        RascTransientInputShell(isFocused: isFocused.wrappedValue) {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(RascSurfacePalette.metadataText(for: colorScheme))

                TextField(
                    "",
                    text: $text,
                    prompt: Text("Search thoughts…")
                        .foregroundStyle(RascSurfacePalette.metadataText(for: colorScheme))
                )
                .textFieldStyle(.plain)
                .font(.system(size: 13.5))
                .focused(isFocused)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Search thoughts")
    }
}

private struct HomeNoteRowView: View {
    let note: Note
    let isSelected: Bool
    let showsKeptIndicator: Bool
    let timestamp: String
    let searchQuery: String
    let onOpen: () -> Void
    let onSelect: () -> Void
    let onCopy: () -> Void
    let onDuplicate: () -> Void
    let onUnkeep: () -> Void
    let onDiscard: () -> Void

    @Environment(\.colorScheme) private var colorScheme
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

    var body: some View {
        Button {
            onSelect()
            onOpen()
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
        .accessibilityHint("Press Return to open")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var rowContent: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "bookmark.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(RascSurfacePalette.metadataText(for: colorScheme))
                .opacity(note.isKept && showsKeptIndicator ? 1 : 0)
                .accessibilityHidden(true)
                .frame(width: 14)

            VStack(alignment: .leading, spacing: 1) {
                Text(note.displayTitle)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.92))
                    .lineLimit(1)
                    .multilineTextAlignment(.leading)
                    .truncationMode(.tail)

                if let excerpt = rowExcerpt {
                    Text(excerpt)
                        .font(.system(size: 12))
                        .foregroundStyle(RascSurfacePalette.secondaryText(for: colorScheme))
                        .lineLimit(1)
                        .multilineTextAlignment(.leading)
                        .truncationMode(.tail)
                }
            }

            Spacer(minLength: 16)

            Text(timestamp)
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(RascSurfacePalette.metadataText(for: colorScheme))
                .lineLimit(1)

            noteActionsMenu
                .opacity(showsTrailingActions ? 1 : 0)
                .allowsHitTesting(showsTrailingActions)
                .disabled(!showsTrailingActions)
                .accessibilityHidden(!showsTrailingActions)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 46, maxHeight: 46, alignment: .center)
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .background {
            if isSelected {
                RascTransientSelectionBackground(cornerRadius: 8)
            } else if isHovered {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(RascSurfacePalette.subtleFill(for: colorScheme))
            }
        }
    }

    private var noteActionsMenu: some View {
        Menu {
            noteActionsMenuContent
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(RascSurfacePalette.secondaryText(for: colorScheme))
                .symbolRenderingMode(.monochrome)
                .frame(width: 22, height: 22)
                .background {
                    if isHovered {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(RascSurfacePalette.subtleFill(for: colorScheme))
                    }
                }
                .contentShape(Rectangle())
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
        Button("Duplicate", action: onDuplicate)
            .disabled(!note.hasMeaningfulContent)
        Button("Discard Note", role: .destructive, action: onDiscard)
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
            ? RascSurfacePalette.actionPrimaryLabel(for: colorScheme)
            : RascSurfacePalette.primaryText(for: colorScheme)
    }

    @ViewBuilder
    private var buttonBackground: some View {
        RoundedRectangle(
            cornerRadius: HomeLayout.emptyStateCTACornerRadius,
            style: .continuous
        )
        .fill(
            style == .prominent
                ? RascSurfacePalette.actionPrimaryFill(for: colorScheme)
                : RascSurfacePalette.homeCardFill(for: colorScheme)
        )
        .overlay {
            if style == .header {
                RoundedRectangle(
                    cornerRadius: HomeLayout.emptyStateCTACornerRadius,
                    style: .continuous
                )
                .strokeBorder(
                    RascSurfacePalette.innerHighlight(for: colorScheme),
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
                        ? RascSurfacePalette.actionPrimaryLabel(for: colorScheme).opacity(0.08)
                        : RascSurfacePalette.subtleFill(for: colorScheme)
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
                RascSurfacePalette.homeCardBorder(
                    for: colorScheme,
                    isHovered: isHovered,
                    increasedContrast: colorSchemeContrast == .increased
                ),
                lineWidth: 0.85
            )
        }
    }
}

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
    static let gridSpacing: CGFloat = 16
    static let gridMaxColumns = 4
    static let idealCardWidth: CGFloat = 260
    static let browseCardHeight: CGFloat = 116
    static let browseCompactCardHeight: CGFloat = 86
    static let searchCardHeight: CGFloat = 108
    static let searchCompactCardHeight: CGFloat = 84
    static let cardCornerRadius: CGFloat = 12
    static let cardPadding: CGFloat = 14
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
    @FocusState private var searchIsFocused: Bool
    @FocusState private var gridIsFocused: Bool
    @State private var retryAction: (() -> Void)?
    @State private var gridContainerWidth: CGFloat = 0

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
                            contentBody
                                .padding(.top, HomeLayout.contentTopPadding)
                                .padding(.bottom, HomeLayout.contentBottomPadding)
                        }
                    }
                    .focusable()
                    .focused($gridIsFocused)
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
                    Text("Thought discarded.").foregroundStyle(.secondary)
                    Spacer()
                    Button("Undo") { Task { await session.undoDiscard() } }
                }
                .font(.callout)
                .padding(.horizontal, HomeLayout.horizontalPadding)
                .padding(.vertical, 12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .rascWindowSurface()
        .onChange(of: session.actionErrorMessage) { _, message in
            if let message { RascAccessibility.announce(message) }
        }
        .onChange(of: session.lastDiscard) { _, receipt in
            if receipt != nil { RascAccessibility.announce("Thought discarded. Undo is available.") }
        }
        .onKeyPress(.upArrow) {
            guard !searchIsFocused else { return .ignored }
            gridIsFocused = true
            session.moveSelection(.up, columns: HomeGridLayout.columnCount(for: max(0, gridContainerWidth - HomeLayout.horizontalPadding * 2)))
            return .handled
        }
        .onKeyPress(.downArrow) {
            guard !searchIsFocused else { return .ignored }
            gridIsFocused = true
            session.moveSelection(.down, columns: HomeGridLayout.columnCount(for: max(0, gridContainerWidth - HomeLayout.horizontalPadding * 2)))
            return .handled
        }
        .onKeyPress(.leftArrow) {
            guard !searchIsFocused else { return .ignored }
            gridIsFocused = true
            session.moveSelection(.left, columns: HomeGridLayout.columnCount(for: max(0, gridContainerWidth - HomeLayout.horizontalPadding * 2)))
            return .handled
        }
        .onKeyPress(.rightArrow) {
            guard !searchIsFocused else { return .ignored }
            gridIsFocused = true
            session.moveSelection(.right, columns: HomeGridLayout.columnCount(for: max(0, gridContainerWidth - HomeLayout.horizontalPadding * 2)))
            return .handled
        }
        .onKeyPress(.return) {
            guard !searchIsFocused, gridIsFocused else { return .ignored }
            openSelectedNote()
            return .handled
        }
    }

    private func homeContentColumn<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: HomeLayout.contentMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, HomeLayout.horizontalPadding)
            .homeLayoutWidthReader($gridContainerWidth)
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
                .onSubmit { searchIsFocused = false; gridIsFocused = true }
                .onKeyPress(.downArrow) {
                    searchIsFocused = false
                    gridIsFocused = true
                    return .handled
                }
                .frame(minWidth: HomeLayout.searchMinWidth, maxWidth: HomeLayout.searchMaxWidth)

            Spacer(minLength: 12)

            HomeNewScratchButton(style: .header, action: onNewScratch)

            RascSettingsLink {
                Image(systemName: "gearshape")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
            .help("Settings")
        }
    }

    @ViewBuilder
    private var contentBody: some View {
        if let loadErrorMessage = session.loadErrorMessage {
            quietStateLabel(loadErrorMessage)
        } else if session.showsNoSearchResults {
            quietStateLabel("No thoughts found.")
        } else if session.isSearching {
            searchResultsGrid
        } else {
            chronologicalGrid
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

    private var chronologicalGrid: some View {
        VStack(alignment: .leading, spacing: HomeLayout.temporalGroupSpacing) {
            ForEach(Array(session.visibleBrowseGroups.enumerated()), id: \.element.id) { index, group in
                VStack(alignment: .leading, spacing: HomeLayout.temporalLabelSpacing) {
                    sectionTitle(for: group)

                    noteGrid(
                        for: group.notes,
                        style: .browse,
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

    private var searchResultsGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            noteGrid(for: session.searchResults, style: .search)
            if session.hasMoreSearchResults {
                Text("Showing the first 500 matches. Narrow your search to find more.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
            .animation(RascMotion.bodyContentAnimation(reduceMotion: reduceMotion), value: session.searchResults.map(\.id))
    }

    private func noteGrid(
        for notes: [Note],
        style: HomeNoteCardStyle,
        showsKeptIndicator: Bool = true
    ) -> some View {
        HomeNoteGrid(
            notes: notes,
            containerWidth: max(0, gridContainerWidth - HomeLayout.horizontalPadding * 2)
        ) { note in
            HomeNoteCard(
                note: note,
                style: style,
                isSelected: session.selectedNoteID == note.id,
                showsKeptIndicator: showsKeptIndicator,
                timestamp: session.formattedTimestamp(for: note),
                searchQuery: session.searchQuery,
                onOpen: { onOpenNote(note.id) },
                onSelect: { session.selectNote(note.id) },
                onDuplicate: { duplicateNote(note.id) },
                onUnkeep: { unkeepNote(note.id) },
                onDiscard: { discardNote(note.id) }
            )
            .id(note.id)
        }
    }

    private func quietStateLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 15))
            .foregroundStyle(.secondary)
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
        Text(group.sectionTitle)
            .font(.system(size: 12, weight: .semibold))
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

private enum HomeNoteCardStyle {
    case browse
    case search

    func cardHeight(hasExcerpt: Bool) -> CGFloat {
        switch self {
        case .browse:
            hasExcerpt ? HomeLayout.browseCardHeight : HomeLayout.browseCompactCardHeight
        case .search:
            hasExcerpt ? HomeLayout.searchCardHeight : HomeLayout.searchCompactCardHeight
        }
    }

    var excerptLineLimit: Int {
        switch self {
        case .browse, .search:
            2
        }
    }

    var titleFontSize: CGFloat {
        switch self {
        case .browse: 14.5
        case .search: 14
        }
    }
}

private struct HomeSearchField: View {
    @Binding var text: String
    let isFocused: FocusState<Bool>.Binding

    var body: some View {
        RascTransientInputShell(isFocused: isFocused.wrappedValue) {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.tertiary)

                TextField(
                    "",
                    text: $text,
                    prompt: Text("Search thoughts…")
                        .foregroundStyle(.tertiary)
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

private struct HomeNoteCard: View {
    let note: Note
    let style: HomeNoteCardStyle
    let isSelected: Bool
    let showsKeptIndicator: Bool
    let timestamp: String
    let searchQuery: String
    let onOpen: () -> Void
    let onSelect: () -> Void
    let onDuplicate: () -> Void
    let onUnkeep: () -> Void
    let onDiscard: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false
    @FocusState private var cardIsFocused: Bool

    private var showsCardActions: Bool {
        isHovered || isSelected
    }

    private var cardExcerpt: String? {
        switch style {
        case .browse:
            note.displayHomeExcerpt
        case .search:
            note.retrievalSnippet(matching: searchQuery)
        }
    }

    private var resolvedCardHeight: CGFloat {
        style.cardHeight(hasExcerpt: cardExcerpt != nil)
    }

    var body: some View {
        Button {
            onSelect()
            onOpen()
        } label: {
            cardContent
        }
        .buttonStyle(HomeNoteCardButtonStyle())
        .focused($cardIsFocused)
        .onChange(of: cardIsFocused) { _, focused in if focused { onSelect() } }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .overlay(alignment: .topTrailing) {
            cardHeaderActions
                .padding(.top, HomeLayout.cardPadding + 1)
                .padding(.trailing, HomeLayout.cardPadding - 2)
        }
        .contextMenu {
            noteActionMenuContent
        }
        .onHover { isHovered = $0 }
        .animation(RascMotion.micro(reduceMotion: reduceMotion), value: isHovered)
        .animation(RascMotion.selection(reduceMotion: reduceMotion), value: isSelected)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Press Return to open")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(note.displayTitle)
                .font(.system(size: style.titleFontSize, weight: .medium))
                .foregroundStyle(.primary.opacity(0.94))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, cardHeaderTrailingInset)

            if let snippet = cardExcerpt {
                Text(snippet)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary.opacity(0.92))
                    .lineSpacing(1.5)
                    .lineLimit(style.excerptLineLimit)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .padding(HomeLayout.cardPadding)
        .frame(
            maxWidth: .infinity,
            minHeight: resolvedCardHeight,
            maxHeight: .infinity,
            alignment: .topLeading
        )
        .background(cardBackground)
        .overlay(cardBorder)
        .shadow(
            color: .black.opacity(cardShadowOpacity),
            radius: cardShadowRadius,
            y: cardShadowYOffset
        )
        .contentShape(Rectangle())
    }

    private var cardHeaderTrailingInset: CGFloat {
        note.isKept && showsKeptIndicator ? 84 : 70
    }

    private var cardHeaderActions: some View {
        HStack(alignment: .center, spacing: 5) {
            if note.isKept, showsKeptIndicator {
                keptHeaderIndicator
            }

            Text(timestamp)
                .font(.system(size: 10.5, weight: .medium, design: .rounded))
                .foregroundStyle(.tertiary)
                .lineLimit(1)

            noteActionsMenu
                .opacity(showsCardActions ? 1 : 0)
                .allowsHitTesting(showsCardActions)
                .disabled(!showsCardActions)
                .accessibilityHidden(!showsCardActions)
        }
        .fixedSize(horizontal: true, vertical: false)
        .animation(RascMotion.micro(reduceMotion: reduceMotion), value: showsCardActions)
    }

    private var noteActionsMenu: some View {
        Menu {
            noteActionMenuContent
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
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
    private var noteActionMenuContent: some View {
        if note.isKept {
            Button("Unkeep", action: onUnkeep)
        }
        Button("Copy content") {
            NoteHandoff.copyPlainText(note.content)
        }
        Button("Duplicate", action: onDuplicate)
        Button("Discard Note", role: .destructive, action: onDiscard)
    }

    private var keptHeaderIndicator: some View {
        Image(systemName: "bookmark.fill")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(RascSurfacePalette.homeSupportingText(for: colorScheme))
            .frame(width: 11, height: 11)
            .accessibilityHidden(true)
    }

    private var cardShadowOpacity: Double {
        RascSurfacePalette.homeCardShadowOpacity(
            for: colorScheme,
            isHovered: isHovered,
            isSelected: isSelected
        )
    }

    private var cardShadowRadius: CGFloat {
        RascSurfacePalette.homeCardShadowRadius(
            for: colorScheme,
            isHovered: isHovered,
            isSelected: isSelected
        )
    }

    private var cardShadowYOffset: CGFloat {
        if isSelected || isHovered {
            return colorScheme == .dark ? 4 : 3
        }
        return colorScheme == .dark ? 3 : 2
    }

    private var accessibilityLabel: String {
        var components = [note.displayTitle]
        if note.isKept {
            components.append("Kept")
        }
        if let snippet = cardExcerpt {
            components.append(snippet)
        }
        components.append(timestamp)
        return components.joined(separator: ", ")
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: HomeLayout.cardCornerRadius, style: .continuous)
            .fill(RascSurfacePalette.homeCardFill(for: colorScheme))
            .overlay {
                RoundedRectangle(cornerRadius: HomeLayout.cardCornerRadius, style: .continuous)
                    .strokeBorder(
                        RascSurfacePalette.innerHighlight(for: colorScheme),
                        lineWidth: 1
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: HomeLayout.cardCornerRadius, style: .continuous)
                    .strokeBorder(
                        RascSurfacePalette.homeCardVioletUndertone(
                            for: colorScheme,
                            isHovered: isHovered,
                            isSelected: isSelected
                        ),
                        lineWidth: 1
                    )
            }
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: HomeLayout.cardCornerRadius, style: .continuous)
                        .fill(RascSurfacePalette.homeCardSelectionFill(for: colorScheme))
                } else if isHovered {
                    RoundedRectangle(cornerRadius: HomeLayout.cardCornerRadius, style: .continuous)
                        .fill(RascSurfacePalette.subtleFill(for: colorScheme))
                }
            }
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: HomeLayout.cardCornerRadius, style: .continuous)
            .strokeBorder(borderColor, lineWidth: borderLineWidth)
    }

    private var borderColor: Color {
        RascSurfacePalette.homeCardBorder(
            for: colorScheme,
            isHovered: isHovered,
            isSelected: isSelected,
            increasedContrast: colorSchemeContrast == .increased
        )
    }

    private var borderLineWidth: CGFloat {
        if isSelected {
            return 1
        }
        return 0.85
    }
}

private struct HomeNoteCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.94 : 1)
    }
}

private enum HomeGridLayout {
    static func columnCount(for availableWidth: CGFloat) -> Int {
        let spacing = HomeLayout.gridSpacing
        let cardWidth = HomeLayout.idealCardWidth

        guard availableWidth > 0 else { return 1 }

        let count = Int((availableWidth + spacing) / (cardWidth + spacing))
        return max(1, min(HomeLayout.gridMaxColumns, count))
    }

    static func columns(for availableWidth: CGFloat) -> [GridItem] {
        let spacing = HomeLayout.gridSpacing
        let cardWidth = HomeLayout.idealCardWidth
        let columnCount = columnCount(for: availableWidth)

        return Array(
            repeating: GridItem(.flexible(minimum: cardWidth, maximum: 360), spacing: spacing),
            count: columnCount
        )
    }
}

private struct HomeLayoutWidthReaderModifier: ViewModifier {
    @Binding var width: CGFloat

    func body(content: Content) -> some View {
        content.onGeometryChange(for: CGFloat.self) { geometry in
            geometry.size.width
        } action: { newWidth in
            width = newWidth
        }
    }
}

private extension View {
    func homeLayoutWidthReader(_ width: Binding<CGFloat>) -> some View {
        modifier(HomeLayoutWidthReaderModifier(width: width))
    }
}

private struct HomeNoteGrid<Card: View>: View {
    let notes: [Note]
    let containerWidth: CGFloat
    @ViewBuilder let card: (Note) -> Card

    var body: some View {
        LazyVGrid(
            columns: HomeGridLayout.columns(for: containerWidth),
            alignment: .leading,
            spacing: HomeLayout.gridSpacing
        ) {
            ForEach(notes, id: \.id) { note in
                card(note)
                    .frame(maxHeight: .infinity, alignment: .topLeading)
            }
        }
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Label("New Scratch", systemImage: "plus")
                .font(.system(size: style.fontSize, weight: .semibold))
                .foregroundStyle(RascSurfacePalette.actionAccent(for: colorScheme))
                .padding(.horizontal, style.horizontalPadding)
                .padding(.vertical, style.verticalPadding)
                .background(buttonBackground)
                .overlay(buttonBorder)
        }
        .buttonStyle(HomeNoteCardButtonStyle())
        .onHover { isHovered = $0 }
        .animation(RascMotion.micro(reduceMotion: reduceMotion), value: isHovered)
        .accessibilityLabel("New Scratch")
    }

    @ViewBuilder
    private var buttonBackground: some View {
        RoundedRectangle(
            cornerRadius: HomeLayout.emptyStateCTACornerRadius,
            style: .continuous
        )
        .fill(RascSurfacePalette.homeCardFill(for: colorScheme))
        .overlay {
            RoundedRectangle(
                cornerRadius: HomeLayout.emptyStateCTACornerRadius,
                style: .continuous
            )
            .strokeBorder(
                RascSurfacePalette.innerHighlight(for: colorScheme),
                lineWidth: 1
            )
        }
        .overlay {
            if isHovered {
                RoundedRectangle(
                    cornerRadius: HomeLayout.emptyStateCTACornerRadius,
                    style: .continuous
                )
                .fill(RascSurfacePalette.subtleFill(for: colorScheme))
            }
        }
    }

    private var buttonBorder: some View {
        RoundedRectangle(
            cornerRadius: HomeLayout.emptyStateCTACornerRadius,
            style: .continuous
        )
        .strokeBorder(
            RascSurfacePalette.homeCardBorder(
                for: colorScheme,
                isHovered: isHovered,
                isSelected: false,
                increasedContrast: false
            ),
            lineWidth: 0.85
        )
    }
}

import SwiftUI

private enum HomeLayout {
    static let contentMaxWidth: CGFloat = 1_180
    static let horizontalPadding: CGFloat = 32
    static let actionZoneTopPadding: CGFloat = 18
    static let actionZoneBottomPadding: CGFloat = 14
    static let contentTopPadding: CGFloat = 6
    static let contentBottomPadding: CGFloat = 40
    static let temporalGroupSpacing: CGFloat = 30
    static let temporalLabelSpacing: CGFloat = 12
    static let gridSpacing: CGFloat = 14
    static let cardMinWidth: CGFloat = 258
    static let cardMaxWidth: CGFloat = 296
    static let browseCardHeight: CGFloat = 154
    static let searchCardHeight: CGFloat = 132
    static let cardCornerRadius: CGFloat = 12
    static let cardPadding: CGFloat = 16
    static let searchMinWidth: CGFloat = 220
    static let searchMaxWidth: CGFloat = 440
    static let identitySpacing: CGFloat = 9
    static let actionZoneSpacing: CGFloat = 14
    static let quietStateMinHeight: CGFloat = 240
}

struct HomeView: View {
    @Bindable var session: HomeSession
    let onOpenNote: (UUID) -> Void
    let onNewScratch: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            homeContentColumn {
                actionZone
                    .padding(.top, HomeLayout.actionZoneTopPadding)
                    .padding(.bottom, HomeLayout.actionZoneBottomPadding)
            }

            ScrollViewReader { scrollProxy in
                ScrollView {
                    homeContentColumn {
                        contentBody
                            .padding(.top, HomeLayout.contentTopPadding)
                            .padding(.bottom, HomeLayout.contentBottomPadding)
                    }
                }
                .onChange(of: session.selectedNoteID) { _, noteID in
                    guard let noteID else { return }
                    scrollProxy.scrollTo(noteID, anchor: .center)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .rascWindowSurface()
        .registersSettingsOpenAction()
        .onKeyPress(.upArrow) {
            session.moveSelection(by: -1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            session.moveSelection(by: 1)
            return .handled
        }
        .onKeyPress(.leftArrow) {
            session.moveSelection(by: -1)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            session.moveSelection(by: 1)
            return .handled
        }
        .onKeyPress(.return) {
            openSelectedNote()
            return .handled
        }
    }

    private func homeContentColumn<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            content()
                .frame(maxWidth: HomeLayout.contentMaxWidth, alignment: .leading)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, HomeLayout.horizontalPadding)
    }

    private var actionZone: some View {
        HStack(alignment: .center, spacing: HomeLayout.actionZoneSpacing) {
            HStack(spacing: HomeLayout.identitySpacing) {
                RascOrb(state: session.orbState, size: .inline, decorative: true)
                    .frame(width: RascSurfaceLayout.orbSize, height: RascSurfaceLayout.orbSize)

                Text("Rasc")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary.opacity(0.92))
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Rasc")

            HomeSearchField(text: $session.searchQuery)
                .frame(minWidth: HomeLayout.searchMinWidth, maxWidth: HomeLayout.searchMaxWidth)
                .layoutPriority(1)

            Spacer(minLength: 8)

            Button(action: onNewScratch) {
                Label("New Scratch", systemImage: "plus")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(RascSurfacePalette.actionAccent(for: colorScheme))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("New Scratch")

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
        } else if session.showsEmptyHome {
            emptyHomeState
        } else if session.showsNoSearchResults {
            quietStateLabel("No notes found.")
        } else if session.isSearching {
            searchResultsGrid
        } else {
            chronologicalGrid
        }
    }

    private var emptyHomeState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Nothing here yet.")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)

            Text("Your notes will appear here as you use Rasc.")
                .font(.system(size: 13))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: onNewScratch) {
                Text("New Scratch")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(RascSurfacePalette.actionAccent(for: colorScheme))
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
            .accessibilityLabel("New Scratch")
        }
        .frame(maxWidth: .infinity, minHeight: HomeLayout.quietStateMinHeight, alignment: .leading)
        .padding(.top, 12)
    }

    private var chronologicalGrid: some View {
        VStack(alignment: .leading, spacing: HomeLayout.temporalGroupSpacing) {
            ForEach(session.temporalGroups) { group in
                VStack(alignment: .leading, spacing: HomeLayout.temporalLabelSpacing) {
                    Text(group.section.rawValue)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityAddTraits(.isHeader)

                    noteGrid(for: group.notes, style: .browse)
                }
            }
        }
        .animation(RascMotion.bodyContentAnimation(reduceMotion: reduceMotion), value: session.temporalGroups.map(\.id))
    }

    private var searchResultsGrid: some View {
        noteGrid(for: session.searchResults, style: .search)
            .animation(RascMotion.bodyContentAnimation(reduceMotion: reduceMotion), value: session.searchResults.map(\.id))
    }

    private func noteGrid(for notes: [Note], style: HomeNoteCardStyle) -> some View {
        LazyVGrid(
            columns: [
                GridItem(
                    .adaptive(minimum: HomeLayout.cardMinWidth, maximum: HomeLayout.cardMaxWidth),
                    spacing: HomeLayout.gridSpacing
                ),
            ],
            alignment: .leading,
            spacing: HomeLayout.gridSpacing
        ) {
            ForEach(notes, id: \.id) { note in
                HomeNoteCard(
                    note: note,
                    style: style,
                    isSelected: session.selectedNoteID == note.id,
                    timestamp: session.formattedTimestamp(for: note),
                    onOpen: { onOpenNote(note.id) },
                    onSelect: { session.selectNote(note.id) }
                )
                .id(note.id)
            }
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
}

private enum HomeNoteCardStyle {
    case browse
    case search

    var cardHeight: CGFloat {
        switch self {
        case .browse:
            HomeLayout.browseCardHeight
        case .search:
            HomeLayout.searchCardHeight
        }
    }

    var excerptLineLimit: Int {
        switch self {
        case .browse:
            3
        case .search:
            2
        }
    }
}

private struct HomeSearchField: View {
    @Binding var text: String
    @FocusState private var isFocused: Bool

    var body: some View {
        RascTransientInputShell(isFocused: isFocused) {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.tertiary)

                TextField(
                    "",
                    text: $text,
                    prompt: Text("Search notes…")
                        .foregroundStyle(.tertiary)
                )
                .textFieldStyle(.plain)
                .font(.system(size: 13.5))
                .focused($isFocused)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Search notes")
    }
}

private struct HomeNoteCard: View {
    let note: Note
    let style: HomeNoteCardStyle
    let isSelected: Bool
    let timestamp: String
    let onOpen: () -> Void
    let onSelect: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    var body: some View {
        Button {
            onSelect()
            onOpen()
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Text(note.displayTitle)
                    .font(.system(size: 14.5, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let snippet = note.displayRetrievalSnippet ?? note.displaySnippet {
                    Text(snippet)
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(style.excerptLineLimit)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                } else {
                    Spacer(minLength: 0)
                }

                Text(timestamp)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(HomeLayout.cardPadding)
            .frame(maxWidth: .infinity, minHeight: style.cardHeight, maxHeight: style.cardHeight, alignment: .topLeading)
            .background(cardBackground)
            .overlay(cardBorder)
        }
        .buttonStyle(HomeNoteCardButtonStyle())
        .onHover { isHovered = $0 }
        .animation(RascMotion.micro(reduceMotion: reduceMotion), value: isHovered)
        .animation(RascMotion.selection(reduceMotion: reduceMotion), value: isSelected)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Press Return to open")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var accessibilityLabel: String {
        var components = [note.displayTitle]
        if let snippet = note.displayRetrievalSnippet ?? note.displaySnippet {
            components.append(snippet)
        }
        components.append(timestamp)
        return components.joined(separator: ", ")
    }

    @ViewBuilder
    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: HomeLayout.cardCornerRadius, style: .continuous)
            .fill(RascSurfacePalette.raisedFill(for: colorScheme))
            .overlay {
                if isHovered && !isSelected {
                    RoundedRectangle(cornerRadius: HomeLayout.cardCornerRadius, style: .continuous)
                        .fill(RascSurfacePalette.subtleFill(for: colorScheme))
                }
            }
    }

    @ViewBuilder
    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: HomeLayout.cardCornerRadius, style: .continuous)
            .strokeBorder(borderColor, lineWidth: borderLineWidth)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: HomeLayout.cardCornerRadius, style: .continuous)
                        .fill(RascSurfacePalette.selectionFill(for: colorScheme))
                }
            }
    }

    private var borderColor: Color {
        if isSelected {
            return RascSurfacePalette.selectionStroke(for: colorScheme)
        }

        let baseOpacity = colorSchemeContrast == .increased ? 0.82 : 0.58
        let hoverOpacity = colorSchemeContrast == .increased ? 0.95 : 0.78
        return RascSurfacePalette.border(for: colorScheme)
            .opacity(isHovered ? hoverOpacity : baseOpacity)
    }

    private var borderLineWidth: CGFloat {
        if isSelected || colorSchemeContrast == .increased {
            return 1
        }
        return 0.75
    }
}

private struct HomeNoteCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.94 : 1)
    }
}

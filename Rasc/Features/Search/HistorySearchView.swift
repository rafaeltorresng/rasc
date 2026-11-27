import Observation
import SwiftUI

struct HistorySearchInputField: View {
    @Bindable var session: ScratchpadSession
    @State private var isFocused = false
    @Environment(\.noteTextSize) private var noteTextSize

    var body: some View {
        RascTransientInputShell(isFocused: isFocused) {
            HStack(spacing: 8) {
                RascTransientInputTextField(
                    text: $session.searchQuery,
                    isFocused: $isFocused,
                    focusRequest: session.searchFocusRequest,
                    placeholder: "Search thoughts…",
                    accessibilityLabel: "Search thoughts",
                    fontSize: noteTextSize.points(15),
                    onCommand: handleSearchCommand
                )
                if !session.searchQuery.isEmpty {
                    RascClearInputButton(label: "Clear search") {
                        session.searchQuery = ""
                        session.requestSearchFocus()
                    }
                }
            }
        }
        .onChange(of: session.searchQuery) {
            session.scheduleSearch()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Search thoughts")
    }

    private func handleSearchCommand(_ command: RascTransientFieldCommand) {
        switch command {
        case .moveUp:
            session.moveSearchSelection(by: -1)
        case .moveDown:
            session.moveSearchSelection(by: 1)
        case .execute:
            Task {
                _ = try? await session.openSelectedSearchResult()
            }
        case .close:
            session.closeSearch()
        }
    }
}

struct HistorySearchView: View {
    @Bindable var session: ScratchpadSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.rascPalette) private var palette
    @Environment(\.noteTextSize) private var noteTextSize
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    var body: some View {
        VStack(spacing: 0) {
            HistorySearchHeader(session: session)

            searchBody
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            if session.hasMoreSearchResults {
                Text("Search more specifically, or browse Home.")
                    .font(.caption)
                    .foregroundStyle(palette.secondaryText(for: colorScheme))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, RascSurfaceLayout.horizontalInset)
                    .padding(.vertical, 10)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onExitCommand {
            session.closeSearch()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Search thoughts")
    }

    @ViewBuilder
    private var searchBody: some View {
        Group {
            if let searchErrorMessage = session.searchErrorMessage {
                quietStateLabel(searchErrorMessage)
            } else if session.searchQuery.isEmpty, !session.searchResults.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    recentSectionHeader
                    resultList
                }
            } else if session.searchResults.isEmpty {
                if session.searchQuery.isEmpty {
                    quietStateLabel("No previous thoughts.")
                } else {
                    quietStateLabel("No thoughts found.")
                }
            } else {
                resultList
            }
        }
        .padding(.horizontal, RascSurfaceLayout.horizontalInset)
    }

    private var recentSectionHeader: some View {
        Text("Recent")
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(palette.metadataText(for: colorScheme))
            .accessibilityAddTraits(.isHeader)
    }

    private func quietStateLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(palette.secondaryText(for: colorScheme))
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel(text)
    }

    private var resultList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: RascSurfaceLayout.listRowSpacing) {
                    ForEach(Array(session.searchResults.enumerated()), id: \.element.id) { index, note in
                        Button {
                            session.selectSearchResult(at: index)
                            openSelectedResult()
                        } label: {
                            resultRow(note, isSelected: index == session.selectedSearchIndex)
                        }
                        .buttonStyle(.plain)
                        .id(note.id)
                        .accessibilityLabel(resultAccessibilityLabel(for: note))
                        .accessibilityHint(index == session.selectedSearchIndex ? "Press Return to open" : "")
                        .accessibilityAddTraits(index == session.selectedSearchIndex ? .isSelected : [])
                    }
                }
                .animation(
                    RascMotion.selection(reduceMotion: reduceMotion),
                    value: session.selectedSearchIndex
                )
            }
            .clipShape(Rectangle())
            .onChange(of: session.selectedSearchIndex) { _, index in
                guard session.searchResults.indices.contains(index) else { return }
                let note = session.searchResults[index]
                proxy.scrollTo(note.id)
                RascAccessibility.announce(note.displayTitle)
            }
        }
    }

    private var matchMark: Color {
        palette.searchMark(for: colorScheme, increasedContrast: colorSchemeContrast == .increased)
    }

    private func resultRow(_ note: Note, isSelected: Bool) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(RascSearchMatch.highlighted(note.displayTitle, query: session.searchQuery, mark: matchMark, tokenStartOnly: true, underline: palette.preset == .custom))
                    .font(.system(size: noteTextSize.points(RascSurfaceMetrics.searchTitleFontSize), weight: .medium))
                    .foregroundStyle(palette.noteText(for: colorScheme))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                if let snippet = note.retrievalSnippet(matching: session.searchQuery) {
                    Text(RascSearchMatch.highlighted(snippet, query: session.searchQuery, mark: matchMark, tokenStartOnly: true, underline: palette.preset == .custom))
                        .font(.system(size: noteTextSize.points(RascSurfaceMetrics.searchSnippetFontSize)))
                        .foregroundStyle(palette.noteText(for: colorScheme, fallback: palette.secondaryText(for: colorScheme)))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 6) {
                HStack(spacing: 5) {
                    if note.origin == .dictation {
                        Image(systemName: "mic")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(palette.metadataText(for: colorScheme))
                            .accessibilityLabel("Dictated")
                    }
                    if note.isKept {
                        Text("Kept")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(palette.metadataText(for: colorScheme))
                    }
                }

                Text(HomeNoteTimestampFormatter.format(note.updatedAt, calendar: .current, now: .now))
                    .font(.system(size: RascSurfaceMetrics.searchTimestampFontSize))
                    .monospacedDigit()
                    .foregroundStyle(palette.metadataText(for: colorScheme))
                    .lineLimit(1)

                if isSelected {
                    RascKeyboardActionHint(shortcut: "↵", title: "Open")
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 2)))
                }
            }
        }
        .rascTransientListRow(
            isSelected: isSelected,
            minHeight: RascSurfaceLayout.searchRowMinHeight
        )
    }

    private func resultAccessibilityLabel(for note: Note) -> String {
        var components = [note.displayTitle]
        if note.isKept {
            components.append("Kept")
        }
        if note.origin == .dictation {
            components.append("Dictated")
        }
        if let snippet = note.retrievalSnippet(matching: session.searchQuery) {
            components.append(snippet)
        }
        components.append(HomeNoteTimestampFormatter.format(note.updatedAt, calendar: .current, now: .now))
        return components.joined(separator: ", ")
    }

    private func openSelectedResult() {
        Task {
            _ = try? await session.openSelectedSearchResult()
        }
    }
}

private struct HistorySearchHeader: View {
    @Bindable var session: ScratchpadSession

    var body: some View {
        RascSurfaceInputHeader {
            HistorySearchInputField(session: session)
        }
        .padding(.bottom, RascSurfaceLayout.transientHeaderBodyGap)
    }
}

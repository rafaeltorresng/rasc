import Observation
import SwiftUI

struct HistorySearchInputField: View {
    @Bindable var session: ScratchpadSession
    @State private var isFocused = false

    var body: some View {
        RascTransientInputShell(isFocused: isFocused) {
            RascTransientInputTextField(
                text: $session.searchQuery,
                isFocused: $isFocused,
                focusRequest: session.searchFocusRequest,
                placeholder: "Search thoughts…",
                accessibilityLabel: "Search thoughts",
                onCommand: handleSearchCommand
            )
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
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            HistorySearchHeader(session: session)

            searchBody
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            if session.hasMoreSearchResults {
                Text("Showing 12 recent thoughts. Search more specifically, or browse Home.")
                    .font(.caption)
                    .foregroundStyle(RascSurfacePalette.secondaryText(for: colorScheme))
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
            .foregroundStyle(RascSurfacePalette.metadataText(for: colorScheme))
            .accessibilityAddTraits(.isHeader)
    }

    private func quietStateLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(RascSurfacePalette.secondaryText(for: colorScheme))
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
                proxy.scrollTo(session.searchResults[index].id)
            }
        }
    }

    private func resultRow(_ note: Note, isSelected: Bool) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(note.displayTitle)
                    .font(.system(size: RascSurfaceMetrics.searchTitleFontSize, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                if let snippet = note.retrievalSnippet(matching: session.searchQuery) {
                    Text(snippet)
                        .font(.system(size: RascSurfaceMetrics.searchSnippetFontSize))
                        .foregroundStyle(RascSurfacePalette.secondaryText(for: colorScheme))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 6) {
                if note.isKept {
                    Text("Kept")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(RascSurfacePalette.metadataText(for: colorScheme))
                }

                Text(note.updatedAt, style: .relative)
                    .font(.system(size: RascSurfaceMetrics.searchTimestampFontSize))
                    .foregroundStyle(RascSurfacePalette.metadataText(for: colorScheme))
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
        if let snippet = note.retrievalSnippet(matching: session.searchQuery) {
            components.append(snippet)
        }
        components.append(note.updatedAt.formatted(.relative(presentation: .named)))
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
        RascSurfaceOrbHeaderRow(orbState: .searching) {
            HistorySearchInputField(session: session)
                .offset(y: -RascSurfaceLayout.searchFieldOrbVerticalOffset)
        }
        .padding(.bottom, RascSurfaceLayout.transientHeaderBodyGap)
    }
}

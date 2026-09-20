import SwiftUI

struct HomeView: View {
    @Bindable var session: HomeSession
    let onOpenNote: (UUID) -> Void
    let onNewScratch: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(spacing: 0) {
            actionZone
                .padding(.horizontal, 28)
                .padding(.top, 20)
                .padding(.bottom, 18)
                .background {
                    RascSurfacePalette.canvas(for: colorScheme)
                }

            ScrollViewReader { scrollProxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        sectionHeader

                        contentBody
                    }
                    .padding(.horizontal, 28)
                    .padding(.bottom, 28)
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

    private var actionZone: some View {
        HStack(alignment: .center, spacing: 16) {
            HStack(spacing: 10) {
                RascOrb(state: session.orbState, size: .inline, decorative: true)
                    .frame(width: RascSurfaceLayout.orbSize, height: RascSurfaceLayout.orbSize)

                Text("Rasc")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Rasc")

            HomeSearchField(text: $session.searchQuery)
            .frame(maxWidth: 360)

            Spacer(minLength: 12)

            Button(action: onNewScratch) {
                Label("New Scratch", systemImage: "plus")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(RascSurfacePalette.actionAccent(for: colorScheme))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("New Scratch")

            RascSettingsLink {
                Image(systemName: "gearshape")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
            .help("Settings")
        }
    }

    private var sectionHeader: some View {
        Text("Your notes")
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(.primary)
            .accessibilityAddTraits(.isHeader)
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
        VStack(alignment: .leading, spacing: 14) {
            Text("Nothing here yet.")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)

            Text("Your notes will appear here as you use Rasc.")
                .font(.system(size: 13))
                .foregroundStyle(.tertiary)

            Button(action: onNewScratch) {
                Text("New Scratch")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(RascSurfacePalette.actionAccent(for: colorScheme))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("New Scratch")
        }
        .padding(.top, 8)
    }

    private var chronologicalGrid: some View {
        VStack(alignment: .leading, spacing: 24) {
            ForEach(session.temporalGroups) { group in
                VStack(alignment: .leading, spacing: 14) {
                    Text(group.section.rawValue)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .accessibilityAddTraits(.isHeader)

                    noteGrid(for: group.notes)
                }
            }
        }
        .animation(RascMotion.bodyContentAnimation(reduceMotion: reduceMotion), value: session.temporalGroups.map(\.id))
    }

    private var searchResultsGrid: some View {
        noteGrid(for: session.searchResults)
            .animation(RascMotion.bodyContentAnimation(reduceMotion: reduceMotion), value: session.searchResults.map(\.id))
    }

    private func noteGrid(for notes: [Note]) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 240, maximum: 330), spacing: 16)],
            alignment: .leading,
            spacing: 16
        ) {
            ForEach(notes, id: \.id) { note in
                HomeNoteCard(
                    note: note,
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
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel(text)
    }

    private func openSelectedNote() {
        guard let note = session.selectedNote() else { return }
        onOpenNote(note.id)
    }
}

private struct HomeSearchField: View {
    @Binding var text: String
    @FocusState private var isFocused: Bool

    var body: some View {
        RascTransientInputShell(isFocused: isFocused) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.tertiary)

                TextField("Search notes…", text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .focused($isFocused)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Search notes")
    }
}

private struct HomeNoteCard: View {
    let note: Note
    let isSelected: Bool
    let timestamp: String
    let onOpen: () -> Void
    let onSelect: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    private let cornerRadius: CGFloat = 15

    var body: some View {
        Button {
            onSelect()
            onOpen()
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                Text(note.displayTitle)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let snippet = note.displayRetrievalSnippet ?? note.displaySnippet {
                    Text(snippet)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Spacer(minLength: 0)

                Text(timestamp)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(17)
            .frame(maxWidth: .infinity, minHeight: 148, alignment: .topLeading)
            .background(cardBackground)
            .overlay(cardBorder)
        }
        .buttonStyle(.plain)
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
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(RascSurfacePalette.raisedFill(for: colorScheme))
            .shadow(
                color: .black.opacity(isHovered ? 0.1 : 0.06),
                radius: isHovered ? 10 : 6,
                y: isHovered ? 4 : 2
            )
    }

    @ViewBuilder
    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(
                isSelected
                    ? RascSurfacePalette.selectionStroke(for: colorScheme)
                    : RascSurfacePalette.border(for: colorScheme).opacity(isHovered ? 0.9 : 0.65),
                lineWidth: isSelected || colorSchemeContrast == .increased ? 1 : 0.8
            )
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(RascSurfacePalette.selectionFill(for: colorScheme))
                }
            }
    }
}

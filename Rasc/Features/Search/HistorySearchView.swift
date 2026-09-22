import AppKit
import Observation
import SwiftUI

enum HistorySearchCommand: Equatable {
    case moveUp
    case moveDown
    case openSelection
    case closeSearch

    init?(commandSelector: Selector) {
        switch commandSelector {
        case #selector(NSResponder.moveUp(_:)):
            self = .moveUp
        case #selector(NSResponder.moveDown(_:)):
            self = .moveDown
        case #selector(NSResponder.insertNewline(_:)):
            self = .openSelection
        case #selector(NSResponder.cancelOperation(_:)):
            self = .closeSearch
        default:
            return nil
        }
    }
}

struct HistorySearchTextField: NSViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    let focusRequest: Int
    let onCommand: (HistorySearchCommand) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField()
        textField.delegate = context.coordinator
        textField.isBordered = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.font = .systemFont(ofSize: 15)
        textField.placeholderString = "Find a note…"
        textField.setAccessibilityLabel("Find a note")
        textField.cell?.usesSingleLineMode = true
        textField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return textField
    }

    func updateNSView(_ textField: NSTextField, context: Context) {
        context.coordinator.parent = self

        if textField.stringValue != text {
            textField.stringValue = text
        }

        context.coordinator.focus(textField, for: focusRequest)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: HistorySearchTextField
        private var fulfilledFocusRequest: Int?

        init(parent: HistorySearchTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else { return }
            parent.text = textField.stringValue
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            parent.isFocused = true
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            parent.isFocused = false
        }

        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            guard let command = HistorySearchCommand(commandSelector: commandSelector) else {
                return false
            }

            parent.onCommand(command)
            return true
        }

        func focus(_ textField: NSTextField, for request: Int) {
            guard fulfilledFocusRequest != request else { return }

            DispatchQueue.main.async { [weak self, weak textField] in
                guard let self, let textField, let window = textField.window else { return }
                window.makeFirstResponder(textField)
                fulfilledFocusRequest = request
                parent.isFocused = window.firstResponder === textField.currentEditor()
                    || window.firstResponder === textField
            }
        }
    }
}

struct HistorySearchInputField: View {
    @Bindable var session: ScratchpadSession
    @State private var isFocused = false

    var body: some View {
        RascTransientInputShell(isFocused: isFocused) {
            HistorySearchTextField(
                text: $session.searchQuery,
                isFocused: $isFocused,
                focusRequest: session.searchFocusRequest,
                onCommand: handleSearchCommand
            )
        }
        .onChange(of: session.searchQuery) {
            session.scheduleSearch()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Find a note")
    }

    private func handleSearchCommand(_ command: HistorySearchCommand) {
        switch command {
        case .moveUp:
            session.moveSearchSelection(by: -1)
        case .moveDown:
            session.moveSearchSelection(by: 1)
        case .openSelection:
            Task {
                _ = try? await session.openSelectedSearchResult()
            }
        case .closeSearch:
            session.closeSearch()
        }
    }
}

struct HistorySearchView: View {
    @Bindable var session: ScratchpadSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            HistorySearchHeader(session: session)

            searchBody
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onExitCommand {
            session.closeSearch()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("History and search")
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
                    quietStateLabel("No previous notes.")
                } else {
                    quietStateLabel("No notes found.")
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
            .foregroundStyle(.tertiary)
            .accessibilityAddTraits(.isHeader)
    }

    private func quietStateLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
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
                proxy.scrollTo(session.searchResults[index].id, anchor: .center)
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

                if let snippet = note.displayRetrievalSnippet {
                    Text(snippet)
                        .font(.system(size: RascSurfaceMetrics.searchSnippetFontSize))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 6) {
                if note.isKept {
                    Text("Kept")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }

                Text(note.updatedAt, style: .relative)
                    .font(.system(size: RascSurfaceMetrics.searchTimestampFontSize))
                    .foregroundStyle(.tertiary)
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
        if let snippet = note.displayRetrievalSnippet {
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

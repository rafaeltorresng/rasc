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
        textField.placeholderString = "Search notes…"
        textField.setAccessibilityLabel("Search notes")
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
            }
        }
    }
}

struct HistorySearchInputField: View {
    @Bindable var session: ScratchpadSession

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            HistorySearchTextField(
                text: $session.searchQuery,
                focusRequest: session.searchFocusRequest,
                onCommand: handleSearchCommand
            )
            .frame(maxWidth: .infinity)
            .onChange(of: session.searchQuery) {
                session.scheduleSearch()
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Search notes")
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
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if let searchErrorMessage = session.searchErrorMessage {
                ContentUnavailableView(
                    "Search unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: Text(searchErrorMessage)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if session.searchResults.isEmpty {
                ContentUnavailableView(
                    session.searchQuery.isEmpty ? "No previous notes" : "No matching notes",
                    systemImage: "text.magnifyingglass"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                resultList
            }
        }
        .padding(.top, RascSurfaceMetrics.searchContentTopInset)
        .padding(.bottom, RascSurfaceMetrics.editorBottomPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .scratchpadOverlayBackground()
        .ignoresSafeArea(edges: .top)
        .onExitCommand {
            session.closeSearch()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("History and search")
    }

    private var resultList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: RascSurfaceMetrics.commandRowSpacing) {
                    ForEach(Array(session.searchResults.enumerated()), id: \.element.id) { index, note in
                        Button {
                            session.selectSearchResult(at: index)
                            openSelectedResult()
                        } label: {
                            resultRow(note, isSelected: index == session.selectedSearchIndex)
                        }
                        .buttonStyle(.plain)
                        .id(note.id)
                    }
                }
                .padding(.horizontal, RascSurfaceMetrics.editorHorizontalPadding)
            }
            .onChange(of: session.selectedSearchIndex) { _, index in
                guard session.searchResults.indices.contains(index) else { return }
                proxy.scrollTo(session.searchResults[index].id, anchor: .center)
            }
        }
    }

    private func resultRow(_ note: Note, isSelected: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(note.displayTitle)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)

                if let snippet = note.displaySnippet {
                    Text(snippet)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            Text(note.updatedAt, style: .relative)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, RascSurfaceMetrics.commandRowVerticalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(isSelected ? RascSurfacePalette.selectionFill(for: colorScheme) : Color.clear)
        )
    }

    private func openSelectedResult() {
        Task {
            _ = try? await session.openSelectedSearchResult()
        }
    }
}

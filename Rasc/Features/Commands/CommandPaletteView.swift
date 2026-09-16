import AppKit
import SwiftUI

enum CommandPaletteCommand: Equatable {
    case moveUp
    case moveDown
    case executeSelection
    case closePalette

    init?(commandSelector: Selector) {
        switch commandSelector {
        case #selector(NSResponder.moveUp(_:)):
            self = .moveUp
        case #selector(NSResponder.moveDown(_:)):
            self = .moveDown
        case #selector(NSResponder.insertNewline(_:)):
            self = .executeSelection
        case #selector(NSResponder.cancelOperation(_:)):
            self = .closePalette
        default:
            return nil
        }
    }
}

struct CommandPaletteTextField: NSViewRepresentable {
    @Binding var text: String
    let focusRequest: Int
    let onCommand: (CommandPaletteCommand) -> Void

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
        textField.placeholderString = "Type a command…"
        textField.cell?.usesSingleLineMode = true
        textField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textField.setAccessibilityLabel("Command palette")
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
        var parent: CommandPaletteTextField
        private var fulfilledFocusRequest: Int?

        init(parent: CommandPaletteTextField) {
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
            guard let command = CommandPaletteCommand(commandSelector: commandSelector) else {
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

struct CommandPaletteView: View {
    @Bindable var session: ScratchpadSession
    let onExecute: (PaletteCommand) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "command")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)

                CommandPaletteTextField(
                    text: $session.commandPaletteQuery,
                    focusRequest: session.commandPaletteFocusRequest,
                    onCommand: handlePaletteCommand
                )
                .frame(maxWidth: .infinity)
                .onChange(of: session.commandPaletteQuery) {
                    session.refreshCommandPalette()
                }
            }
            .padding(.horizontal, 20)
            .frame(height: 52)

            Divider()

            if session.filteredCommands.isEmpty {
                ContentUnavailableView(
                    "No matching commands",
                    systemImage: "command"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                commandList
            }
        }
        .transientSurfaceBackground()
        .onExitCommand {
            session.closeCommandPalette()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Command palette")
    }

    private var commandList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(Array(session.filteredCommands.enumerated()), id: \.element.id) { index, command in
                        Button {
                            session.selectCommand(at: index)
                            executeSelectedCommand()
                        } label: {
                            commandRow(command, isSelected: index == session.selectedCommandIndex)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(command.title)
                        .accessibilityHint(command.accessibilityHint)
                        .accessibilityAddTraits(index == session.selectedCommandIndex ? .isSelected : [])
                        .id(command.id)
                    }
                }
                .padding(8)
            }
            .onChange(of: session.selectedCommandIndex) { _, index in
                guard session.filteredCommands.indices.contains(index) else { return }
                proxy.scrollTo(session.filteredCommands[index].id, anchor: .center)
            }
        }
    }

    private func commandRow(_ command: PaletteCommand, isSelected: Bool) -> some View {
        HStack(spacing: 12) {
            Text(command.title)
                .font(.system(size: 13, weight: .medium))
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(command.shortcutLabel)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(isSelected ? Color.accentColor.opacity(0.16) : Color.clear)
        )
    }

    private func executeSelectedCommand() {
        guard let command = session.selectedCommand() else { return }
        session.closeCommandPalette()
        onExecute(command)
    }

    private func handlePaletteCommand(_ command: CommandPaletteCommand) {
        switch command {
        case .moveUp:
            session.moveCommandSelection(by: -1)
        case .moveDown:
            session.moveCommandSelection(by: 1)
        case .executeSelection:
            executeSelectedCommand()
        case .closePalette:
            session.closeCommandPalette()
        }
    }
}

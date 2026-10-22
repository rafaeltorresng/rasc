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

struct CommandPaletteKeyboardHandler: NSViewRepresentable {
    let focusRequest: Int
    let onCommand: (CommandPaletteCommand) -> Void
    let onInsert: (String) -> Void
    let onDelete: () -> Void

    func makeNSView(context: Context) -> CommandPaletteKeyView {
        let view = CommandPaletteKeyView()
        view.focusRingType = .none
        return view
    }

    func updateNSView(_ nsView: CommandPaletteKeyView, context: Context) {
        nsView.onCommand = onCommand
        nsView.onInsert = onInsert
        nsView.onDelete = onDelete
        nsView.claimFocus(for: focusRequest)
    }
}

@MainActor
final class CommandPaletteKeyView: NSView {
    var onCommand: ((CommandPaletteCommand) -> Void)?
    var onInsert: ((String) -> Void)?
    var onDelete: (() -> Void)?
    private var fulfilledFocusRequest = -1

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers.contains(.command) || modifiers.contains(.control) {
            return
        }
        interpretKeyEvents([event])
    }

    override func insertText(_ insertString: Any) {
        let string: String
        if let value = insertString as? String {
            string = value
        } else if let value = insertString as? NSAttributedString {
            string = value.string
        } else {
            return
        }
        guard !string.isEmpty else { return }
        guard string.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else { return }
        onInsert?(string)
    }

    override func deleteBackward(_ sender: Any?) {
        onDelete?()
    }

    override func moveUp(_ sender: Any?) {
        onCommand?(.moveUp)
    }

    override func moveDown(_ sender: Any?) {
        onCommand?(.moveDown)
    }

    override func insertNewline(_ sender: Any?) {
        onCommand?(.executeSelection)
    }

    override func cancelOperation(_ sender: Any?) {
        onCommand?(.closePalette)
    }

    func claimFocus(for request: Int) {
        guard fulfilledFocusRequest != request else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self, let window else { return }
            window.makeFirstResponder(self)
            fulfilledFocusRequest = request
        }
    }
}

struct CommandPaletteView: View {
    @Bindable var session: ScratchpadSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var globalShortcutRevision = 0
    let onExecute: (PaletteCommand) -> Void

    var body: some View {
        let _ = globalShortcutRevision
        VStack(spacing: 0) {
            paletteHeader

            ScrollView {
                commandList
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            CommandPaletteKeyboardHandler(
                focusRequest: session.commandPaletteKeyFocusRequest,
                onCommand: handlePaletteCommand,
                onInsert: { session.insertCommandPaletteText($0) },
                onDelete: { session.deleteCommandPaletteText() }
            )
        }
        .onGlobalShortcutChange {
            globalShortcutRevision += 1
            session.refreshCommandsForShortcutChange()
        }
        .onExitCommand {
            session.closeCommandPalette()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Command palette")
    }

    private var paletteHeader: some View {
        HStack(alignment: .center, spacing: RascSurfaceLayout.orbToAccessoryGap) {
            RascOrb(state: .note, size: .inline, decorative: true)
                .frame(width: RascSurfaceLayout.orbSize, height: RascSurfaceLayout.orbSize)

            Text(session.commandPaletteQuery.isEmpty ? "Commands" : session.commandPaletteQuery)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(session.commandPaletteQuery.isEmpty ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel(session.commandPaletteQuery.isEmpty ? "Commands" : "Command filter")
                .accessibilityValue(session.commandPaletteQuery)
        }
        .padding(.horizontal, RascSurfaceLayout.horizontalInset)
        .padding(.top, RascSurfaceLayout.topInset)
        .padding(.bottom, RascSurfaceLayout.transientHeaderBodyGap)
    }

    private var commandList: some View {
        VStack(spacing: RascSurfaceLayout.listRowSpacing) {
            if session.filteredCommands.isEmpty {
                Text("No matching commands.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel("No matching commands")
            } else {
                ForEach(Array(session.filteredCommands.enumerated()), id: \.element.id) { index, command in
                    Button {
                        session.selectCommand(at: index)
                        execute(command)
                    } label: {
                        commandRow(command, isSelected: index == session.selectedCommandIndex)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(command.title)
                    .accessibilityHint(command.accessibilityHint)
                    .accessibilityAddTraits(index == session.selectedCommandIndex ? .isSelected : [])
                }
            }
        }
        .padding(.horizontal, RascSurfaceLayout.horizontalInset)
        .animation(
            RascMotion.selection(reduceMotion: reduceMotion),
            value: session.selectedCommandIndex
        )
    }

    private func commandRow(_ command: PaletteCommand, isSelected: Bool) -> some View {
        HStack(spacing: 12) {
            Text(command.title)
                .font(.system(size: RascSurfaceMetrics.searchTitleFontSize, weight: .medium))
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(command.displayedShortcutLabel())
                .font(.system(size: RascSurfaceMetrics.searchTimestampFontSize, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
        .rascTransientListRow(
            isSelected: isSelected,
            minHeight: RascSurfaceLayout.commandRowMinHeight
        )
    }

    private func execute(_ command: PaletteCommand) {
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
            guard let selected = session.selectedCommand() else { return }
            execute(selected)
        case .closePalette:
            session.closeCommandPalette()
        }
    }
}

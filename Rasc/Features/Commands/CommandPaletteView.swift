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

    func makeNSView(context: Context) -> CommandPaletteKeyView {
        let view = CommandPaletteKeyView()
        view.focusRingType = .none
        return view
    }

    func updateNSView(_ nsView: CommandPaletteKeyView, context: Context) {
        nsView.onCommand = onCommand
        nsView.claimFocus(for: focusRequest)
    }
}

@MainActor
final class CommandPaletteKeyView: NSView {
    var onCommand: ((CommandPaletteCommand) -> Void)?
    private var fulfilledFocusRequest = -1

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        interpretKeyEvents([event])
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
    @Environment(\.colorScheme) private var colorScheme
    let onExecute: (PaletteCommand) -> Void

    var body: some View {
        commandList
            .padding(.top, RascSurfaceMetrics.commandPaletteContentTopInset)
            .padding(.bottom, RascSurfaceMetrics.editorBottomPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .scratchpadOverlayBackground()
            .ignoresSafeArea(edges: .top)
            .background {
                CommandPaletteKeyboardHandler(
                    focusRequest: session.commandPaletteKeyFocusRequest,
                    onCommand: handlePaletteCommand
                )
            }
            .onExitCommand {
                session.closeCommandPalette()
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Command palette")
    }

    private var commandList: some View {
        VStack(spacing: RascSurfaceMetrics.commandRowSpacing) {
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
        .padding(.horizontal, RascSurfaceMetrics.editorHorizontalPadding)
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
        .padding(.horizontal, 10)
        .padding(.vertical, RascSurfaceMetrics.commandRowVerticalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(isSelected ? RascSurfacePalette.selectionFill(for: colorScheme) : Color.clear)
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

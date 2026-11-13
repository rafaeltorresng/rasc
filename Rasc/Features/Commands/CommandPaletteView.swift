import SwiftUI

struct CommandPaletteView: View {
    @Bindable var session: ScratchpadSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var isFocused = false
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
        RascSurfaceOrbHeaderRow(orbState: .note) {
            RascTransientInputShell(isFocused: isFocused) {
                RascTransientInputTextField(
                    text: $session.commandPaletteQuery,
                    isFocused: $isFocused,
                    focusRequest: session.commandPaletteKeyFocusRequest,
                    placeholder: "Type a command…",
                    accessibilityLabel: "Commands",
                    onCommand: handlePaletteCommand
                )
            }
            .offset(y: -RascSurfaceLayout.searchFieldOrbVerticalOffset)
        }
        .padding(.bottom, RascSurfaceLayout.transientHeaderBodyGap)
    }

    private var commandList: some View {
        VStack(spacing: RascSurfaceLayout.listRowSpacing) {
            if session.filteredCommands.isEmpty {
                Text("No matching commands.")
                    .font(.system(size: 13))
                    .foregroundStyle(RascSurfacePalette.secondaryText(for: colorScheme))
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
                    .accessibilityHint(
                        command == .discardNote && session.destructiveConfirmationRequested
                            ? "Press Return again to discard this note"
                            : command.accessibilityHint
                    )
                    .accessibilityAddTraits(index == session.selectedCommandIndex ? .isSelected : [])
                }
            }
        }
        .padding(.horizontal, RascSurfaceLayout.horizontalInset)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .animation(
            RascMotion.selection(reduceMotion: reduceMotion),
            value: session.selectedCommandIndex
        )
    }

    private func commandRow(_ command: PaletteCommand, isSelected: Bool) -> some View {
        HStack(spacing: 12) {
            Text(command.title)
                .font(.system(size: RascSurfaceMetrics.searchTitleFontSize, weight: .medium))
                .foregroundStyle(
                    command == .discardNote
                        ? RascSurfacePalette.destructiveText(for: colorScheme)
                        : Color.primary
                )
                .frame(maxWidth: .infinity, alignment: .leading)

            if command == .discardNote, session.destructiveConfirmationRequested {
                Text("↵ again to discard")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(RascSurfacePalette.destructiveText(for: colorScheme))
            } else {
                Text(command.displayedShortcutLabel())
                    .font(.system(size: RascSurfaceMetrics.searchTimestampFontSize, design: .monospaced))
                    .foregroundStyle(RascSurfacePalette.metadataText(for: colorScheme))
            }
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

    private func handlePaletteCommand(_ command: RascTransientFieldCommand) {
        switch command {
        case .moveUp:
            session.moveCommandSelection(by: -1)
        case .moveDown:
            session.moveCommandSelection(by: 1)
        case .execute:
            switch session.attemptSelectedCommandExecution() {
            case .allowed:
                if let commandToRun = session.selectedCommand() {
                    execute(commandToRun)
                }
            case .requiresConfirmation:
                // The Discard row shows a deliberate confirmation; the next Return executes.
                break
            }
        case .close:
            session.closeCommandPalette()
        }
    }
}

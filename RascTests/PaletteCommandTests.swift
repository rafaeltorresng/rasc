import KeyboardShortcuts
import Testing
@testable import Rasc

@MainActor
struct PaletteCommandTests {
    @Test
    func emptyQueryReturnsAvailableCommands() {
        let commands = PaletteCommand.availableCommands(
            isKept: false,
            hasPersistableContent: true,
            canPerformCompletion: true
        )
        #expect(PaletteCommand.filtered(by: "", in: commands) == commands)
    }

    @Test
    func fuzzyFilterMatchesTitles() {
        let commands = PaletteCommand.availableCommands(
            isKept: false,
            hasPersistableContent: true,
            canPerformCompletion: true
        )
        #expect(PaletteCommand.filtered(by: "sett", in: commands) == [.settings])
        #expect(PaletteCommand.filtered(by: "find", in: commands) == [.findNote])
        #expect(PaletteCommand.filtered(by: "home", in: commands) == [.openHome])
        #expect(PaletteCommand.filtered(by: "keep", in: commands) == [.keep])
        #expect(PaletteCommand.filtered(by: "keyboard", in: commands) == [.keyboardShortcuts])
        #expect(PaletteCommand.filtered(by: "shortcuts", in: commands) == [.keyboardShortcuts])
    }

    @Test
    func openHomeKeepsTheDocumentedDefaultAlias() {
        #expect(PaletteCommand.openHome.shortcutLabel == "⌘⌥\\")
    }

    @Test
    func openHomeDisplayFollowsTheStoredShortcut() {
        let original = KeyboardShortcuts.getShortcut(for: .toggleHome)
        defer { KeyboardShortcuts.setShortcut(original, for: .toggleHome) }

        let custom = KeyboardShortcuts.Shortcut(.f6, modifiers: [.command, .option, .control])
        KeyboardShortcuts.setShortcut(custom, for: .toggleHome)

        #expect(PaletteCommand.openHome.displayedShortcutLabel() == custom.description)
        #expect(PaletteCommand.openHome.displayedShortcutLabel() == GlobalShortcutFormatting.currentHomeShortcutDisplay())
    }

    @Test
    func insideRascListsRealShortcutsWithoutEditableGlobals() {
        let titles = RascShortcutCatalog.insideRasc.map(\.title)
        #expect(titles == [
            "New Scratch",
            "Refine",
            "Keep",
            "Search thoughts",
            "Command Palette",
            "Settings",
            "Hide Scratchpad",
            "Keep original",
            "Accept suggestion",
            "Quit Rasc"
        ])
        #expect(RascShortcutCatalog.insideRasc.allSatisfy { !$0.shortcut.isEmpty })
        #expect(!titles.contains("Unkeep"))
        #expect(!titles.contains("Copy Note"))
        #expect(!titles.contains("Toggle Scratchpad"))
        #expect(!titles.contains("Toggle Home"))
    }

    @Test
    func keptNoteShowsUnkeepInsteadOfKeep() {
        let commands = PaletteCommand.availableCommands(
            isKept: true,
            hasPersistableContent: true,
            canPerformCompletion: true
        )
        #expect(commands.contains(.unkeep))
        #expect(!commands.contains(.keep))
    }
}

import Testing
@testable import Rasc

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
    }

    @Test
    func openHomeShowsToggleShortcut() {
        #expect(PaletteCommand.openHome.shortcutLabel == "⌘⌥\\")
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

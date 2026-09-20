import Testing
@testable import Rasc

struct PaletteCommandTests {
    @Test
    func emptyQueryReturnsAllCommands() {
        #expect(PaletteCommand.filtered(by: "") == PaletteCommand.allCases)
    }

    @Test
    func fuzzyFilterMatchesTitles() {
        #expect(PaletteCommand.filtered(by: "sett") == [.settings])
        #expect(PaletteCommand.filtered(by: "find") == [.findNote])
        #expect(PaletteCommand.filtered(by: "home") == [.openHome])
    }
}

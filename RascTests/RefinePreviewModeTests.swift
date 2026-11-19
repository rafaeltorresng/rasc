import Testing
@testable import Rasc

@Suite
struct RefinePreviewModeTests {
    @Test
    func allCasesAreInDisplayOrder() {
        #expect(ScratchpadSession.RefinePreviewMode.allCases == [.suggested, .changes, .original])
    }

    @Test
    func steppingRightWalksTheSequenceAndClampsAtOriginal() {
        var mode = ScratchpadSession.RefinePreviewMode.suggested
        mode = mode.stepped(by: 1)
        #expect(mode == .changes)
        mode = mode.stepped(by: 1)
        #expect(mode == .original)
        mode = mode.stepped(by: 1)
        #expect(mode == .original)
    }

    @Test
    func steppingLeftWalksBackwardsAndClampsAtSuggested() {
        var mode = ScratchpadSession.RefinePreviewMode.original
        mode = mode.stepped(by: -1)
        #expect(mode == .changes)
        mode = mode.stepped(by: -1)
        #expect(mode == .suggested)
        mode = mode.stepped(by: -1)
        #expect(mode == .suggested)
    }

    @Test
    func zeroStepIsStable() {
        #expect(ScratchpadSession.RefinePreviewMode.suggested.stepped(by: 0) == .suggested)
        #expect(ScratchpadSession.RefinePreviewMode.changes.stepped(by: 0) == .changes)
        #expect(ScratchpadSession.RefinePreviewMode.original.stepped(by: 0) == .original)
    }

    @Test
    func offsetsBeyondTheBoundaryClamp() {
        #expect(ScratchpadSession.RefinePreviewMode.suggested.stepped(by: -10) == .suggested)
        #expect(ScratchpadSession.RefinePreviewMode.suggested.stepped(by: 10) == .original)
        #expect(ScratchpadSession.RefinePreviewMode.original.stepped(by: -10) == .suggested)
        #expect(ScratchpadSession.RefinePreviewMode.original.stepped(by: 10) == .original)
    }
}

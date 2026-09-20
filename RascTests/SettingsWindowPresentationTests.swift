import AppKit
import Testing
@testable import Rasc

@Suite(.serialized)
@MainActor
struct SettingsWindowPresentationTests {
    @Test
    func configuresSwiftUISettingsWindowForFullscreenSpaces() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 320),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        _ = window.setFrameAutosaveName("com.apple.SwiftUI.Settings")

        SettingsWindowPresentation.configureIfNeeded(window)

        #expect(window.collectionBehavior.contains(.fullScreenAuxiliary))
        #expect(window.collectionBehavior.contains(.moveToActiveSpace))
    }

    @Test
    func ignoresNonSettingsWindows() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 320),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        _ = window.setFrameAutosaveName("scratchpadWindowFrame")

        SettingsWindowPresentation.configureIfNeeded(window)

        #expect(!window.collectionBehavior.contains(.fullScreenAuxiliary))
    }
}

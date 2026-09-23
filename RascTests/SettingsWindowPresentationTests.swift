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

        #expect(window.collectionBehavior == [.moveToActiveSpace, .fullScreenAuxiliary])
    }

    @Test
    func positionsSettingsWindowOnPresentationScreen() {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 420),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        _ = window.setFrameAutosaveName("com.apple.SwiftUI.Settings")
        window.setFrameOrigin(NSPoint(x: -2_000, y: -2_000))

        SettingsWindowPresentation.configureIfNeeded(window, reposition: true)

        let centeredOrigin = WindowFramePlacement.centeredOrigin(
            for: window.frame.size,
            in: screen.visibleFrame
        )
        #expect(abs(window.frame.origin.x - centeredOrigin.x) < 1)
        #expect(abs(window.frame.origin.y - centeredOrigin.y) < 1)
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

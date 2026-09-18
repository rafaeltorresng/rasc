import AppKit
import SwiftUI

@MainActor
final class OnboardingWindowController {
    private var window: NSWindow?
    private var preferredScreen: NSScreen?

    func show(
        coordinator: OnboardingCoordinator,
        on preferredScreen: NSScreen? = nil
    ) {
        self.preferredScreen = preferredScreen ?? activeScreen()

        let contentView = OnboardingView(coordinator: coordinator)
        let hostingController = NSHostingController(rootView: contentView)

        let window = self.window ?? makeWindow()
        window.contentViewController = hostingController
        center(window, on: self.preferredScreen)

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        self.window = window
    }

    func hide() {
        window?.orderOut(nil)
    }

    func close() {
        window?.close()
        window = nil
    }

    func resignKey() {
        window?.makeFirstResponder(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 520),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Rasc"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = true
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        return window
    }

    private func center(_ window: NSWindow, on screen: NSScreen?) {
        let targetScreen = screen ?? NSScreen.main ?? NSScreen.screens.first
        guard let visibleFrame = targetScreen?.visibleFrame else { return }

        let origin = WindowFramePlacement.centeredOrigin(
            for: window.frame.size,
            in: visibleFrame
        )
        window.setFrameOrigin(origin)
    }

    private func activeScreen() -> NSScreen? {
        if let frontmost = NSWorkspace.shared.frontmostApplication,
           frontmost.processIdentifier != NSRunningApplication.current.processIdentifier,
           let window = NSApp.windows.first(where: { $0.isVisible && $0.isKeyWindow }) {
            return window.screen
        }

        return NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
            ?? NSScreen.main
    }
}

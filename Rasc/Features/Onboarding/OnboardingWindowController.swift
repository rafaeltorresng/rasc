import AppKit
import SwiftUI

@MainActor
final class OnboardingWindowController {
    private var window: NSWindow?

    func show(coordinator: OnboardingCoordinator) {
        let contentView = OnboardingView(coordinator: coordinator)
        let hostingController = NSHostingController(rootView: contentView)

        let window = self.window ?? makeWindow()
        window.contentViewController = hostingController
        RascWindowPlacement.placeOnboarding(
            window: window,
            excludingProcessID: NSRunningApplication.current.processIdentifier
        )

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
            contentRect: NSRect(origin: .zero, size: RascWindowMetrics.onboarding),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Rasc"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = true
        window.minSize = RascWindowMetrics.onboarding
        window.maxSize = RascWindowMetrics.onboarding
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        return window
    }
}

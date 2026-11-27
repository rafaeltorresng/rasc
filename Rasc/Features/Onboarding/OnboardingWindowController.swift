import AppKit
import SwiftUI

@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var hostingController: NSHostingController<RascAppearanceView<OnboardingView>>?
    var onWindowClosedByUser: (() -> Void)?

    func show(coordinator: OnboardingCoordinator) {
        let contentView = RascAppearanceView { OnboardingView(coordinator: coordinator) }
        let window = self.window ?? makeWindow()

        // One hosting controller for the whole flow. Recreating it per step
        // renegotiates the preferred content size and moves the window.
        if let hostingController {
            hostingController.rootView = contentView
        } else {
            let controller = NSHostingController(rootView: contentView)
            // The SwiftUI view has an exact frame; AppKit must not resize the
            // window from a preferred content size on a step transition.
            controller.sizingOptions = []
            window.contentViewController = controller
            hostingController = controller
        }

        // Place once, when the window first appears. Later steps only change
        // content inside the same, centered frame.
        if !window.isVisible {
            RascWindowPlacement.placeOnboarding(
                window: window,
                excludingProcessID: NSRunningApplication.current.processIdentifier
            )
        }

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        self.window = window
    }

    func hide() {
        window?.orderOut(nil)
    }

    func close() {
        window?.orderOut(nil)
        window?.contentViewController = nil
        hostingController = nil
        window = nil
    }

    func resignKey() {
        window?.makeFirstResponder(nil)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        onWindowClosedByUser?()
        return false
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: RascWindowMetrics.onboarding),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.delegate = self
        window.title = "Rasc"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = true
        window.minSize = RascWindowMetrics.onboardingMinimum
        window.maxSize = RascWindowMetrics.onboardingMaximum
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        return window
    }
}

import AppKit
import SwiftUI

@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    let panel: NSPanel

    private let session: ScratchpadSession
    private var previousApplication: NSRunningApplication?

    init(repository: NoteRepository) {
        session = ScratchpadSession(repository: repository)
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 340),
            styleMask: [.titled, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        super.init()

        configurePanel()
        panel.contentViewController = NSHostingController(
            rootView: ScratchpadView(session: session) { [weak self] in
                Task {
                    await self?.hide()
                }
            }
        )
    }

    func toggle() async {
        if panel.isVisible {
            await hide()
        } else {
            await show()
        }
    }

    func show() async {
        do {
            try await session.restore()
        } catch {
            return
        }

        presentPanel()
    }

    func startNewScratch() async {
        do {
            try await session.startNewScratch()
        } catch {
            return
        }

        presentPanel()
    }

    private func presentPanel() {
        let currentApplication = NSRunningApplication.current
        let frontmostApplication = NSWorkspace.shared.frontmostApplication

        if frontmostApplication?.processIdentifier != currentApplication.processIdentifier {
            previousApplication = frontmostApplication
        }

        positionOnPointerScreenIfNeeded()
        panel.makeKeyAndOrderFront(nil)
        session.requestEditorFocus()
    }

    func hide() async {
        do {
            try await session.flush()
        } catch {
            return
        }

        let shouldRestorePreviousApplication = NSApp.isActive && panel.isKeyWindow

        panel.orderOut(nil)

        if shouldRestorePreviousApplication {
            previousApplication?.activate(options: [])
        }

        previousApplication = nil
    }

    func flushForTermination() async -> Bool {
        do {
            try await session.flush()
            return true
        } catch {
            return false
        }
    }

    func windowShouldZoom(_ window: NSWindow, toFrame newFrame: NSRect) -> Bool {
        false
    }

    private func configurePanel() {
        panel.delegate = self
        panel.title = "Rasc"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.level = .floating
        panel.collectionBehavior = [
            .moveToActiveSpace,
            .transient,
            .canJoinAllApplications,
            .fullScreenNone,
        ]
        panel.isReleasedWhenClosed = false
        panel.standardWindowButton(.zoomButton)?.isEnabled = false
        panel.minSize = NSSize(width: 360, height: 220)
        panel.maxSize = NSSize(width: 800, height: 700)
    }

    private func positionOnPointerScreenIfNeeded() {
        guard let targetScreen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
            ?? NSScreen.main
        else {
            return
        }

        let visibleFrame = targetScreen.visibleFrame
        guard !visibleFrame.contains(panel.frame) else {
            return
        }

        let origin = NSPoint(
            x: visibleFrame.midX - panel.frame.width / 2,
            y: visibleFrame.midY - panel.frame.height / 2
        )
        panel.setFrameOrigin(origin)
    }
}

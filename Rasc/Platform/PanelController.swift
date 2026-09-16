import AppKit
import SwiftUI

@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    let panel: NSPanel

    private let session: ScratchpadSession
    private let windowFrameStore: WindowFrameStore
    private var previousApplication: NSRunningApplication?

    init(
        repository: NoteRepository,
        refinementProvider: any RefinementProvider = FoundationModelsRefinementProvider(),
        windowFrameStore: WindowFrameStore = WindowFrameStore()
    ) {
        session = ScratchpadSession(
            repository: repository,
            refinementProvider: refinementProvider
        )
        self.windowFrameStore = windowFrameStore
        panel = ScratchpadPanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 340),
            styleMask: [.titled, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        super.init()

        configurePanel()
        panel.contentViewController = NSHostingController(
            rootView: ScratchpadView(
                session: session,
                onEscape: { [weak self] in
                    Task {
                        await self?.hide()
                    }
                },
                onPaletteCommand: { [weak self] command in
                    self?.handlePaletteCommand(command)
                }
            )
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

    func openSearch() async {
        do {
            if !panel.isVisible {
                try await session.restore()
            }
            try await session.openSearch()
        } catch {
            return
        }

        presentPanel()
    }

    func openCommandPalette() async {
        if !panel.isVisible {
            do {
                try await session.restore()
            } catch {
                return
            }
        }

        session.openCommandPalette()
        presentPanel()
    }

    func startRefinement() {
        guard panel.isVisible else { return }
        session.startRefinement()
    }

    func openSettings() {
        AppSettings.present()
    }

    private func presentPanel() {
        let currentApplication = NSRunningApplication.current
        let frontmostApplication = NSWorkspace.shared.frontmostApplication

        if frontmostApplication?.processIdentifier != currentApplication.processIdentifier {
            previousApplication = frontmostApplication
        }

        positionPanelIfNeeded()
        NSApp.activate(ignoringOtherApps: true)
        panel.orderFrontRegardless()
        panel.makeKeyAndOrderFront(nil)
        focusActiveSurface()
    }

    func hide() async {
        session.cancelRefinement()
        session.closeCommandPalette()
        do {
            try await session.flush()
        } catch {
            return
        }

        windowFrameStore.save(panel)

        let shouldRestorePreviousApplication = NSApp.isActive && panel.isKeyWindow

        panel.orderOut(nil)

        if shouldRestorePreviousApplication {
            previousApplication?.activate(options: [])
        }

        previousApplication = nil
    }

    func flushForTermination() async -> Bool {
        session.cancelRefinement()
        session.closeCommandPalette()
        windowFrameStore.save(panel)
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

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        Task { [weak self] in
            await self?.hide()
        }
        return false
    }

    func windowDidMove(_ notification: Notification) {
        guard panel.isVisible else { return }
        windowFrameStore.save(panel)
    }

    func windowDidResize(_ notification: Notification) {
        guard panel.isVisible else { return }
        windowFrameStore.save(panel)
    }

    private func configurePanel() {
        panel.delegate = self
        panel.title = "Rasc"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        // `.screenSaver` is required for the scratchpad to appear above native fullscreen apps.
        // `.floating` stays below fullscreen Spaces; validated on macOS 26 with `.fullScreenAuxiliary`.
        panel.level = .screenSaver
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .canJoinAllApplications,
            .fullScreenAuxiliary,
            .stationary,
        ]
        panel.isReleasedWhenClosed = false
        panel.standardWindowButton(.zoomButton)?.isEnabled = false
        panel.minSize = NSSize(width: 360, height: 220)
        panel.maxSize = NSSize(width: 800, height: 700)
    }

    private func positionPanelIfNeeded() {
        let targetScreen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
            ?? NSScreen.main
        windowFrameStore.restore(into: panel, on: targetScreen)
    }

    private func focusActiveSurface() {
        switch session.surface {
        case .search:
            session.requestSearchFocus()
        case .commandPalette:
            session.requestCommandPaletteFocus()
        case .editor, .message, .refining, .refinementPreview:
            session.requestEditorFocus()
        }
    }

    private func handlePaletteCommand(_ command: PaletteCommand) {
        switch command {
        case .newScratch:
            Task { await startNewScratch() }
        case .findNote:
            Task { await openSearch() }
        case .refine:
            startRefinement()
        case .settings:
            openSettings()
        }
    }
}

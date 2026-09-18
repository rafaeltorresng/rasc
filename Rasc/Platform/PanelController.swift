import AppKit
import CoreGraphics
import SwiftUI

@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    let panel: NSPanel
    let repository: NoteRepository

    private let session: ScratchpadSession
    private let windowFrameStore: WindowFrameStore
    private var previousApplication: NSRunningApplication?
    private var displayObservers: [NSObjectProtocol] = []
    weak var onboardingDelegate: OnboardingPanelDelegate?

    var scratchpadGuidance: OnboardingScratchpadGuidance = .inactive {
        didSet {
            session.scratchpadGuidance = scratchpadGuidance
        }
    }

    init(
        repository: NoteRepository,
        refinementProvider: any RefinementProvider = FoundationModelsRefinementProvider(),
        windowFrameStore: WindowFrameStore = WindowFrameStore()
    ) {
        self.repository = repository
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

        wireSessionObservation()
        configurePanel()
        observeDisplayChanges()
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
            .environment(\.onboardingScratchpadActions, onboardingScratchpadActions())
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
            AppDiagnostics.panelRestoreFailed()
            session.markLoadFailed()
        }

        presentPanel()
    }

    func startNewScratch() async {
        do {
            try await session.startNewScratch()
        } catch {
            session.markLoadFailed()
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
            if !panel.isVisible {
                session.markLoadFailed()
            }
        }

        presentPanel()
    }

    func startNewScratchForOnboarding() async {
        do {
            try await session.startNewScratch()
        } catch {
            session.markLoadFailed()
        }

        presentPanel()
    }

    func openCommandPalette() async {
        if !panel.isVisible {
            do {
                try await session.restore()
            } catch {
                session.markLoadFailed()
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
        let startedAt = ContinuousClock.now
        let surfaceLabel = session.surfaceDiagnosticLabel
        AppDiagnostics.panelPresentStarted(surface: surfaceLabel)

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

        let durationMs = Int((ContinuousClock.now - startedAt).components.attoseconds / 1_000_000_000_000_000)
        AppDiagnostics.panelPresentCompleted(surface: surfaceLabel, durationMs: max(durationMs, 0))
        onboardingDelegate?.panelDidShow()
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
        onboardingDelegate?.panelDidHide()
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
        windowFrameStore.restore(into: panel, on: targetPresentationScreen())
    }

    private func revalidatePanelFrame(reason: String) {
        windowFrameStore.ensureVisible(
            panel,
            on: targetPresentationScreen(),
            reason: reason
        )
    }

    private func targetPresentationScreen() -> NSScreen? {
        WindowFramePlacement.preferredScreen(
            frontmostWindowFrame: Self.frontmostWindowFrame(
                excludingPID: NSRunningApplication.current.processIdentifier
            ),
            mouseLocation: NSEvent.mouseLocation,
            screens: NSScreen.screens
        )
    }

    private static func frontmostWindowFrame(excludingPID: pid_t) -> NSRect? {
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return nil
        }

        for window in windowList {
            guard let ownerPID = window[kCGWindowOwnerPID as String] as? pid_t,
                  ownerPID != excludingPID,
                  let layer = window[kCGWindowLayer as String] as? Int,
                  layer == 0,
                  let bounds = window[kCGWindowBounds as String] as? [String: CGFloat]
            else {
                continue
            }

            return NSRect(
                x: bounds["X"] ?? 0,
                y: bounds["Y"] ?? 0,
                width: bounds["Width"] ?? 0,
                height: bounds["Height"] ?? 0
            )
        }

        return nil
    }

    private func observeDisplayChanges() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        displayObservers.append(
            workspaceCenter.addObserver(
                forName: NSWorkspace.screensDidWakeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.revalidatePanelFrame(reason: "screens_did_wake")
                }
            }
        )
        displayObservers.append(
            NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.revalidatePanelFrame(reason: "screen_parameters_changed")
                }
            }
        )
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

    private func onboardingScratchpadActions() -> OnboardingScratchpadActions {
        OnboardingScratchpadActions(
            dismissRefineUnavailable: { [weak self] in
                Task { @MainActor in
                    self?.onboardingDelegate?.dismissRefineUnavailable()
                }
            },
            openRefineSystemSettings: { [weak self] in
                Task { @MainActor in
                    self?.onboardingDelegate?.openRefineSystemSettings()
                }
            }
        )
    }

    private func wireSessionObservation() {
        session.onTextDidChange = { [weak self] text in
            self?.onboardingDelegate?.sessionTextDidChange(text)
        }
        session.onSurfaceDidChange = { [weak self] surface in
            self?.onboardingDelegate?.sessionSurfaceDidChange(surface)
        }
        session.onMessageDidShow = { [weak self] message in
            self?.onboardingDelegate?.sessionMessageDidShow(message)
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

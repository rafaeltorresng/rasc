import AppKit
import CoreGraphics
import SwiftUI

@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    let panel: NSPanel
    let repository: NoteRepository

    private let session: ScratchpadSession
    private let windowFrameStore: WindowFrameStore
    private var hostingController: NSHostingController<AnyView>!
    private var previousApplication: NSRunningApplication?
    private var displayObservers: [NSObjectProtocol] = []
    weak var onboardingDelegate: OnboardingPanelDelegate?
    var onOpenHome: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onDidHide: (() -> Void)?

    var scratchpadGuidance: OnboardingScratchpadGuidance = .inactive {
        didSet {
            session.scratchpadGuidance = scratchpadGuidance
        }
    }

    init(
        repository: NoteRepository,
        refinementProvider: any RefinementProvider = FoundationModelsRefinementProvider(),
        windowFrameStore: WindowFrameStore = .scratchpad()
    ) {
        self.repository = repository
        session = ScratchpadSession(
            repository: repository,
            refinementProvider: refinementProvider
        )
        self.windowFrameStore = windowFrameStore
        panel = ScratchpadPanel(
            contentRect: NSRect(origin: .zero, size: RascWindowMetrics.scratchpadDefault),
            styleMask: [.titled, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        super.init()

        wireSessionObservation()
        configurePanel()
        observeDisplayChanges()
        let rootView = ScratchpadView(
            session: session,
            onEscape: { [weak self] in
                Task {
                    await self?.hide()
                }
            },
            onPaletteCommand: { [weak self] command in
                self?.handlePaletteCommand(command)
            },
            onOpenHome: { [weak self] in
                self?.onOpenHome?()
            },
            onKeep: { [weak self] in
                Task { await self?.keepActiveNote() }
            },
            onUnkeep: { [weak self] in
                Task { await self?.unkeepActiveNote() }
            }
        )
        .environment(\.onboardingScratchpadActions, onboardingScratchpadActions())
        .frame(maxWidth: .infinity, maxHeight: .infinity)

        hostingController = NSHostingController(rootView: AnyView(rootView))
        hostingController.sizingOptions = [.minSize]
        panel.contentViewController = hostingController
    }

    var contentHostingSizingOptions: NSHostingSizingOptions {
        hostingController.sizingOptions
    }

    var scratchpadSession: ScratchpadSession {
        session
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
            if session.saveErrorMessage == nil {
                session.markLoadFailed()
            }
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
            if session.saveErrorMessage == nil {
                session.markLoadFailed()
            }
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
        session.requestSettingsPresentation()
    }

    func keepActiveNote() async {
        do {
            let outcome = try await session.keepActiveNote()
            if outcome == .keptShouldHide {
                try? await Task.sleep(for: .milliseconds(450))
                await hide()
            }
        } catch {
            session.reportCompletionFailure(.keep)
        }
    }

    func unkeepActiveNote() async {
        do {
            try await session.unkeepActiveNote()
        } catch {
            session.reportCompletionFailure(.unkeep)
        }
    }

    func copyActiveNote() async {
        do {
            guard let text = try await session.copyActiveNoteText() else { return }
            NoteHandoff.copyPlainText(text)
        } catch { session.reportCompletionFailure(.copy) }
    }

    func shareActiveNote() {
        Task { @MainActor in
            do {
                guard let text = try await session.copyActiveNoteText(), let contentView = panel.contentView else { return }
                NoteHandoff.presentSharePicker(for: text, relativeTo: contentView)
            } catch { session.reportCompletionFailure(.share) }
        }
    }

    func discardActiveNote() async {
        do {
            try await session.discardActiveNote(undoManager: panel.undoManager)
        } catch {
            session.reportCompletionFailure(.discard)
        }
    }

    func abandonActiveNoteIfMatching(id: UUID) async {
        await session.abandonActiveNoteIfMatching(id: id)
    }

    func refreshActiveNoteIfMatching(id: UUID) async {
        await session.refreshActiveNoteIfMatching(id: id)
    }

    func openNote(id: UUID) async {
        do {
            if !panel.isVisible {
                try await session.restore()
            }
            let opened = try await session.openNote(id: id)
            guard opened else { return }
        } catch {
            session.markLoadFailed()
            return
        }

        presentPanel()
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
        onDidHide?()
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

    func windowDidEndLiveResize(_ notification: Notification) {
        guard panel.isVisible else { return }
        windowFrameStore.save(panel)
    }

    private func configurePanel() {
        panel.delegate = self
        panel.title = "Rasc"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.backgroundColor = .clear
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
        for buttonType in [
            NSWindow.ButtonType.closeButton,
            .miniaturizeButton,
            .zoomButton,
        ] {
            panel.standardWindowButton(buttonType)?.isHidden = true
        }
        panel.standardWindowButton(.zoomButton)?.isEnabled = false
        panel.minSize = RascWindowMetrics.scratchpadMinimum
        panel.maxSize = RascWindowMetrics.scratchpadMaximum
    }

    private func positionPanelIfNeeded() {
        RascWindowPlacement.placeScratchpad(
            window: panel,
            store: windowFrameStore,
            excludingProcessID: NSRunningApplication.current.processIdentifier
        )
    }

    private func revalidatePanelFrame(reason: String) {
        RascWindowPlacement.ensureScratchpadVisible(
            window: panel,
            store: windowFrameStore,
            excludingProcessID: NSRunningApplication.current.processIdentifier,
            reason: reason
        )
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
            session.requestCommandPaletteKeyFocus()
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
        case .keep:
            Task { await keepActiveNote() }
        case .unkeep:
            Task { await unkeepActiveNote() }
        case .copyNote:
            Task { await copyActiveNote() }
        case .shareNote:
            shareActiveNote()
        case .discardNote:
            Task { await discardActiveNote() }
        case .newScratch:
            Task { await startNewScratch() }
        case .findNote:
            Task { await openSearch() }
        case .refine:
            startRefinement()
        case .openHome:
            session.closeCommandPalette()
            onOpenHome?()
        case .keyboardShortcuts:
            session.closeCommandPalette()
            SettingsNavigation.revealKeyboardShortcuts()
        case .settings:
            session.closeCommandPalette()
            onOpenSettings?()
        }
    }
}

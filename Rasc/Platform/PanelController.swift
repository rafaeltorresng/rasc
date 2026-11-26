import AppKit
import CoreGraphics
import SwiftUI

struct PanelOcclusionWindow: Equatable, Sendable {
    var ownerPID: pid_t
    var ownerName: String
    var layer: Int
    var width: CGFloat
    var height: CGFloat
}

enum ScratchpadPanelLevelPolicy {
    static let modalLayer = NSWindow.Level.modalPanel.rawValue

    static func level(
        homeIsVisible: Bool,
        appIsActive: Bool,
        menuIsTracking: Bool,
        systemInteractionNeedsPriority: Bool = false
    ) -> NSWindow.Level {
        if systemInteractionNeedsPriority || (homeIsVisible && appIsActive) {
            return .normal
        }
        if menuIsTracking {
            return .floating
        }
        return .screenSaver
    }

    /// Alerts, menus, and authorization windows sit between modal level and the menu bar.
    /// Menu-bar strips and the Dock are always present and must not lower the scratchpad.
    static func systemInteractionNeedsPriority(
        windows: [PanelOcclusionWindow],
        ourPID: pid_t
    ) -> Bool {
        let ignoredOwners: Set<String> = ["Window Server", "Dock"]
        for window in windows where window.ownerPID != ourPID {
            guard window.layer >= modalLayer else { continue }
            if ignoredOwners.contains(window.ownerName) { continue }
            // Menu bars and app strips sit above modal level but are not dialogs.
            if window.height < 120 { continue }
            if window.width >= 900, window.height < 200 { continue }
            return true
        }
        return false
    }
}

private struct PanelKeySnapshot: Sendable {
    var isCommandW: Bool
    var shortcut: InternalShortcut?
}

@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    let panel: ScratchpadPanel
    let repository: NoteRepository
    lazy var noteExport = NoteExportController(repository: repository)

    private let session: ScratchpadSession
    private let windowFrameStore: WindowFrameStore
    private var hostingController: NSHostingController<AnyView>!
    private var previousApplication: NSRunningApplication?
    private nonisolated(unsafe) var defaultObservers: [NSObjectProtocol] = []
    private nonisolated(unsafe) var workspaceObservers: [NSObjectProtocol] = []
    private nonisolated(unsafe) var keyMonitor: Any?
    private var homeIsVisible = false
    private var menuIsTracking = false
    private nonisolated(unsafe) var occlusionTimer: Timer?

    deinit {
        occlusionTimer?.invalidate()
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        for observer in defaultObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        for observer in workspaceObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }
    weak var onboardingDelegate: OnboardingPanelDelegate?
    var onOpenHome: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onVoiceCapture: (() -> Void)?
    var onVoiceDictate: (() -> Void)?
    var onVoiceCaptureShortcut: ((NSEvent) -> Bool)?
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
        observeActivation()
        installKeyMonitor()
        let session = self.session
        let onboardingActions = self.onboardingScratchpadActions()
        let rootView = RascAppearanceView {
            ScratchpadView(
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
            .environment(\.onboardingScratchpadActions, onboardingActions)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }

        hostingController = NSHostingController(rootView: AnyView(rootView))
        hostingController.sizingOptions = [.minSize]
        panel.contentViewController = hostingController
    }

    var contentHostingSizingOptions: NSHostingSizingOptions {
        hostingController.sizingOptions
    }

    private var lastAutoHeight: CGFloat?

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
        } catch NoteRepository.PersistenceError.structuredContentRequiresDocument {
            session.markStructuredContentUnavailable()
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

    func reopenCurrentScratchForOnboarding() async {
        if !panel.isVisible {
            do {
                try await session.restore()
            } catch {
                if session.saveErrorMessage == nil {
                    session.markLoadFailed()
                }
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
            onboardingDelegate?.sessionDidKeepNote()
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
            guard let document = try await session.documentForHandoff() else { return }
            try await NoteHandoff.copy(document)
            if document.hasImages { session.reportImageCopy(document) }
        } catch { session.reportCompletionFailure(.copy) }
    }

    func shareActiveNote() {
        Task { @MainActor in
            do {
                guard let document = try await session.documentForHandoff(), let contentView = panel.contentView else { return }
                try await NoteHandoff.presentSharePicker(for: document, relativeTo: contentView)
            } catch { session.reportCompletionFailure(.share) }
        }
    }

    func exportActiveThought() async {
        await noteExport.exportThought(from: panel) {
            try await session.activeThoughtForExport()
        }
    }

    func prepareThoughtsForExport(_ scope: NoteExportScope) async throws {
        try await session.flushForExport(scope)
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

    func noteHomeVisibility(_ isVisible: Bool) {
        homeIsVisible = isVisible
        updatePanelLevel()
    }

    func openNote(id: UUID) async {
        do {
            if !panel.isVisible {
                try await session.restore()
            }
            let opened = try await session.openNote(id: id)
            guard opened else { return }
        } catch NoteRepository.PersistenceError.structuredContentRequiresDocument {
            session.markStructuredContentUnavailable()
            presentPanel()
            return
        } catch {
            session.markLoadFailed()
            return
        }

        presentPanel()
    }

    func openCapturedScratch(id: UUID, interrupted: Bool) async -> Bool {
        func canOpen() -> Bool {
            NSApp.modalWindow == nil && NSApp.keyWindow?.attachedSheet == nil
        }

        guard canOpen(), (try? await session.openNote(id: id, canOpen: canOpen)) == true else {
            return false
        }
        if interrupted { session.reportInterruptedVoiceCapture() }
        presentPanel()
        return true
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
        resizePanelForTransientSurface()
        NSApp.activate(ignoringOtherApps: true)
        updatePanelLevel(force: true)
        startOcclusionMonitoring()
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

        stopOcclusionMonitoring()
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

    func flushActiveNoteIfMatching(id: UUID) async throws {
        try await session.flushIfActiveNote(id: id)
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
        updatePanelLevel(force: true)
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

    /// Keep the transient panel compact when only a few rows are on screen.
    /// Switching surfaces must never move a panel the user sized themselves:
    /// auto-sizing applies only to the default height or the last height we set.
    private func resizePanelForTransientSurface() {
        let currentHeight = panel.frame.size.height
        let isUserSized = currentHeight != RascWindowMetrics.scratchpadDefault.height
            && abs(currentHeight - (lastAutoHeight ?? -1)) > 0.5

        let isTransient = session.surface == .search || session.surface == .commandPalette

        let target: CGFloat?
        switch session.surface {
        case .search:
            target = RascTransientPanelSizing.searchHeight(resultCount: session.searchResults.count)
        case .commandPalette:
            target = RascTransientPanelSizing.paletteHeight(commandCount: session.filteredCommands.count)
        default:
            guard let lastAutoHeight,
                  abs(currentHeight - lastAutoHeight) < 0.5
            else {
                return
            }
            target = RascWindowMetrics.scratchpadDefault.height
        }

        guard !isUserSized, let target, abs(currentHeight - target) > 0.5 else { return }

        panel.minSize = isTransient
            ? NSSize(width: RascWindowMetrics.scratchpadMinimum.width, height: RascTransientPanelSizing.transientMinimumHeight)
            : RascWindowMetrics.scratchpadMinimum

        var frame = panel.frame
        let top = frame.maxY
        frame.size.height = target
        frame.origin.y = top - target
        panel.setFrame(frame, display: true)
        lastAutoHeight = session.surface == .editor || session.surface == .message ? nil : target
        revalidatePanelFrame(reason: "transient-resize")
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

    private func installKeyMonitor() {
        // Preview Left/Right cycles Suggested → Changes → Original. Intercepted
        // before the responder chain because the preview's comparison picker
        // (an NSSegmentedControl) accepts first responder and would otherwise
        // consume the arrows. The editor keeps its own arrows.
        panel.keyDownHandler = { [weak self] event in
            MainActor.assumeIsolated {
                if self?.onVoiceCaptureShortcut?(event) == true { return true }
                return self?.handlePreviewArrowKey(event) ?? false
            }
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let snapshot = PanelKeySnapshot(
                isCommandW: flags == .command && event.charactersIgnoringModifiers?.lowercased() == "w",
                shortcut: InternalShortcut(event: event)
            )
            let handled = MainActor.assumeIsolated {
                self?.handleKeySnapshot(snapshot) ?? false
            }
            return handled ? nil : event
        }
    }

    private func handlePreviewArrowKey(_ event: NSEvent) -> Bool {
        guard panel.isKeyWindow else { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        // Arrow keys are "special keys" and carry the Function flag (numpad
        // arrows carry numericPad), so "plain" means none of the four
        // command-like modifiers — not an empty flag set.
        guard flags.intersection([.command, .option, .control, .shift]).isEmpty,
              let specialKey = event.specialKey else { return false }
        let offset: Int
        switch specialKey {
        case .leftArrow: offset = -1
        case .rightArrow: offset = 1
        default: return false
        }
        guard session.surface == .refinementPreview else { return false }
        session.cyclePreviewMode(by: offset)
        return true
    }

    private func handleKeySnapshot(_ snapshot: PanelKeySnapshot) -> Bool {
        guard panel.isKeyWindow else { return false }
        if snapshot.isCommandW {
            Task { await hide() }
            return true
        }
        if let shortcut = snapshot.shortcut,
           let command = InternalShortcutStore.shared.command(matching: shortcut) {
            performInternalCommand(command)
            return true
        }
        return false
    }

    private func performInternalCommand(_ command: InternalCommand) {
        switch command {
        case .newScratch:
            Task { await startNewScratch() }
        case .search:
            Task { await openSearch() }
        case .refine:
            startRefinement()
        case .commandPalette:
            Task { await openCommandPalette() }
        case .keep:
            Task { await keepActiveNote() }
        }
    }

    private func observeActivation() {
        let center = NotificationCenter.default
        defaultObservers.append(
            center.addObserver(
                forName: NSApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.updatePanelLevel()
                    InternalShortcutStore.shared.applyToMainMenu()
                }
            }
        )
        workspaceObservers.append(
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.updatePanelLevel()
                }
            }
        )
        defaultObservers.append(
            center.addObserver(
                forName: NSApplication.didResignActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.updatePanelLevel()
                }
            }
        )
        defaultObservers.append(
            center.addObserver(
                forName: NSMenu.didBeginTrackingNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.menuIsTracking = true
                    self?.updatePanelLevel()
                }
            }
        )
        defaultObservers.append(
            center.addObserver(
                forName: NSMenu.didEndTrackingNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.menuIsTracking = false
                    self?.updatePanelLevel()
                }
            }
        )
    }

    private func updatePanelLevel(force: Bool = false) {
        guard force || panel.isVisible else { return }
        let appIsActive = NSApp.isActive
        let needsPriority = (homeIsVisible && appIsActive) ? false : systemInteractionNeedsPriority()
        let nextLevel = ScratchpadPanelLevelPolicy.level(
            homeIsVisible: homeIsVisible,
            appIsActive: appIsActive,
            menuIsTracking: menuIsTracking,
            systemInteractionNeedsPriority: needsPriority
        )
        if panel.level != nextLevel {
            panel.level = nextLevel
        }
    }

    private func systemInteractionNeedsPriority() -> Bool {
        ScratchpadPanelLevelPolicy.systemInteractionNeedsPriority(
            windows: Self.onScreenOcclusionWindows(),
            ourPID: ProcessInfo.processInfo.processIdentifier
        )
    }

    private func startOcclusionMonitoring() {
        guard occlusionTimer == nil else { return }
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updatePanelLevel()
            }
        }
        timer.tolerance = 0.15
        RunLoop.main.add(timer, forMode: .common)
        occlusionTimer = timer
    }

    private func stopOcclusionMonitoring() {
        occlusionTimer?.invalidate()
        occlusionTimer = nil
    }

    private static func onScreenOcclusionWindows() -> [PanelOcclusionWindow] {
        guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        return info.compactMap { window in
            guard let ownerPID = window[kCGWindowOwnerPID as String] as? pid_t,
                  let layer = window[kCGWindowLayer as String] as? Int,
                  let bounds = window[kCGWindowBounds as String] as? [String: CGFloat]
            else {
                return nil
            }
            return PanelOcclusionWindow(
                ownerPID: ownerPID,
                ownerName: window[kCGWindowOwnerName as String] as? String ?? "",
                layer: layer,
                width: bounds["Width"] ?? 0,
                height: bounds["Height"] ?? 0
            )
        }
    }

    private func observeDisplayChanges() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(
            workspaceCenter.addObserver(
                forName: NSWorkspace.screensDidWakeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.panel.isVisible else { return }
                    self.revalidatePanelFrame(reason: "screens_did_wake")
                }
            }
        )
        defaultObservers.append(
            NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.panel.isVisible else { return }
                    self.revalidatePanelFrame(reason: "screen_parameters_changed")
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
            MainActor.assumeIsolated {
                self?.resizePanelForTransientSurface()
            }
        }
        session.onSearchResultsDidChange = { [weak self] _ in
            self?.resizePanelForTransientSurface()
        }
        session.onPaletteResultsDidChange = { [weak self] _ in
            self?.resizePanelForTransientSurface()
        }
        session.onMessageDidShow = { [weak self] message in
            self?.onboardingDelegate?.sessionMessageDidShow(message)
        }
    }

    func refreshSearchAfterVoiceCapture() {
        if session.surface == .search { session.scheduleSearch() }
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
        case .exportThought:
            Task { await exportActiveThought() }
        case .exportThoughts:
            session.closeCommandPalette()
            Task { await noteExport.exportThoughts(from: panel, prepare: prepareThoughtsForExport) }
        case .discardNote:
            Task { await discardActiveNote() }
        case .newScratch:
            Task { await startNewScratch() }
        case .findNote:
            Task { await openSearch() }
        case .refine:
            startRefinement()
        case .voiceCapture:
            session.closeCommandPalette()
            onVoiceCapture?()
        case .dictate:
            session.closeCommandPalette()
            onVoiceDictate?()
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

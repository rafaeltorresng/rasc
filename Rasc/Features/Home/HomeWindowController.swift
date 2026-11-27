import AppKit
import Combine
import SwiftUI

@MainActor
private final class HomeActionCallbacks {
    var onOpenNote: (UUID) -> Void = { _ in }
    var onNewScratch: () -> Void = {}
    var onNoteDiscarded: (UUID) -> Void = { _ in }
    var onNoteUnkept: (UUID) -> Void = { _ in }
    var onExportThought: (UUID) -> Void = { _ in }
    var onExportSelected: (Set<UUID>) -> Void = { _ in }
}

@MainActor
final class HomeWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var session: HomeSession?
    private var paletteObservation: AnyCancellable?
    private let windowFrameStore: WindowFrameStore
    private let hiddenReleaseGracePeriod: Duration
    private let callbacks = HomeActionCallbacks()
    private nonisolated(unsafe) var deferredReleaseTask: Task<Void, Never>?
    private nonisolated(unsafe) var memoryPressureSource: DispatchSourceMemoryPressure?
    private nonisolated(unsafe) var defaultObservers: [NSObjectProtocol] = []
    private nonisolated(unsafe) var workspaceObservers: [NSObjectProtocol] = []
    private var suppressNextBecomeKeyReload = false

    deinit {
        deferredReleaseTask?.cancel()
        memoryPressureSource?.cancel()
        for observer in defaultObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        for observer in workspaceObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }

    var isVisible: Bool {
        window?.isVisible == true
    }

    var isKeyWindow: Bool { window?.isKeyWindow == true }
    var selectedNoteID: UUID? { session?.selectedNote()?.id }
    var exportWindow: NSWindow? { window }
    var hasAttachedContentViewController: Bool { window?.contentViewController != nil }
    var loadedNoteCount: Int { session?.noteCount ?? 0 }
    #if RASC_EFFICIENCY_BENCHMARK
    var benchmarkSession: HomeSession? { session }
    #endif

    var onVisibilityChange: ((Bool) -> Void)?

    init(
        windowFrameStore: WindowFrameStore = .home(),
        hiddenReleaseGracePeriod: Duration = .seconds(2)
    ) {
        self.windowFrameStore = windowFrameStore
        self.hiddenReleaseGracePeriod = hiddenReleaseGracePeriod
        super.init()
        observeDisplayChanges()
        observeMemoryPressure()
    }

    func show(
        repository: NoteRepository,
        onOpenNote: @escaping (UUID) -> Void,
        onNewScratch: @escaping () -> Void,
        prepareForDuplicate: @escaping @MainActor (UUID) async throws -> Void = { _ in },
        onNoteDiscarded: @escaping (UUID) -> Void = { _ in },
        onNoteUnkept: @escaping (UUID) -> Void = { _ in },
        onExportThought: @escaping (UUID) -> Void = { _ in },
        onExportSelected: @escaping (Set<UUID>) -> Void = { _ in }
    ) {
        deferredReleaseTask?.cancel()
        deferredReleaseTask = nil

        let wasVisible = window?.isVisible == true
        let session = session ?? HomeSession(repository: repository, prepareForDuplicate: prepareForDuplicate)
        self.session = session
        if !wasVisible {
            session.recordHomeVisit()
        }
        session.requestSearchFocus()

        callbacks.onOpenNote = onOpenNote
        callbacks.onNewScratch = onNewScratch
        callbacks.onNoteDiscarded = onNoteDiscarded
        callbacks.onNoteUnkept = onNoteUnkept
        callbacks.onExportThought = onExportThought
        callbacks.onExportSelected = onExportSelected

        let window = self.window ?? makeWindow()
        (window as? HomeWindow)?.homeSession = session
        if window.contentViewController == nil {
            let contentView = RascAppearanceView { [weak callbacks] in
                HomeView(
                    session: session,
                    onOpenNote: { callbacks?.onOpenNote($0) },
                    onNewScratch: { callbacks?.onNewScratch() },
                    onNoteDiscarded: { callbacks?.onNoteDiscarded($0) },
                    onNoteUnkept: { callbacks?.onNoteUnkept($0) },
                    onExportThought: { callbacks?.onExportThought($0) },
                    onExportSelected: { callbacks?.onExportSelected($0) }
                )
            }
            window.contentViewController = NSHostingController(rootView: contentView)
        }

        positionWindowIfNeeded(window)
        NSApp.activate(ignoringOtherApps: true)
        suppressNextBecomeKeyReload = true
        window.makeKeyAndOrderFront(nil)
        suppressNextBecomeKeyReload = false
        self.window = window
        onVisibilityChange?(true)
        reloadIfVisible()
    }

    func close() {
        guard let window else { return }
        hideWindow(window)
    }

    func reloadIfVisible() {
        guard isVisible, let session else { return }
        Task {
            await session.reloadImmediately()
        }
    }

    func windowDidBecomeKey(_ notification: Notification) {
        guard !suppressNextBecomeKeyReload else { return }
        reloadIfVisible()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hideWindow(sender)
        return false
    }

    func releaseHiddenContentIfNeeded() {
        deferredReleaseTask?.cancel()
        deferredReleaseTask = nil
        guard let window, !window.isVisible else { return }
        releaseHiddenContent(of: window)
    }

    private func hideWindow(_ window: NSWindow) {
        windowFrameStore.save(window)
        window.orderOut(nil)
        scheduleDeferredHiddenRelease(for: window)
        onVisibilityChange?(false)
    }

    private func scheduleDeferredHiddenRelease(for window: NSWindow) {
        deferredReleaseTask?.cancel()
        deferredReleaseTask = Task { @MainActor [weak self, weak window] in
            guard let self else { return }
            do {
                try await Task.sleep(for: hiddenReleaseGracePeriod)
            } catch {
                return
            }
            guard !Task.isCancelled, let window, !window.isVisible else { return }
            releaseHiddenContent(of: window)
            deferredReleaseTask = nil
        }
    }

    private func releaseHiddenContent(of window: NSWindow) {
        window.contentViewController = nil
        session?.releaseCachedNotesForHiddenWindow()
    }

    private func observeMemoryPressure() {
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        source.setEventHandler { [weak self] in
            Task { @MainActor [weak self] in
                self?.releaseHiddenContentIfNeeded()
            }
        }
        source.resume()
        memoryPressureSource = source
    }

    func windowDidMove(_ notification: Notification) {
        guard let window, window.isVisible else { return }
        windowFrameStore.save(window)
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        guard let window, window.isVisible else { return }
        windowFrameStore.save(window)
    }

    private func makeWindow() -> NSWindow {
        let window = HomeWindow(
            contentRect: NSRect(origin: .zero, size: RascWindowMetrics.homeDefault),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.homeSession = session
        window.delegate = self
        window.title = "Rasc"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = true
        window.minSize = RascWindowMetrics.homeMinimum
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        paletteObservation = ThemeStore.shared.$palette.sink { [weak window] palette in
            window?.backgroundColor = palette.panelBackground
        }
        return window
    }

    private func positionWindowIfNeeded(_ window: NSWindow) {
        RascWindowPlacement.placeHome(
            window: window,
            store: windowFrameStore,
            excludingProcessID: NSRunningApplication.current.processIdentifier
        )
    }

    private func revalidateWindowFrame(reason: String) {
        guard let window, window.isVisible else { return }
        RascWindowPlacement.ensureHomeVisible(
            window: window,
            store: windowFrameStore,
            excludingProcessID: NSRunningApplication.current.processIdentifier,
            reason: reason
        )
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
                    self?.revalidateWindowFrame(reason: "screens_did_wake")
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
                    self?.revalidateWindowFrame(reason: "screen_parameters_changed")
                }
            }
        )
    }
}

private final class HomeWindow: NSWindow {
    weak var homeSession: HomeSession?

    @objc override func selectAll(_ sender: Any?) {
        if firstResponder is NSText {
            NSApp.sendAction(#selector(NSText.selectAll(_:)), to: firstResponder, from: sender)
            return
        }
        homeSession?.selectAllVisible()
    }

    override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(selectAll(_:)), !(firstResponder is NSText) {
            return homeSession?.displayedNotes.isEmpty == false
        }
        return super.validateUserInterfaceItem(item)
    }
}

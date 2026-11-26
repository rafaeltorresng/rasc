import AppKit
import Combine
import SwiftUI

@MainActor
final class HomeWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var session: HomeSession?
    private var paletteObservation: AnyCancellable?
    private let windowFrameStore: WindowFrameStore
    private nonisolated(unsafe) var defaultObservers: [NSObjectProtocol] = []
    private nonisolated(unsafe) var workspaceObservers: [NSObjectProtocol] = []

    deinit {
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
    #if RASC_EFFICIENCY_BENCHMARK
    var benchmarkSession: HomeSession? { session }
    #endif

    var onVisibilityChange: ((Bool) -> Void)?

    init(windowFrameStore: WindowFrameStore = .home()) {
        self.windowFrameStore = windowFrameStore
        super.init()
        observeDisplayChanges()
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
        let session = session ?? HomeSession(repository: repository, prepareForDuplicate: prepareForDuplicate)
        self.session = session
        session.recordHomeVisit()

        let contentView = RascAppearanceView {
            HomeView(
                session: session,
                onOpenNote: onOpenNote,
                onNewScratch: onNewScratch,
                onNoteDiscarded: onNoteDiscarded,
                onNoteUnkept: onNoteUnkept,
                onExportThought: onExportThought,
                onExportSelected: onExportSelected
            )
        }

        let hostingController = NSHostingController(rootView: contentView)
        let window = self.window ?? makeWindow()
        (window as? HomeWindow)?.homeSession = session
        window.contentViewController = hostingController

        positionWindowIfNeeded(window)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        self.window = window
        onVisibilityChange?(true)
        reloadIfVisible()
    }

    func close() {
        guard let window else { return }
        windowFrameStore.save(window)
        window.orderOut(nil)
        releaseHiddenContent(of: window)
        onVisibilityChange?(false)
    }

    func reloadIfVisible() {
        guard isVisible, let session else { return }
        Task {
            await session.reloadImmediately()
        }
    }

    func windowDidBecomeKey(_ notification: Notification) {
        reloadIfVisible()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        windowFrameStore.save(sender)
        sender.orderOut(nil)
        releaseHiddenContent(of: sender)
        onVisibilityChange?(false)
        return false
    }

    private func releaseHiddenContent(of window: NSWindow) {
        window.contentViewController = nil
        session?.releaseCachedNotesForHiddenWindow()
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

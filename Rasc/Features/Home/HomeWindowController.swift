import AppKit
import SwiftUI

@MainActor
final class HomeWindowController: NSObject, NSWindowDelegate {
    static let defaultSize = NSSize(width: 1_000, height: 680)
    static let minimumSize = NSSize(width: 760, height: 520)

    private var window: NSWindow?
    private var session: HomeSession?
    private let windowFrameStore: WindowFrameStore
    private var displayObservers: [NSObjectProtocol] = []

    var isVisible: Bool {
        window?.isVisible == true
    }

    init(windowFrameStore: WindowFrameStore = .home()) {
        self.windowFrameStore = windowFrameStore
        super.init()
        observeDisplayChanges()
    }

    func show(
        repository: NoteRepository,
        onOpenNote: @escaping (UUID) -> Void,
        onNewScratch: @escaping () -> Void
    ) {
        let session = session ?? HomeSession(repository: repository)
        self.session = session

        let contentView = HomeView(
            session: session,
            onOpenNote: onOpenNote,
            onNewScratch: onNewScratch
        )

        let hostingController = NSHostingController(rootView: contentView)
        let window = self.window ?? makeWindow()
        window.contentViewController = hostingController

        positionWindowIfNeeded(window)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        self.window = window
        reloadIfVisible()
    }

    func close() {
        guard let window else { return }
        windowFrameStore.save(window)
        window.orderOut(nil)
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
        return false
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
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.defaultSize),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.delegate = self
        window.title = "Rasc"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = true
        window.minSize = Self.minimumSize
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.backgroundColor = RascSurfacePalette.panelBackground
        return window
    }

    private func positionWindowIfNeeded(_ window: NSWindow) {
        if windowFrameStore.hasSavedFrame {
            windowFrameStore.restore(into: window, on: targetPresentationScreen())
            return
        }

        window.setContentSize(Self.defaultSize)
        windowFrameStore.restore(into: window, on: targetPresentationScreen())
    }

    private func revalidateWindowFrame(reason: String) {
        guard let window, window.isVisible else { return }
        windowFrameStore.ensureVisible(
            window,
            on: targetPresentationScreen(),
            reason: reason
        )
    }

    private func targetPresentationScreen() -> NSScreen? {
        WindowFramePlacement.preferredScreen(
            frontmostWindowFrame: nil,
            mouseLocation: NSEvent.mouseLocation,
            screens: NSScreen.screens
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
                    self?.revalidateWindowFrame(reason: "screens_did_wake")
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
                    self?.revalidateWindowFrame(reason: "screen_parameters_changed")
                }
            }
        )
    }
}

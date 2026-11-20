import AppKit
import Testing
@testable import Rasc

@Suite(.serialized)
@MainActor
struct HomeWindowControllerTests {
    @Test
    func homeUsesIndependentFrameStoreKey() throws {
        let userDefaults = UserDefaults(suiteName: "RascTests.\(UUID().uuidString)")!
        let scratchpadStore = WindowFrameStore.scratchpad(userDefaults: userDefaults)
        let homeStore = WindowFrameStore.home(userDefaults: userDefaults)

        let scratchpadWindow = NSWindow(
            contentRect: NSRect(x: 120, y: 180, width: 520, height: 340),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let homeWindow = NSWindow(
            contentRect: NSRect(x: 240, y: 260, width: 1_000, height: 680),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )

        scratchpadStore.save(scratchpadWindow)
        homeStore.save(homeWindow)

        #expect(userDefaults.string(forKey: WindowFrameStore.scratchpadFrameKey) != nil)
        #expect(userDefaults.string(forKey: WindowFrameStore.homeFrameKey) != nil)
        #expect(
            userDefaults.string(forKey: WindowFrameStore.scratchpadFrameKey)
                != userDefaults.string(forKey: WindowFrameStore.homeFrameKey)
        )
    }

    @Test
    func openingHomeDoesNotResizeScratchpad() async throws {
        let userDefaults = UserDefaults(suiteName: "RascTests.\(UUID().uuidString)")!
        let scratchpadStore = WindowFrameStore.scratchpad(userDefaults: userDefaults)
        let homeStore = WindowFrameStore.home(userDefaults: userDefaults)
        let controller = try makePanelController(windowFrameStore: scratchpadStore)
        let fixedFrame = NSRect(x: 100, y: 200, width: 520, height: 340)
        controller.panel.setFrame(fixedFrame, display: false)

        let homeController = HomeWindowController(windowFrameStore: homeStore)
        homeController.show(
            repository: controller.repository,
            onOpenNote: { _ in },
            onNewScratch: {}
        )

        #expect(controller.panel.frame == fixedFrame)
        #expect(homeController.isVisible)
    }

    @Test
    func reopeningHomeFocusesTheSearchField() async throws {
        let defaults = UserDefaults(suiteName: "RascTests.HomeFocus.\(UUID().uuidString)")!
        let panel = try makePanelController(windowFrameStore: .scratchpad(userDefaults: defaults))
        let home = HomeWindowController(windowFrameStore: .home(userDefaults: defaults))
        defer { home.close() }

        home.show(repository: panel.repository, onOpenNote: { _ in }, onNewScratch: {})
        try await Task.sleep(for: .milliseconds(100))
        let window = try #require(NSApp.keyWindow)
        window.makeFirstResponder(nil)

        home.show(repository: panel.repository, onOpenNote: { _ in }, onNewScratch: {})
        // The focus lands asynchronously after the hosting controller is rebuilt;
        // poll instead of assuming a fixed delay (fixed delays flake on busy runners).
        let focused = await waitUntil {
            guard let editor = window.firstResponder as? NSTextView else { return false }
            return (editor.delegate as? NSTextField)?.placeholderString == "Search thoughts…"
        }
        #expect(focused)
    }

    @Test
    func toggleHomeOpensAndClosesHome() async throws {
        let bootstrap = AppBootstrap()
        bootstrap.start()

        while bootstrap.panelIfReady() == nil {
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(!bootstrap.homeIsVisible)
        await bootstrap.toggleHome()
        #expect(bootstrap.homeIsVisible)
        await bootstrap.toggleHome()
        #expect(!bootstrap.homeIsVisible)
    }

    @Test
    func openingHomeTwiceKeepsItOpen() async throws {
        let bootstrap = AppBootstrap()
        bootstrap.start()

        while bootstrap.panelIfReady() == nil {
            try await Task.sleep(for: .milliseconds(10))
        }

        await bootstrap.openHome()
        #expect(bootstrap.homeIsVisible)
        await bootstrap.openHome()
        #expect(bootstrap.homeIsVisible)
    }

    @Test
    func finishingOnboardingOpensHome() async throws {
        let suiteName = "RascTests.OnboardingFinish.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let bootstrap = AppBootstrap()
        bootstrap.start()
        let coordinator = OnboardingCoordinator(
            store: OnboardingStore(userDefaults: defaults),
            activeNoteStore: ActiveNoteStore(userDefaults: defaults),
            windowFrameStore: WindowFrameStore(userDefaults: defaults)
        )
        await coordinator.prepare(bootstrap: bootstrap, forceReset: true)

        coordinator.finish()
        for _ in 0..<100 where !bootstrap.homeIsVisible {
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(bootstrap.homeIsVisible)
        await bootstrap.toggleHome()
    }

    @Test
    func closingHomeDoesNotTerminateApplication() {
        let delegate = AppDelegate()
        #expect(delegate.applicationShouldTerminateAfterLastWindowClosed(NSApp) == false)
    }

    @Test
    func restoresAndPersistsHomeFrameIndependently() throws {
        let userDefaults = UserDefaults(suiteName: "RascTests.\(UUID().uuidString)")!
        let homeStore = WindowFrameStore.home(userDefaults: userDefaults)
        let window = NSWindow(
            contentRect: NSRect(x: 180, y: 220, width: 980, height: 660),
            styleMask: [.titled, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        let savedFrame = window.frame
        homeStore.save(window)

        #expect(userDefaults.string(forKey: WindowFrameStore.homeFrameKey) != nil)

        let restoredWindow = NSWindow(
            contentRect: .zero,
            styleMask: [.titled, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        homeStore.restore(into: restoredWindow, on: NSScreen.main)

        #expect(restoredWindow.frame == savedFrame)
    }

    private func makePanelController(
        windowFrameStore: WindowFrameStore
    ) throws -> PanelController {
        let databaseURL = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appendingPathExtension("sqlite")
        return PanelController(
            repository: try NoteRepository(databaseURL: databaseURL),
            windowFrameStore: windowFrameStore
        )
    }

    /// Polls until the predicate holds, up to ~3s; returns the final value.
    private func waitUntil(_ predicate: @MainActor () -> Bool, timeout: TimeInterval = 3) async -> Bool {
        for _ in 0..<30 {
            if predicate() { return true }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return predicate()
    }
}

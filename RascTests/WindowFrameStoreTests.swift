import AppKit
import Testing
@testable import Rasc

@Suite
struct WindowFramePlacementTests {
    @Test
    func requiresMinimumVisibleIntersection() {
        let visible = NSRect(x: 0, y: 0, width: 1_440, height: 900)
        let onscreen = NSRect(x: 100, y: 100, width: 520, height: 340)
        let offscreen = NSRect(x: 2_000, y: 2_000, width: 520, height: 340)

        #expect(WindowFramePlacement.isVisible(frame: onscreen, in: visible))
        #expect(!WindowFramePlacement.isVisible(frame: offscreen, in: visible))
    }

    @Test
    func centersWithinVisibleFrame() {
        let visible = NSRect(x: 100, y: 100, width: 800, height: 600)
        let origin = WindowFramePlacement.centeredOrigin(
            for: RascWindowMetrics.scratchpadDefault,
            in: visible
        )

        #expect(origin.x == 140)
        #expect(origin.y == 180)
    }

    @Test
    func opticalCenterSitsAboveGeometricCenter() {
        let visible = NSRect(x: 100, y: 100, width: 800, height: 600)
        let size = RascWindowMetrics.scratchpadDefault
        let geometric = WindowFramePlacement.centeredOrigin(for: size, in: visible)
        let optical = RascWindowPlacement.opticalCenterOrigin(for: size, in: visible)

        #expect(optical.x == geometric.x)
        #expect(optical.y < geometric.y)
    }
}

@Suite(.serialized)
@MainActor
struct WindowFrameStoreTests {
    @Test
    func recentersOffscreenStoredFrameOnRestore() {
        let userDefaults = UserDefaults(suiteName: "RascTests.\(UUID().uuidString)")!
        let store = WindowFrameStore(userDefaults: userDefaults)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: RascWindowMetrics.scratchpadDefault),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let offscreenFrame = NSRect(
            x: 9_000,
            y: 9_000,
            width: RascWindowMetrics.scratchpadDefault.width,
            height: RascWindowMetrics.scratchpadDefault.height
        )

        userDefaults.set(NSStringFromRect(offscreenFrame), forKey: "scratchpadWindowFrame")
        store.restore(into: window, on: NSScreen.main)

        guard let screen = NSScreen.main else {
            Issue.record("No main screen available for window frame test")
            return
        }

        #expect(WindowFramePlacement.isVisible(frame: window.frame, in: screen.visibleFrame))
    }

    @Test
    func restoresSavedFrameWithoutRepositioning() {
        let userDefaults = UserDefaults(suiteName: "RascTests.\(UUID().uuidString)")!
        let store = WindowFrameStore.home(userDefaults: userDefaults)
        let savedFrame = NSRect(x: 220, y: 180, width: 980, height: 660)
        userDefaults.set(NSStringFromRect(savedFrame), forKey: WindowFrameStore.homeFrameKey)

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: RascWindowMetrics.homeDefault),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )

        RascWindowPlacement.placeHome(
            window: window,
            store: store,
            excludingProcessID: NSRunningApplication.current.processIdentifier
        )

        #expect(window.frame == savedFrame)
    }

    @Test
    func scratchpadFirstOpenUsesOpticalPlacement() {
        let userDefaults = UserDefaults(suiteName: "RascTests.\(UUID().uuidString)")!
        let store = WindowFrameStore.scratchpad(userDefaults: userDefaults)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: RascWindowMetrics.scratchpadDefault),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )

        guard let screen = NSScreen.main else {
            Issue.record("No main screen available for window frame test")
            return
        }

        RascWindowPlacement.placeScratchpad(
            window: window,
            store: store,
            excludingProcessID: NSRunningApplication.current.processIdentifier,
            screens: [screen]
        )

        let geometric = WindowFramePlacement.centeredOrigin(
            for: window.frame.size,
            in: screen.visibleFrame
        )
        let contentSize = window.contentRect(forFrameRect: window.frame).size
        #expect(contentSize == RascWindowMetrics.scratchpadDefault)
        #expect(window.frame.origin.y < geometric.y)
    }
}

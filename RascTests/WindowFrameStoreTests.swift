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
            for: NSSize(width: 520, height: 340),
            in: visible
        )

        #expect(origin.x == 240)
        #expect(origin.y == 230)
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
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 340),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let offscreenFrame = NSRect(x: 9_000, y: 9_000, width: 520, height: 340)

        userDefaults.set(NSStringFromRect(offscreenFrame), forKey: "scratchpadWindowFrame")
        store.restore(into: window, on: NSScreen.main)

        guard let screen = NSScreen.main else {
            Issue.record("No main screen available for window frame test")
            return
        }

        #expect(WindowFramePlacement.isVisible(frame: window.frame, in: screen.visibleFrame))
    }
}

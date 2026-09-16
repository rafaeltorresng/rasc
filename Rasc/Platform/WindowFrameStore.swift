import AppKit
import CoreGraphics

@MainActor
struct WindowFrameStore {
    private let userDefaults: UserDefaults
    private let frameKey = "scratchpadWindowFrame"

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func restore(into window: NSWindow, on screen: NSScreen?) {
        guard let screen = screen ?? window.screen ?? NSScreen.main else { return }

        if let stored = storedFrame, isVisible(frame: stored, on: screen) {
            window.setFrame(stored, display: false)
            return
        }

        center(window, on: screen)
    }

    func save(_ window: NSWindow) {
        let frame = window.frame
        guard frame.width > 0, frame.height > 0 else { return }
        userDefaults.set(
            NSStringFromRect(NSRectToCGRect(frame)),
            forKey: frameKey
        )
    }

    private var storedFrame: NSRect? {
        guard let value = userDefaults.string(forKey: frameKey) else { return nil }
        let rect = NSRectFromString(value)
        guard rect.width > 0, rect.height > 0 else { return nil }
        return rect
    }

    private func isVisible(frame: NSRect, on screen: NSScreen) -> Bool {
        let visible = screen.visibleFrame
        let intersection = frame.intersection(visible)
        return intersection.width >= 120 && intersection.height >= 80
    }

    private func center(_ window: NSWindow, on screen: NSScreen) {
        let visible = screen.visibleFrame
        let origin = NSPoint(
            x: visible.midX - window.frame.width / 2,
            y: visible.midY - window.frame.height / 2
        )
        window.setFrameOrigin(origin)
    }
}

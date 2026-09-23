import AppKit
import CoreGraphics

enum WindowFramePlacement {
    static let minimumVisibleSize = NSSize(width: 120, height: 80)

    static func isVisible(frame: NSRect, in visibleFrame: NSRect) -> Bool {
        let intersection = frame.intersection(visibleFrame)
        return intersection.width >= minimumVisibleSize.width
            && intersection.height >= minimumVisibleSize.height
    }

    static func screenContaining(
        frame: NSRect,
        in screens: [NSScreen]
    ) -> NSScreen? {
        screens.first { isVisible(frame: frame, in: $0.visibleFrame) }
    }

    static func preferredScreen(
        frontmostWindowFrame: NSRect?,
        mouseLocation: NSPoint,
        screens: [NSScreen]
    ) -> NSScreen? {
        guard !screens.isEmpty else { return nil }

        if let frontmostWindowFrame,
           let screen = screens.first(where: { $0.frame.intersects(frontmostWindowFrame) }) {
            return screen
        }

        if let screen = screens.first(where: { $0.frame.contains(mouseLocation) }) {
            return screen
        }

        return NSScreen.main ?? screens.first
    }

    static func centeredOrigin(
        for windowSize: NSSize,
        in visibleFrame: NSRect
    ) -> NSPoint {
        NSPoint(
            x: visibleFrame.midX - windowSize.width / 2,
            y: visibleFrame.midY - windowSize.height / 2
        )
    }

    static func frontmostOnScreenWindowFrame(excludingProcessID: pid_t) -> NSRect? {
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return nil
        }

        for window in windowList {
            guard let ownerPID = window[kCGWindowOwnerPID as String] as? pid_t,
                  ownerPID != excludingProcessID,
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

    static func targetPresentationScreen(
        excludingProcessID: pid_t,
        screens: [NSScreen] = NSScreen.screens
    ) -> NSScreen? {
        preferredScreen(
            frontmostWindowFrame: frontmostOnScreenWindowFrame(excludingProcessID: excludingProcessID),
            mouseLocation: NSEvent.mouseLocation,
            screens: screens
        )
    }
}

@MainActor
struct WindowFrameStore {
    static let scratchpadFrameKey = "scratchpadWindowFrame"
    static let homeFrameKey = "homeWindowFrame"

    private let userDefaults: UserDefaults
    private let frameKey: String

    init(
        frameKey: String = WindowFrameStore.scratchpadFrameKey,
        userDefaults: UserDefaults = .standard
    ) {
        self.frameKey = frameKey
        self.userDefaults = userDefaults
    }

    static func scratchpad(userDefaults: UserDefaults = .standard) -> WindowFrameStore {
        WindowFrameStore(frameKey: scratchpadFrameKey, userDefaults: userDefaults)
    }

    static func home(userDefaults: UserDefaults = .standard) -> WindowFrameStore {
        WindowFrameStore(frameKey: homeFrameKey, userDefaults: userDefaults)
    }

    var hasSavedFrame: Bool {
        storedFrame != nil
    }

    func restore(
        into window: NSWindow,
        on preferredScreen: NSScreen?,
        initialPlacement: RascWindowInitialPlacement = .geometricCenter,
        screens: [NSScreen] = NSScreen.screens
    ) {
        guard !screens.isEmpty else { return }

        if let stored = storedFrame,
           WindowFramePlacement.screenContaining(frame: stored, in: screens) != nil {
            window.setFrame(stored, display: false)
            return
        }

        let targetScreen = preferredScreen
            ?? WindowFramePlacement.preferredScreen(
                frontmostWindowFrame: nil,
                mouseLocation: NSEvent.mouseLocation,
                screens: screens
            )
            ?? screens[0]
        placeInitially(window, on: targetScreen, initialPlacement: initialPlacement)
    }

    func ensureVisible(
        _ window: NSWindow,
        on preferredScreen: NSScreen?,
        initialPlacement: RascWindowInitialPlacement = .geometricCenter,
        screens: [NSScreen] = NSScreen.screens,
        reason: String
    ) {
        guard window.isVisible, !screens.isEmpty else { return }

        if WindowFramePlacement.screenContaining(frame: window.frame, in: screens) != nil {
            return
        }

        AppDiagnostics.panelRepositioned(reason: reason)
        restore(
            into: window,
            on: preferredScreen,
            initialPlacement: initialPlacement,
            screens: screens
        )
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

    private func placeInitially(
        _ window: NSWindow,
        on screen: NSScreen,
        initialPlacement: RascWindowInitialPlacement
    ) {
        window.setFrameOrigin(
            initialPlacement.origin(for: window.frame.size, in: screen.visibleFrame)
        )
    }
}

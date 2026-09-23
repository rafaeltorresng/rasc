import AppKit

enum RascWindowInitialPlacement: Equatable {
    case geometricCenter
    case opticalCenter(verticalRatio: CGFloat = 0.45)

    func origin(for windowSize: NSSize, in visibleFrame: NSRect) -> NSPoint {
        switch self {
        case .geometricCenter:
            WindowFramePlacement.centeredOrigin(for: windowSize, in: visibleFrame)
        case let .opticalCenter(verticalRatio):
            RascWindowPlacement.opticalCenterOrigin(
                for: windowSize,
                in: visibleFrame,
                verticalRatio: verticalRatio
            )
        }
    }
}

enum RascWindowPlacement {
    static let scratchpadOpticalVerticalRatio: CGFloat = 0.45

    static func opticalCenterOrigin(
        for windowSize: NSSize,
        in visibleFrame: NSRect,
        verticalRatio: CGFloat = scratchpadOpticalVerticalRatio
    ) -> NSPoint {
        NSPoint(
            x: visibleFrame.midX - windowSize.width / 2,
            y: visibleFrame.minY + visibleFrame.height * verticalRatio - windowSize.height / 2
        )
    }

    @MainActor
    static func placeScratchpad(
        window: NSWindow,
        store: WindowFrameStore,
        excludingProcessID: pid_t,
        screens: [NSScreen] = NSScreen.screens
    ) {
        if !store.hasSavedFrame {
            window.setContentSize(RascWindowMetrics.scratchpadDefault)
        }

        store.restore(
            into: window,
            on: presentationScreen(excludingProcessID: excludingProcessID, screens: screens),
            initialPlacement: .opticalCenter(),
            screens: screens
        )
    }

    @MainActor
    static func ensureScratchpadVisible(
        window: NSWindow,
        store: WindowFrameStore,
        excludingProcessID: pid_t,
        reason: String,
        screens: [NSScreen] = NSScreen.screens
    ) {
        store.ensureVisible(
            window,
            on: presentationScreen(excludingProcessID: excludingProcessID, screens: screens),
            initialPlacement: .opticalCenter(),
            screens: screens,
            reason: reason
        )
    }

    @MainActor
    static func placeHome(
        window: NSWindow,
        store: WindowFrameStore,
        excludingProcessID: pid_t,
        screens: [NSScreen] = NSScreen.screens
    ) {
        if !store.hasSavedFrame {
            window.setContentSize(RascWindowMetrics.homeDefault)
        }

        store.restore(
            into: window,
            on: presentationScreen(excludingProcessID: excludingProcessID, screens: screens),
            initialPlacement: .geometricCenter,
            screens: screens
        )
    }

    @MainActor
    static func ensureHomeVisible(
        window: NSWindow,
        store: WindowFrameStore,
        excludingProcessID: pid_t,
        reason: String,
        screens: [NSScreen] = NSScreen.screens
    ) {
        store.ensureVisible(
            window,
            on: presentationScreen(excludingProcessID: excludingProcessID, screens: screens),
            initialPlacement: .geometricCenter,
            screens: screens,
            reason: reason
        )
    }

    @MainActor
    static func placeOnboarding(
        window: NSWindow,
        excludingProcessID: pid_t,
        screens: [NSScreen] = NSScreen.screens
    ) {
        window.setContentSize(RascWindowMetrics.onboarding)

        guard let screen = presentationScreen(excludingProcessID: excludingProcessID, screens: screens)
            ?? screens.first
        else {
            return
        }

        window.setFrameOrigin(
            RascWindowInitialPlacement.geometricCenter.origin(
                for: window.frame.size,
                in: screen.visibleFrame
            )
        )
    }

    private static func presentationScreen(
        excludingProcessID: pid_t,
        screens: [NSScreen]
    ) -> NSScreen? {
        WindowFramePlacement.targetPresentationScreen(
            excludingProcessID: excludingProcessID,
            screens: screens
        )
    }
}

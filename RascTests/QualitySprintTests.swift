import AppKit
import Testing
@testable import Rasc

@Suite
struct DisplayCoordinateTests {
    @Test
    func quartzBoundsOnTheLowerDisplayBecomeAppKitCoordinates() {
        let primaryHeight: CGFloat = 1080
        let appKitOnLowerDisplay = NSRect(x: 200, y: -800, width: 800, height: 500)
        let quartzY = primaryHeight - appKitOnLowerDisplay.origin.y - appKitOnLowerDisplay.height
        let quartz = NSRect(x: 200, y: quartzY, width: 800, height: 500)

        let converted = WindowFramePlacement.appKitFrame(
            fromQuartzBounds: quartz,
            primaryScreenHeight: primaryHeight
        )

        #expect(converted == appKitOnLowerDisplay)

        let screens = [
            NSScreenFrame(frame: NSRect(x: 0, y: 0, width: 1920, height: 1080)),
            NSScreenFrame(frame: NSRect(x: 138, y: -982, width: 1512, height: 982)),
        ]
        let upper = screens[0].frame
        let lower = screens[1].frame
        #expect(lower.intersects(converted))
        #expect(!upper.intersects(converted))
    }
}

private struct NSScreenFrame {
    let frame: NSRect
}

@Suite
struct ScratchpadPanelLevelPolicyTests {
    @Test
    func keepsScreenSaverUnlessHomeOrAMenuNeedsThePanelLower() {
        #expect(
            ScratchpadPanelLevelPolicy.level(
                homeIsVisible: false,
                appIsActive: true,
                menuIsTracking: false
            ) == .screenSaver
        )
        #expect(
            ScratchpadPanelLevelPolicy.level(
                homeIsVisible: false,
                appIsActive: false,
                menuIsTracking: false
            ) == .screenSaver
        )
        #expect(
            ScratchpadPanelLevelPolicy.level(
                homeIsVisible: true,
                appIsActive: true,
                menuIsTracking: false
            ) == .normal
        )
        #expect(
            ScratchpadPanelLevelPolicy.level(
                homeIsVisible: true,
                appIsActive: false,
                menuIsTracking: false
            ) == .screenSaver
        )
        #expect(
            ScratchpadPanelLevelPolicy.level(
                homeIsVisible: false,
                appIsActive: true,
                menuIsTracking: true
            ) == .floating
        )
        #expect(
            ScratchpadPanelLevelPolicy.level(
                homeIsVisible: false,
                appIsActive: true,
                menuIsTracking: false,
                systemInteractionNeedsPriority: true
            ) == .normal
        )
    }

    @Test
    func securityAlertsLowerThePanelAndTheMenuBarDoesNot() {
        let menuBar = PanelOcclusionWindow(ownerPID: 1, ownerName: "Window Server", layer: 24, width: 1512, height: 33)
        let appStrip = PanelOcclusionWindow(ownerPID: 4, ownerName: "Cursor", layer: 26, width: 1512, height: 65)
        let alert = PanelOcclusionWindow(ownerPID: 2, ownerName: "SecurityAgent", layer: 8, width: 420, height: 220)
        let fullscreen = PanelOcclusionWindow(ownerPID: 3, ownerName: "Safari", layer: 0, width: 1920, height: 1080)

        #expect(!ScratchpadPanelLevelPolicy.systemInteractionNeedsPriority(windows: [menuBar, fullscreen, appStrip], ourPID: 9))
        #expect(ScratchpadPanelLevelPolicy.systemInteractionNeedsPriority(windows: [menuBar, alert], ourPID: 9))
        #expect(!ScratchpadPanelLevelPolicy.systemInteractionNeedsPriority(windows: [alert], ourPID: 2))
    }
}

@Suite
struct SettingsWindowFitTests {
    @Test
    func settingsMinimumHeightFitsTheVisibleFrame() {
        #expect(SettingsWindowPresentation.fittedMinimumHeight(visibleHeight: 900) == 680)
        #expect(SettingsWindowPresentation.fittedMinimumHeight(visibleHeight: 520) == 484)
        #expect(SettingsWindowPresentation.fittedMinimumHeight(visibleHeight: 300) == 360)
    }
}

@Suite
struct ShortcutKeycapTokenTests {
    @Test
    func splitsModifierGlyphsWithoutSpaces() {
        #expect(ShortcutKeycapView.tokens(in: "⌘N") == ["⌘", "N"])
        #expect(ShortcutKeycapView.tokens(in: "⇧⌘K") == ["⇧", "⌘", "K"])
        #expect(ShortcutKeycapView.tokens(in: "⌘⌥\\") == ["⌘", "⌥", "\\"])
        #expect(ShortcutKeycapView.tokens(in: "Esc") == ["Esc"])
    }
}

@MainActor
@Suite
struct InternalShortcutStoreTests {
    @Test
    func rejectsConflictsAndKeepsDefaults() throws {
        let suite = "RascTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let store = InternalShortcutStore(userDefaults: defaults)

        #expect(store.displayString(for: .keep) == "⇧⌘K")
        #expect(store.displayString(for: .commandPalette) == "⌘K")

        let blocked = store.assign(InternalShortcut(key: "k", command: true), to: .keep)
        #expect(blocked == "Already used by Command Palette.")
        #expect(store.displayString(for: .keep) == "⇧⌘K")

        let system = store.assign(InternalShortcut(key: "w", command: true), to: .search)
        #expect(system == "That shortcut belongs to macOS.")

        let moved = store.assign(InternalShortcut(key: "k", command: true), to: .commandPalette)
        #expect(moved == nil)
        let keepOnCommandK = store.assign(InternalShortcut(key: "k", command: true, shift: true), to: .commandPalette)
        #expect(keepOnCommandK == "Already used by Keep.")

        store.restoreDefaults()
        #expect(store.displayString(for: .commandPalette) == "⌘K")
        defaults.removePersistentDomain(forName: suite)
    }
}

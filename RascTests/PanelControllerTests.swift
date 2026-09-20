import AppKit
import SwiftUI
import Testing
@testable import Rasc

@Suite(.serialized)
@MainActor
struct PanelControllerTests {
    @Test
    func appDisallowsMultipleSimultaneousInstances() {
        let appBundle = Bundle(for: PanelController.self)

        #expect(appBundle.object(forInfoDictionaryKey: "LSMultipleInstancesProhibited") as? Bool == true)
    }

    @Test
    func appRunsAsMenuBarUtilityWithoutDockIcon() {
        let appBundle = Bundle(for: PanelController.self)

        #expect(appBundle.object(forInfoDictionaryKey: "LSUIElement") as? Bool == true)
    }

    @Test
    func configuresPanelForFullscreenOverlayScratchpadBehavior() throws {
        let controller = try makeController()
        let panel = controller.panel

        #expect(panel is ScratchpadPanel)
        #expect((panel as? ScratchpadPanel)?.canBecomeKey == true)
        #expect(panel.isFloatingPanel)
        #expect(!panel.hidesOnDeactivate)
        #expect(!panel.becomesKeyOnlyIfNeeded)
        #expect(panel.level == .screenSaver)
        #expect(panel.styleMask.contains(.titled))
        #expect(panel.styleMask.contains(.resizable))
        #expect(panel.styleMask.contains(.fullSizeContentView))
        #expect(panel.styleMask.contains(.nonactivatingPanel))
        #expect(panel.collectionBehavior.contains(.canJoinAllSpaces))
        #expect(panel.collectionBehavior.contains(.canJoinAllApplications))
        #expect(panel.collectionBehavior.contains(.fullScreenAuxiliary))
        #expect(panel.collectionBehavior.contains(.stationary))
        #expect(!panel.collectionBehavior.contains(.moveToActiveSpace))
        #expect(!panel.collectionBehavior.contains(.transient))
        #expect(!panel.collectionBehavior.contains(.fullScreenNone))
    }

    @Test
    func preventsSystemZoomFromExpandingTheScratchpad() throws {
        let controller = try makeController()
        let shouldZoom = controller.panel.delegate?.windowShouldZoom?(
            controller.panel,
            toFrame: NSRect(x: 0, y: 0, width: 1_500, height: 900)
        )

        #expect(shouldZoom == false)
        #expect(controller.panel.standardWindowButton(.zoomButton)?.isEnabled == false)
    }

    @Test
    func hidesTrafficLightsWithoutRemovingNativeWindowBehavior() throws {
        let panel = try makeController().panel

        #expect(panel.standardWindowButton(.closeButton)?.isHidden == true)
        #expect(panel.standardWindowButton(.miniaturizeButton)?.isHidden == true)
        #expect(panel.standardWindowButton(.zoomButton)?.isHidden == true)
        #expect(panel.styleMask.contains(.titled))
        #expect(panel.styleMask.contains(.resizable))
        #expect(panel.styleMask.contains(.fullSizeContentView))
        #expect(panel.styleMask.contains(.nonactivatingPanel))
    }

    @Test
    func toggleHidesAVisiblePanel() async throws {
        let controller = try makeController()
        controller.panel.orderFront(nil)

        await controller.toggle()

        #expect(!controller.panel.isVisible)
    }

    @Test
    func restoresAndPersistsWindowFrame() throws {
        let userDefaults = UserDefaults(suiteName: "RascTests.\(UUID().uuidString)")!
        let store = WindowFrameStore(userDefaults: userDefaults)
        let controller = try makeController(windowFrameStore: store)
        let targetFrame = NSRect(x: 120, y: 180, width: 540, height: 360)

        controller.panel.setFrame(targetFrame, display: false)
        store.save(controller.panel)

        let restoredController = try makeController(windowFrameStore: store)
        restoredController.panel.setFrame(.zero, display: false)
        store.restore(into: restoredController.panel, on: NSScreen.main)

        #expect(restoredController.panel.frame == targetFrame)
    }

    @Test
    func hostingControllerDoesNotExpandToContentIdealSize() throws {
        let controller = try makeController()

        #expect(controller.contentHostingSizingOptions == [.minSize])
    }

    @Test
    func switchingSurfacesPreservesPanelFrame() async throws {
        let controller = try makeController()
        let fixedFrame = NSRect(x: 100, y: 200, width: 520, height: 340)
        controller.panel.setFrame(fixedFrame, display: false)

        await controller.openCommandPalette()
        #expect(controller.panel.frame == fixedFrame)

        controller.scratchpadSession.closeCommandPalette()
        #expect(controller.panel.frame == fixedFrame)

        try await controller.openSearch()
        #expect(controller.panel.frame == fixedFrame)

        controller.scratchpadSession.closeSearch()
        #expect(controller.panel.frame == fixedFrame)
    }

    @Test
    func searchFieldRoutesNativeNavigationAndSubmitCommands() {
        var commands: [HistorySearchCommand] = []
        let searchField = HistorySearchTextField(
            text: .constant(""),
            isFocused: .constant(false),
            focusRequest: 0,
            onCommand: { commands.append($0) }
        )
        let coordinator = searchField.makeCoordinator()
        let textField = NSTextField()
        let textView = NSTextView()

        #expect(coordinator.control(
            textField,
            textView: textView,
            doCommandBy: #selector(NSResponder.moveUp(_:))
        ))
        #expect(coordinator.control(
            textField,
            textView: textView,
            doCommandBy: #selector(NSResponder.moveDown(_:))
        ))
        #expect(coordinator.control(
            textField,
            textView: textView,
            doCommandBy: #selector(NSResponder.insertNewline(_:))
        ))
        #expect(coordinator.control(
            textField,
            textView: textView,
            doCommandBy: #selector(NSResponder.cancelOperation(_:))
        ))

        #expect(commands == [.moveUp, .moveDown, .openSelection, .closeSearch])
    }

    private func makeController(
        windowFrameStore: WindowFrameStore = WindowFrameStore()
    ) throws -> PanelController {
        let databaseURL = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appendingPathExtension("sqlite")
        return PanelController(
            repository: try NoteRepository(databaseURL: databaseURL),
            windowFrameStore: windowFrameStore
        )
    }
}

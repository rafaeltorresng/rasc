import AppKit
import Testing
@testable import Rasc

@Suite(.serialized)
@MainActor
struct PanelControllerTests {
    @Test
    func configuresPanelForPersistentFloatingScratchpadBehavior() throws {
        let controller = try makeController()
        let panel = controller.panel

        #expect(panel.isFloatingPanel)
        #expect(!panel.hidesOnDeactivate)
        #expect(!panel.becomesKeyOnlyIfNeeded)
        #expect(panel.level == .floating)
        #expect(panel.styleMask.contains(.titled))
        #expect(panel.styleMask.contains(.resizable))
        #expect(panel.styleMask.contains(.fullSizeContentView))
        #expect(panel.styleMask.contains(.nonactivatingPanel))
        #expect(panel.collectionBehavior.contains(.moveToActiveSpace))
        #expect(panel.collectionBehavior.contains(.transient))
        #expect(panel.collectionBehavior.contains(.canJoinAllApplications))
        #expect(panel.collectionBehavior.contains(.fullScreenNone))
        #expect(!panel.collectionBehavior.contains(.fullScreenAuxiliary))
        #expect(!panel.collectionBehavior.contains(.canJoinAllSpaces))
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
    func toggleHidesAVisiblePanel() async throws {
        let controller = try makeController()
        controller.panel.orderFront(nil)

        await controller.toggle()

        #expect(!controller.panel.isVisible)
    }

    private func makeController() throws -> PanelController {
        let databaseURL = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appendingPathExtension("sqlite")
        return PanelController(repository: try NoteRepository(databaseURL: databaseURL))
    }
}

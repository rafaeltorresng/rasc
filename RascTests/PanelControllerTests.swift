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
    func orbVisibilityFollowsWindowPresentationAndHiding() async throws {
        let controller = try makeController()
        // Other native suites run concurrently; keep this observer window unoccluded.
        controller.panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 20)
        controller.panel.animationBehavior = .none
        let observer = OrbWindowVisibilityView()
        var visible = false
        observer.onVisibilityChange = { visible = $0 }
        controller.panel.setFrame(NSRect(x: 220, y: 240, width: 640, height: 420), display: false)
        controller.panel.contentView?.addSubview(observer)
        #expect(await waitUntil { !visible })

        controller.panel.orderFrontRegardless()
        #expect(await waitUntil { visible })

        controller.panel.orderOut(nil)
        #expect(await waitUntil { !visible })

        controller.panel.orderFrontRegardless()
        #expect(await waitUntil { visible })
        controller.panel.orderOut(nil)
    }

    @Test
    func detachingAnOrbFromItsWindowPausesIt() async throws {
        let controller = try makeController()
        controller.panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 20)
        controller.panel.animationBehavior = .none
        let observer = OrbWindowVisibilityView()
        var visible = false
        observer.onVisibilityChange = { visible = $0 }
        controller.panel.setFrame(NSRect(x: 220, y: 240, width: 640, height: 420), display: false)
        controller.panel.contentView?.addSubview(observer)
        controller.panel.orderFrontRegardless()
        #expect(await waitUntil { visible })

        observer.removeFromSuperview()
        #expect(await waitUntil { !visible })
        controller.panel.orderOut(nil)
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
        let userDefaults = UserDefaults(suiteName: "RascTests.\(UUID().uuidString)")!
        let store = WindowFrameStore.scratchpad(userDefaults: userDefaults)
        let controller = try makeController(windowFrameStore: store)
        let fixedFrame = NSRect(x: 100, y: 200, width: 520, height: 340)
        controller.panel.setFrame(fixedFrame, display: false)
        store.save(controller.panel)

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
    func transientPanelAutoSizesAtTheDefaultSizeAndRestoresItOnReturnToTheEditor() async throws {
        let userDefaults = UserDefaults(suiteName: "RascTests.\(UUID().uuidString)")!
        let store = WindowFrameStore.scratchpad(userDefaults: userDefaults)
        let controller = try makeController(windowFrameStore: store)
        defer { controller.panel.orderOut(nil) }

        await controller.openCommandPalette()
        let paletteHeight = controller.panel.frame.height
        let expectedPalette = RascTransientPanelSizing.paletteHeight(commandCount: controller.scratchpadSession.filteredCommands.count)
        #expect(paletteHeight == expectedPalette)
        #expect(paletteHeight < RascWindowMetrics.scratchpadDefault.height)

        controller.scratchpadSession.closeCommandPalette()
        #expect(controller.panel.frame.height == RascWindowMetrics.scratchpadDefault.height)

        try await controller.openSearch()
        #expect(controller.panel.frame.height == RascTransientPanelSizing.searchHeight(resultCount: controller.scratchpadSession.searchResults.count))
        #expect(controller.panel.frame.height <= RascWindowMetrics.scratchpadDefault.height)

        controller.scratchpadSession.closeSearch()
        #expect(controller.panel.frame.height == RascWindowMetrics.scratchpadDefault.height)
    }

    @Test
    func transientPanelAutoSizesWithVoiceCommandsAndRestoresDefaultOnReturnToEditor() async throws {
        let userDefaults = UserDefaults(suiteName: "RascTests.\(UUID().uuidString)")!
        let store = WindowFrameStore.scratchpad(userDefaults: userDefaults)
        let controller = try makeController(
            windowFrameStore: store,
            includesVoiceCapture: { true }
        )
        defer { controller.panel.orderOut(nil) }

        await controller.openCommandPalette()
        let paletteHeight = controller.panel.frame.height
        let expectedPalette = RascTransientPanelSizing.paletteHeight(commandCount: controller.scratchpadSession.filteredCommands.count)
        #expect(paletteHeight == expectedPalette)
        #expect(paletteHeight <= RascTransientPanelSizing.maximumHeight)

        controller.scratchpadSession.closeCommandPalette()
        #expect(controller.panel.frame.height == RascWindowMetrics.scratchpadDefault.height)
    }

    @Test
    func occlusionWindowOnPanelScreenLowersLevelAndEmptyRestoresScreenSaver() throws {
        @MainActor
        final class OcclusionState {
            var occluded = false
            var bounds: CGRect = .zero
        }
        let state = OcclusionState()
        let controller = try makeController(occlusionWindowsProvider: {
            guard state.occluded else { return [] }
            return [
                PanelOcclusionWindow(
                    ownerPID: ProcessInfo.processInfo.processIdentifier + 1,
                    ownerName: "SecurityAgent",
                    layer: ScratchpadPanelLevelPolicy.modalLayer,
                    width: state.bounds.width,
                    height: state.bounds.height,
                    bounds: state.bounds
                )
            ]
        })
        defer { controller.panel.orderOut(nil) }

        controller.panel.setFrame(NSRect(x: 200, y: 200, width: 500, height: 330), display: false)
        controller.panel.orderFrontRegardless()
        let screen = controller.panel.screen ?? NSScreen.main ?? NSScreen.screens.first
        let primaryHeight = (NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.screens.first)?.frame.height
            ?? screen?.frame.maxY
            ?? 900
        let originX = (screen?.frame.minX ?? 0) + 100
        let originY = primaryHeight - (screen?.frame.maxY ?? 900) + 100
        state.bounds = CGRect(x: originX, y: originY, width: 400, height: 260)

        #expect(controller.panel.level == .screenSaver)
        state.occluded = true
        controller.noteHomeVisibility(false)
        #expect(controller.panel.level == .normal)

        state.occluded = false
        controller.noteHomeVisibility(false)
        #expect(controller.panel.level == .screenSaver)
    }

    @Test
    func showWhileVisiblePreservesUnsavedTypingInsideAutosaveDebounce() async throws {
        let controller = try makeController()
        defer { controller.panel.orderOut(nil) }
        controller.panel.setFrame(NSRect(x: 220, y: 240, width: 500, height: 330), display: false)
        controller.panel.orderFrontRegardless()

        controller.scratchpadSession.text = "in-flight typing"
        await controller.show()

        #expect(controller.scratchpadSession.text == "in-flight typing")
    }

    @Test
    func undoSurvivesOpeningAndClosingCommandPalette() async throws {
        let controller = try makeController()
        defer { controller.panel.orderOut(nil) }
        controller.panel.setFrame(NSRect(x: 220, y: 240, width: 640, height: 420), display: true)
        controller.panel.orderFrontRegardless()

        let session = controller.scratchpadSession
        session.text = "preserve undo across palette"
        try await session.flush()

        guard let textView = await waitForTextView(in: controller.panel, showing: "preserve undo across palette") else {
            Issue.record("The scratchpad editor did not install a text view")
            return
        }
        controller.panel.makeKey()
        _ = controller.panel.makeFirstResponder(textView)
        textView.selectAll(nil)
        textView.deleteBackward(nil)
        #expect(await waitUntil { session.text.isEmpty })

        await controller.openCommandPalette()
        #expect(session.surface == .commandPalette)
        try await Task.sleep(for: .milliseconds(80))
        session.closeCommandPalette()
        #expect(session.surface == .editor)
        #expect(await waitUntil { textView.isEditable })

        textView.undoManager?.undo()
        #expect(await waitUntil { session.text == "preserve undo across palette" })
    }

    @Test
    func escapeDuringRefiningCancelsBackToEditor() async throws {
        let controller = try makeController(refinementProvider: SlowRefinementProvider())
        defer { controller.panel.orderOut(nil) }
        controller.panel.setFrame(NSRect(x: 240, y: 260, width: 640, height: 420), display: false)
        controller.panel.orderFrontRegardless()
        let session = controller.scratchpadSession
        session.text = "slow refinement"
        session.startRefinement()
        #expect(await waitUntil { session.surface == .refining })

        if let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: controller.panel.windowNumber,
            context: nil,
            characters: "\u{1b}",
            charactersIgnoringModifiers: "\u{1b}",
            isARepeat: false,
            keyCode: 53
        ) {
            controller.panel.sendEvent(event)
        }

        #expect(await waitUntil { session.surface == .editor })
        #expect(controller.panel.isVisible)
    }

    @Test
    func toggleDoesNotHidePanelWhileSheetIsAttached() async throws {
        let controller = try makeController()
        defer { controller.panel.orderOut(nil) }
        controller.panel.setFrame(NSRect(x: 240, y: 260, width: 500, height: 330), display: false)
        controller.panel.orderFrontRegardless()

        let sheet = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 220, height: 120),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        sheet.isReleasedWhenClosed = false
        controller.panel.beginSheet(sheet) { _ in }
        defer { controller.panel.endSheet(sheet) }

        await controller.toggle()
        #expect(controller.panel.isVisible)
        #expect(controller.panel.attachedSheet === sheet)
    }

    @Test
    func startNewScratchUsesTheSameEntryPointAsCommandN() async throws {
        let controller = try makeController()
        defer { controller.panel.orderOut(nil) }
        controller.scratchpadSession.text = "previous thought"
        let focusBefore = controller.scratchpadSession.focusRequest

        await controller.startNewScratch()

        #expect(controller.scratchpadSession.text.isEmpty)
        #expect(controller.scratchpadSession.surface == .editor)
        #expect(controller.scratchpadSession.focusRequest > focusBefore)
        #expect(controller.scratchpadSession.saveErrorMessage == nil)
        #expect(controller.scratchpadSession.isActiveNoteKept == false)
        let stored = try #require(try await controller.repository.fetchMostRecent())
        #expect(stored.content == "previous thought")
        #expect(stored.isKept == false)
    }

    @Test
    func startNewScratchKeepsTheVisibleScratchWhenPersistenceFails() async throws {
        let controller = try makeController()
        defer { controller.panel.orderOut(nil) }
        controller.scratchpadSession.text = "do not lose this"
        try await controller.scratchpadSession.flush()
        try controller.repository.closeForTesting()

        await controller.startNewScratch()

        #expect(controller.scratchpadSession.text == "do not lose this")
        #expect(controller.scratchpadSession.saveErrorMessage == "Couldn't save locally.")
        #expect(controller.scratchpadSession.isActiveNoteKept == false)
    }

    @Test
    func transientInputFieldRoutesNativeNavigationAndSubmitCommands() {
        var commands: [RascTransientFieldCommand] = []
        let searchField = RascTransientInputTextField(
            text: .constant(""),
            isFocused: .constant(false),
            focusRequest: 0,
            placeholder: "Search thoughts…",
            accessibilityLabel: "Search thoughts",
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

        #expect(commands == [.moveUp, .moveDown, .execute, .close])
    }

    @Test
    func reassigningKeepUpdatesTheMenuItemImmediately() {
        let keep = NSMenuItem(title: "Keep", action: nil, keyEquivalent: "k")
        keep.keyEquivalentModifierMask = [.command, .shift]
        let palette = NSMenuItem(title: "Command Palette", action: nil, keyEquivalent: "k")
        palette.keyEquivalentModifierMask = [.command]
        let menu = NSMenu()
        menu.addItem(keep)
        menu.addItem(palette)
        let top = NSMenuItem()
        top.submenu = menu
        let main = NSMenu()
        main.addItem(top)
        let previous = NSApp.mainMenu
        NSApp.mainMenu = main
        defer {
            InternalShortcutStore.shared.restoreDefaults()
            NSApp.mainMenu = previous
        }

        let store = InternalShortcutStore.shared
        store.restoreDefaults()
        #expect(store.assign(InternalShortcut(key: "k", command: true), to: .keep) == "Already used by Command Palette.")
        #expect(keep.keyEquivalentModifierMask.contains(.shift))

        #expect(store.assign(InternalShortcut(key: "l", command: true), to: .commandPalette) == nil)
        #expect(store.assign(InternalShortcut(key: "k", command: true), to: .keep) == nil)
        #expect(palette.keyEquivalent == "l")
        #expect(keep.keyEquivalent == "k")
        #expect(keep.keyEquivalentModifierMask.contains(.command))
        #expect(!keep.keyEquivalentModifierMask.contains(.shift))

        keep.keyEquivalent = "j"
        keep.keyEquivalentModifierMask = [.command, .option]
        MainMenuShortcutBridge.shared.menuWillOpen(menu)
        #expect(keep.keyEquivalent == "k")
        #expect(keep.keyEquivalentModifierMask.contains(.command))
        #expect(!keep.keyEquivalentModifierMask.contains(.shift))
        #expect(!keep.keyEquivalentModifierMask.contains(.option))
    }

    @Test
    func testHostOpensAnIsolatedDatabase() throws {
        let url = try NoteRepository.defaultDatabaseURL
        TestHostIsolation.assertNotPersonal(url)
        #expect(url.path.contains("RascIsolatedHost"))
        #expect(url.path.contains("/T/") || url.path.contains("/tmp/") || url.path.contains("/var/folders/"))

        let probe = "rasc-isolation-\(UUID().uuidString)"
        UserDefaults.standard.set(probe, forKey: "rascIsolationProbe")
        let personal = UserDefaults(suiteName: "com.rafaeltorres.rasc")
        defer {
            UserDefaults.standard.removeObject(forKey: "rascIsolationProbe")
            personal?.removeObject(forKey: "rascIsolationProbe")
        }
        #expect(personal?.string(forKey: "rascIsolationProbe") == nil)
        #expect(UserDefaults.standard.string(forKey: "rascIsolationProbe") == probe)
    }

    @Test
    func undoAfterClearingTheEditorRestoresTheSameNote() async throws {
        let controller = try makeController()
        defer { controller.panel.orderOut(nil) }
        controller.panel.setFrame(NSRect(x: 220, y: 240, width: 640, height: 420), display: true)
        controller.panel.orderFrontRegardless()

        let session = controller.scratchpadSession
        session.text = "call back tomorrow"
        try await session.flush()
        let noteID = try #require(try await controller.repository.fetchMostRecent()).id

        guard let textView = await waitForTextView(in: controller.panel) else {
            Issue.record("The scratchpad editor did not install a text view")
            return
        }
        controller.panel.makeKey()
        _ = controller.panel.makeFirstResponder(textView)
        textView.selectAll(nil)
        textView.deleteBackward(nil)
        try await Task.sleep(for: .milliseconds(80))

        #expect(session.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        textView.undoManager?.undo()
        try await Task.sleep(for: .milliseconds(80))

        #expect(session.text == "call back tomorrow")
        try await session.flush()
        let restored = try #require(try await controller.repository.fetch(id: noteID))
        #expect(restored.content == "call back tomorrow")
        #expect(restored.deletedAt == nil)
        #expect(try await controller.repository.fetchAllNonDeleted().count == 1)
    }

    @Test
    func undoAfterClearingAKeptNoteKeepsTheSameIdentity() async throws {
        let controller = try makeController()
        defer { controller.panel.orderOut(nil) }
        controller.panel.setFrame(NSRect(x: 220, y: 240, width: 640, height: 420), display: true)
        controller.panel.orderFrontRegardless()

        let session = controller.scratchpadSession
        session.text = "keep this thought"
        try await session.flush()
        let outcome = try await session.keepActiveNote()
        #expect(outcome == .keptShouldHide)
        let kept = try #require(try await controller.repository.fetchMostRecent())
        #expect(kept.keptAt != nil)
        #expect(session.text.isEmpty)

        let opened = try await session.openNote(id: kept.id)
        #expect(opened)
        #expect(session.text == "keep this thought")

        guard let textView = await waitForTextView(in: controller.panel, showing: "keep this thought") else {
            Issue.record("The scratchpad editor did not show the reopened note")
            return
        }
        controller.panel.makeKey()
        _ = controller.panel.makeFirstResponder(textView)
        textView.selectAll(nil)
        textView.deleteBackward(nil)
        #expect(await waitUntil { session.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })

        textView.undoManager?.undo()
        #expect(await waitUntil { session.text == "keep this thought" })
        try await session.flush()
        let restored = try #require(try await controller.repository.fetch(id: kept.id))
        #expect(restored.content == "keep this thought")
        #expect(restored.keptAt != nil)
        #expect(try await controller.repository.fetchAllNonDeleted().count == 1)
    }

    @Test
    func plainArrowKeysCycleTheRefinementPreviewModes() async throws {
        let controller = try makeController(refinementProvider: PreviewArrowRefinementProvider())
        defer { controller.panel.orderOut(nil) }
        let session = controller.scratchpadSession
        session.text = "draft the memo on friday please"
        session.startRefinement()
        let reached = await waitUntil { session.surface == .refinementPreview }
        #expect(reached)
        #expect(session.previewMode == .suggested)

        controller.panel.setFrame(NSRect(x: 240, y: 260, width: 640, height: 420), display: false)
        controller.panel.orderFrontRegardless()
        controller.panel.makeKey()

        func pressArrow(_ character: String, keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags = [.function]) {
            guard let event = NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: modifierFlags,
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: controller.panel.windowNumber,
                context: nil,
                characters: character,
                charactersIgnoringModifiers: character,
                isARepeat: false,
                keyCode: keyCode
            ) else { return }
            NSApp.sendEvent(event)
        }

        // Arrows report the Function flag, so the interception must not require
        // an empty modifier set (regression: plain arrows did nothing).
        pressArrow("\u{F703}", keyCode: 124) // right
        #expect(session.previewMode == .changes)
        pressArrow("\u{F703}", keyCode: 124) // right
        #expect(session.previewMode == .original)
        pressArrow("\u{F703}", keyCode: 124) // right, clamped at Original
        #expect(session.previewMode == .original)
        pressArrow("\u{F702}", keyCode: 123) // left
        #expect(session.previewMode == .changes)
        pressArrow("\u{F702}", keyCode: 123, modifierFlags: [.function, .command]) // ⌘→ passes through
        #expect(session.previewMode == .changes)
    }

    @Test
    func commandWHidesTheKeyPanelWithoutDiscarding() async throws {
        let controller = try makeController()
        defer { controller.panel.orderOut(nil) }
        controller.panel.setFrame(NSRect(x: 240, y: 260, width: 640, height: 420), display: false)
        controller.panel.orderFrontRegardless()
        let session = controller.scratchpadSession
        session.text = "still here"
        try await session.flush()
        controller.panel.makeKey()

        let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .command,
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: controller.panel.windowNumber,
            context: nil,
            characters: "w",
            charactersIgnoringModifiers: "w",
            isARepeat: false,
            keyCode: 13
        )
        if let event {
            NSApp.sendEvent(event)
        }
        try await Task.sleep(for: .milliseconds(200))

        #expect(!controller.panel.isVisible)
        let note = try #require(try await controller.repository.fetchMostRecent())
        #expect(note.content == "still here")
        #expect(note.deletedAt == nil)
    }

    private func waitForTextView(in panel: NSPanel) async -> NSTextView? {
        for _ in 0..<30 {
            if let textView = firstTextView(in: panel.contentView) {
                return textView
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return nil
    }

    private func waitForTextView(in panel: NSPanel, showing expected: String) async -> NSTextView? {
        for _ in 0..<40 {
            if let textView = firstTextView(in: panel.contentView), textView.string == expected {
                return textView
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return nil
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async -> Bool {
        for _ in 0..<40 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return condition()
    }

    private func firstTextView(in view: NSView?) -> NSTextView? {
        guard let view else { return nil }
        if let textView = view as? NSTextView { return textView }
        for subview in view.subviews {
            if let textView = firstTextView(in: subview) { return textView }
        }
        return nil
    }

    private func makeController(
        windowFrameStore: WindowFrameStore = WindowFrameStore(),
        refinementProvider: (any RefinementProvider)? = nil,
        occlusionWindowsProvider: @escaping @MainActor () -> [PanelOcclusionWindow] = { [] },
        includesVoiceCapture: @escaping @MainActor () -> Bool = { false }
    ) throws -> PanelController {
        let databaseURL = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appendingPathExtension("sqlite")
        return PanelController(
            repository: try NoteRepository(databaseURL: databaseURL),
            refinementProvider: refinementProvider ?? FoundationModelsRefinementProvider(),
            windowFrameStore: windowFrameStore,
            occlusionWindowsProvider: occlusionWindowsProvider,
            includesVoiceCapture: includesVoiceCapture
        )
    }
}

private struct PreviewArrowRefinementProvider: RefinementProvider {
    let metadata = RefinementMetadata(
        provider: "panel-test",
        modelIdentifier: "panel-test",
        promptVersion: "panel-test"
    )

    func availability(for _: RefinementRequest) async -> RefinementAvailability {
        .available
    }

    func refine(_ request: RefinementRequest) async throws -> RefinementResult {
        RefinementResult(
            decision: .changed,
            kind: .messyText,
            text: "Suggested rewrite of the memo"
        )
    }
}

private struct SlowRefinementProvider: RefinementProvider {
    let metadata = RefinementMetadata(
        provider: "slow-test",
        modelIdentifier: "slow-test",
        promptVersion: "slow-test"
    )

    func availability(for _: RefinementRequest) async -> RefinementAvailability {
        .available
    }

    func refine(_ request: RefinementRequest) async throws -> RefinementResult {
        try await Task.sleep(for: .seconds(5))
        return RefinementResult(decision: .noChange, kind: .messyText, text: request.inputText)
    }
}

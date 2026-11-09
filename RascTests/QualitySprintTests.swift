import AppKit
import SwiftUI
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

@MainActor
@Suite
struct NaturalListEditingTests {
    @Test
    func createsContinuesAndEndsList() {
        let editor = ListTextView()
        editor.insertText("-", replacementRange: editor.selectedRange())
        editor.insertText(" ", replacementRange: editor.selectedRange())
        #expect(editor.string == "• ")
        editor.insertText("First", replacementRange: editor.selectedRange())
        editor.insertNewline(nil)
        #expect(editor.string == "• First\n• ")
        editor.insertNewline(nil)
        #expect(editor.string == "• First\n")
    }

    @Test
    func backspaceRemovesMarkerAndOrdinaryHyphensRemainText() {
        let editor = ListTextView()
        editor.insertText("• Item", replacementRange: editor.selectedRange())
        editor.setSelectedRange(NSRange(location: 2, length: 0))
        editor.deleteBackward(nil)
        #expect(editor.string == "Item")
        editor.string = "a-"
        editor.setSelectedRange(NSRange(location: 2, length: 0))
        editor.insertText(" ", replacementRange: editor.selectedRange())
        #expect(editor.string == "a- ")
    }

    @Test
    func typingAndMarkerConversionCanBeUndone() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
        let editor = ListTextView(frame: window.contentView!.bounds)
        editor.allowsUndo = true
        window.contentView = editor
        window.makeFirstResponder(editor)
        let undo = window.undoManager!
        undo.groupsByEvent = false
        undo.beginUndoGrouping()
        editor.insertText("-", replacementRange: editor.selectedRange())
        editor.insertText(" ", replacementRange: editor.selectedRange())
        undo.endUndoGrouping()
        undo.undo()
        #expect(editor.string != "• ")
        undo.redo()
        #expect(editor.string == "• ")
    }

    @Test
    func splittingAnItemPreservesBothSides() {
        let editor = ListTextView()
        editor.string = "• FirstSecond"
        editor.setSelectedRange(NSRange(location: 7, length: 0))
        editor.insertNewline(nil)
        #expect(editor.string == "• First\n• Second")
    }
}

@MainActor
@Suite
struct ImagePasteProtectionTests {
    @Test
    func readsFinderURLsAsURLObjects() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("RascClipboard-\(UUID().uuidString).png")
        let bytes = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==")!
        try bytes.write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let board = NSPasteboard(name: .init("RascTests.\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        board.clearContents()
        #expect(board.writeObjects([file as NSURL]))
        let url = try #require(ListTextView.fileURLs(in: board).first)
        let image = try await NoteImageImport.load(.file(url))
        #expect(image == .image(data: bytes, typeIdentifier: "public.png"))
    }

    @Test
    func detectsImageDataAndFinderImageURLsWithoutTreatingTextAsImage() {
        let pasteboard = NSPasteboard(name: .init("RascTests.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.setString("ordinary text", forType: .string)
        #expect(!ListTextView.containsImage(pasteboard))
        pasteboard.clearContents()
        pasteboard.setData(Data([0]), forType: .png)
        #expect(ListTextView.containsImage(pasteboard))
        pasteboard.clearContents()
        pasteboard.writeObjects([URL(fileURLWithPath: "/tmp/screenshot.HEIC") as NSURL])
        #expect(ListTextView.containsImage(pasteboard))
        pasteboard.clearContents()
        pasteboard.writeObjects([URL(fileURLWithPath: "/tmp/notes.txt") as NSURL])
        #expect(!ListTextView.containsImage(pasteboard))
    }

    @Test
    func pastePrefersBitmapBytesOverUnusableRTFD() {
        let image = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==")!
        let pasteboard = NSPasteboard(name: .init("RascTests.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        #expect(pasteboard.setData(image, forType: .png))
        #expect(pasteboard.setData(Data("not rtfd".utf8), forType: .rtfd))
        guard let source = ListTextView.preferredImportSources(from: pasteboard)?.first else {
            Issue.record("Expected bitmap source on pasteboard")
            return
        }
        guard case let .pasteboard(name, type, changeCount) = source else {
            Issue.record("Expected pasteboard bitmap source")
            return
        }
        #expect(type == NSPasteboard.PasteboardType.png.rawValue)
        #expect(changeCount == pasteboard.changeCount)
        let editor = ListTextView()
        var captured: [NoteImageImport.Source]?
        editor.imagePaste = { captured = $0 }
        editor.paste(nil)
        guard case let .pasteboard(capturedName, capturedType, capturedCount)? = captured?.first else {
            Issue.record("Expected paste to route bitmap bytes")
            return
        }
        #expect(capturedName == name)
        #expect(capturedType == type)
        #expect(capturedCount == changeCount)
    }
}

@MainActor
@Suite
struct ImageEditorTests {
    @Test
    func scratchpadPastesAndPersistsImageThroughHostedEditor() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("RascEditor-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let repository = try NoteRepository(databaseURL: url)
        let suite = "RascEditor.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let session = ScratchpadSession(repository: repository, userDefaults: defaults)
        session.text = "before after"
        let root = ScratchpadView(session: session, onEscape: {}, onPaletteCommand: { _ in }, onOpenHome: {}, onKeep: {}, onUnkeep: {})
        let host = NSHostingView(rootView: root)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        func findEditor(_ view: NSView) -> ListTextView? {
            if let editor = view as? ListTextView { return editor }
            return view.subviews.lazy.compactMap { findEditor($0) }.first
        }
        var found = findEditor(host)
        for _ in 0..<100 where found == nil {
            try await Task.sleep(for: .milliseconds(20))
            found = findEditor(host)
        }
        let editor = try #require(found)
        editor.setSelectedRange(NSRange(location: 6, length: 0))
        let sample = NSImage(size: NSSize(width: 480, height: 240))
        sample.lockFocus()
        NSColor.white.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 480, height: 240)).fill()
        ("Screenshot preview\nA thought captured in Rasc." as NSString).draw(at: NSPoint(x: 24, y: 160), withAttributes: [.font: NSFont.systemFont(ofSize: 22), .foregroundColor: NSColor.black])
        sample.unlockFocus()
        let tiff = try #require(sample.tiffRepresentation)
        let bitmap = try #require(NSBitmapImageRep(data: tiff))
        let image = try #require(bitmap.representation(using: .png, properties: [:]))
        editor.imagePaste?([.data(image)])
        for _ in 0..<100 where session.document?.hasImages != true {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(session.document?.hasImages == true)
        for _ in 0..<100 where !editor.currentDocument().hasImages {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(editor.currentDocument().hasImages)
        #expect(editor.string == "before\n\u{fffc}\n after")
        #expect(editor.selectedRange() == NSRange(location: 9, length: 0))
        let undo = try #require(window.undoManager)
        for _ in 0..<50 where !undo.canUndo { try await Task.sleep(for: .milliseconds(20)) }
        #expect(undo.canUndo)
        undo.undo()
        #expect(session.document?.hasImages == false)
        #expect(session.text == "before after")
        undo.redo()
        #expect(session.document?.hasImages == true)
        try await session.flush()
        let note = try #require(try await repository.fetchMostRecent())
        #expect(try await repository.fetchDocument(id: note.id)?.hasImages == true)
        try repository.closeForTesting()
    }

    @Test
    func editingAroundImagesKeepsThemOnTheirOwnLines() {
        let data = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==")!
        let document = NoteDocument(parts: [.text("before\n"), .image(data: data, typeIdentifier: "public.png"), .text("\nafter")])
        let editor = ListTextView()
        editor.isRichText = true
        editor.render(document)
        #expect(!editor.shouldChangeText(in: NSRange(location: 6, length: 1), replacementString: ""))
        editor.setSelectedRange(NSRange(location: 7, length: 0))
        editor.insertText("X", replacementRange: editor.selectedRange())
        #expect(editor.string == "before\nX\n\u{fffc}\nafter")
        editor.render(document)
        editor.setSelectedRange(NSRange(location: 9, length: 0))
        editor.deleteBackward(nil)
        #expect(editor.selectedRange() == NSRange(location: 7, length: 1))
        editor.deleteBackward(nil)
        #expect(!editor.currentDocument().hasImages)
    }

    @Test
    func unsupportedFormattingIsNotApplied() {
        let editor = ListTextView()
        editor.isRichText = true
        editor.string = "plain"
        editor.setSelectedRange(NSRange(location: 0, length: 5))
        editor.underline(nil)
        #expect(editor.textStorage?.attribute(.underlineStyle, at: 0, effectiveRange: nil) == nil)
        let item = NSMenuItem(title: "Underline", action: #selector(NSText.underline(_:)), keyEquivalent: "")
        #expect(!editor.validateUserInterfaceItem(item))
    }

    @Test
    func smallImageIsNotEnlarged() async throws {
        let data = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==")!
        let editor = ListTextView(frame: NSRect(x: 0, y: 0, width: 500, height: 300))
        editor.isRichText = true
        editor.render(NoteDocument(parts: [.image(data: data, typeIdentifier: "public.png")]))
        let attachment = try #require(editor.textStorage?.attribute(.attachment, at: 0, effectiveRange: nil) as? NSTextAttachment)
        for _ in 0..<100 where (attachment.attachmentCell?.cellSize().width ?? 0) <= 0 { try await Task.sleep(for: .milliseconds(20)) }
        let cell = try #require(attachment.attachmentCell)
        #expect(cell.cellSize().width > 0)
        #expect(cell.cellSize().width <= 1.5)
    }

    @Test
    func attachmentSurvivesEditingAndUndo() {
        let image = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==")!
        let document = NoteDocument(parts: [.text("before\n"), .image(data: image, typeIdentifier: "public.png"), .text("\nafter")])
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
        let editor = ListTextView(frame: window.contentView!.bounds)
        editor.isRichText = true
        editor.allowsUndo = true
        window.contentView = editor
        window.makeFirstResponder(editor)
        editor.render(document)
        #expect(editor.currentDocument() == document)
        editor.setSelectedRange(NSRange(location: 7, length: 1))
        #expect(editor.documentForSelection() == NoteDocument(parts: [.image(data: image, typeIdentifier: "public.png")]))
        let undo = window.undoManager!
        undo.groupsByEvent = false
        undo.beginUndoGrouping()
        editor.setSelectedRange(NSRange(location: 7, length: 1))
        editor.deleteBackward(nil)
        undo.endUndoGrouping()
        #expect(!editor.currentDocument().hasImages)
        undo.undo()
        #expect(editor.currentDocument() == document)
        undo.redo()
        #expect(!editor.currentDocument().hasImages)
    }
}

@MainActor
@Suite
struct ImageHandoffTests {
    @Test
    func mixedClipboardContainsTextAndImageWithoutPlainTextFallback() async throws {
        let image = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==")!
        let document = NoteDocument(parts: [.text("before\n"), .image(data: image, typeIdentifier: "public.png"), .text("\nafter")])
        let board = NSPasteboard(name: .init("RascTests.\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        try await NoteHandoff.copy(document, to: board)
        #expect(board.string(forType: .string) == nil)
        let data = try #require(board.data(forType: .rtfd))
        let decoded = try NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtfd], documentAttributes: nil)
        #expect(decoded.string == document.editorText)
        var copiedImage: Data?
        decoded.enumerateAttribute(.attachment, in: NSRange(location: 0, length: decoded.length)) { value, _, _ in
            if let attachment = value as? NSTextAttachment { copiedImage = attachment.fileWrapper?.regularFileContents }
        }
        #expect(copiedImage == image)
    }

    @Test
    func mixedClipboardPreservesMultipleDistinctImagesInOrder() async throws {
        let first = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==")!
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        for x in 0..<2 { for y in 0..<2 { bitmap.setColor(.blue, atX: x, y: y) } }
        let second = try #require(bitmap.representation(using: .png, properties: [:]))
        let document = NoteDocument(parts: [.text("a\n"), .image(data: first, typeIdentifier: "public.png"), .text("\nb\n"), .image(data: second, typeIdentifier: "public.png")])
        let board = NSPasteboard(name: .init("RascTests.\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        try await NoteHandoff.copy(document, to: board)
        let data = try #require(board.data(forType: .rtfd))
        let decoded = try NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtfd], documentAttributes: nil)
        #expect(decoded.string == document.editorText)
        var images: [Data] = []
        decoded.enumerateAttribute(.attachment, in: NSRange(location: 0, length: decoded.length)) { value, _, _ in
            if let attachment = value as? NSTextAttachment, let bytes = attachment.fileWrapper?.regularFileContents { images.append(bytes) }
        }
        #expect(images == [first, second])
    }

    @Test
    func mixedContentCanBePastedBackIntoRasc() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("RascPaste-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let repository = try NoteRepository(databaseURL: url)
        let suite = "RascPaste.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let image = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==")!
        let fragment = NoteDocument(parts: [.text("one\n"), .image(data: image, typeIdentifier: "public.png"), .text("\ntwo")])
        let board = NSPasteboard(name: .init("RascTests.\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        try await NoteHandoff.copy(fragment, to: board)
        let session = ScratchpadSession(repository: repository, userDefaults: defaults)
        session.text = "XY"
        let source = NoteImageImport.Source.documentPasteboard(name: board.name.rawValue, type: NoteHandoff.documentPasteboardType.rawValue, changeCount: board.changeCount)
        let task = try #require(session.beginImageImport(source, selection: NSRange(location: 1, length: 0)))
        #expect(try await task.value != nil)
        #expect(session.text == "Xone\n\u{fffc}\ntwoY")
        try await session.flush()
        let note = try #require(try await repository.fetchMostRecent())
        #expect(try await repository.fetchDocument(id: note.id) == session.document)
        try repository.closeForTesting()
    }

    @Test
    func importsMixedRTFDFromAnotherApp() async throws {
        let image = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==")!
        let fragment = NoteDocument(parts: [.text("before\n"), .image(data: image, typeIdentifier: "public.png"), .text("\nafter")])
        let board = NSPasteboard(name: .init("RascTests.\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        try await NoteHandoff.copy(fragment, to: board)
        let rtfd = try #require(board.data(forType: .rtfd))
        board.clearContents()
        #expect(board.setData(rtfd, forType: .rtfd))
        let imported = try await NoteImageImport.loadDocument(name: board.name.rawValue, type: NSPasteboard.PasteboardType.rtfd.rawValue, changeCount: board.changeCount)
        #expect(imported == fragment)
    }

    @Test
    func rejectsNonImageRTFDAttachments() async throws {
        let wrapper = FileWrapper(regularFileWithContents: Data("not an image".utf8))
        wrapper.preferredFilename = "document.txt"
        let content = NSMutableAttributedString(string: "before")
        content.append(NSAttributedString(attachment: NSTextAttachment(fileWrapper: wrapper)))
        let rtfd = try content.data(from: NSRange(location: 0, length: content.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd])
        let board = NSPasteboard(name: .init("RascTests.\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        board.clearContents()
        #expect(board.setData(rtfd, forType: .rtfd))
        await #expect(throws: NoteImageImport.ImportError.invalidImage) {
            try await NoteImageImport.loadDocument(name: board.name.rawValue, type: NSPasteboard.PasteboardType.rtfd.rawValue, changeCount: board.changeCount)
        }
    }

    @Test
    func imageOnlyClipboardProvidesOriginalImage() async throws {
        let image = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==")!
        let board = NSPasteboard(name: .init("RascTests.\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        try await NoteHandoff.copy(NoteDocument(parts: [.image(data: image, typeIdentifier: "public.png"), .text("\n")]), to: board)
        #expect(board.data(forType: .png) == image)
        let payload = try await NoteHandoff.sharePayload(NoteDocument(parts: [.image(data: image, typeIdentifier: "public.png")]))
        #expect(payload.typeIdentifier == "public.png")
        #expect(payload.data == image)
    }
}

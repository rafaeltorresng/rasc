import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

struct ScratchpadView: View {
    @Bindable var session: ScratchpadSession
    @State private var showsOriginal = false
    @Environment(\.undoManager) private var undoManager
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var globalShortcutRevision = 0

    let onEscape: () -> Void
    let onPaletteCommand: (PaletteCommand) -> Void
    let onOpenHome: () -> Void
    let onKeep: () -> Void
    let onUnkeep: () -> Void

    var body: some View {
        let _ = globalShortcutRevision
        VStack(spacing: 0) {
            if showsScratchpadChrome {
                scratchpadChrome
            }

            surfaceBodyContent
                .padding(.top, showsScratchpadChrome ? RascSurfaceLayout.scratchpadChromeToBodyGap : 0)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .id(session.surface)
                .transition(RascMotion.bodyContentTransition(reduceMotion: reduceMotion))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(RascMotion.bodyContentAnimation(reduceMotion: reduceMotion), value: session.surface)
        .scratchpadCanvas()
        .registersSettingsOpenAction()
        .presentsSettings(on: session.settingsPresentationRequest)
        .onGlobalShortcutChange { globalShortcutRevision += 1 }
        .animation(RascMotion.micro(reduceMotion: reduceMotion), value: session.message)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let saveErrorMessage = session.saveErrorMessage {
                feedbackRow(saveErrorMessage) {
                    Button("Retry") { Task { await session.retrySave() } }
                }
            } else if let failure = session.completionFailure {
                feedbackRow(failure.text) {
                    Button("Retry") { onPaletteCommand(failure.command) }
                    Button("Dismiss") { session.dismissCompletionFailure() }
                }
            } else if session.scratchpadGuidance.unavailablePresentation != nil {
                OnboardingScratchpadOverlay(guidance: session.scratchpadGuidance, editorText: session.text)
            } else if let message = session.message, !message.isTransient {
                feedbackRow(message.text) {
                    if message == .unavailable(.appleIntelligenceNotEnabled) {
                        Button("System Settings") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.Siri") { NSWorkspace.shared.open(url) }
                        }
                    }
                    if message == .couldNotRefine || message == .couldNotSafelyRefineSelection {
                        Button("Retry") { session.dismissRefinementMessage(); session.startRefinement() }
                    }
                    Button("Dismiss") { session.dismissRefinementMessage() }
                }
            } else if session.lastDiscard != nil {
                feedbackRow("Thought discarded.") {
                    Button("Undo") { Task { await session.undoDiscard() } }
                }
            } else if session.scratchpadGuidance.isActive {
                OnboardingScratchpadOverlay(guidance: session.scratchpadGuidance, editorText: session.text)
            } else if let transientFeedback = session.transientFeedback {
                feedbackRow(transientFeedback) { EmptyView() }
            }
        }
        .onChange(of: session.surface) { _, surface in
            if surface == .refinementPreview { RascAccessibility.announce("Refinement preview. Compare the suggestion with your original before accepting.") }
        }
        .onChange(of: session.message) { _, message in
            if let message { RascAccessibility.announce(message.text) }
        }
        .onChange(of: session.completionFailure) { _, failure in
            if let failure { RascAccessibility.announce(failure.text) }
        }
        .onChange(of: session.saveErrorMessage) { _, error in
            if let error { RascAccessibility.announce(error) }
        }
        .onChange(of: session.transientFeedback) { _, feedback in
            if let feedback { RascAccessibility.announce(feedback) }
        }
    }

    private func feedbackRow<Actions: View>(_ text: String, @ViewBuilder actions: () -> Actions) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(text).font(.callout).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            actions().controlSize(.small)
        }
        .padding(.horizontal, RascSurfaceLayout.horizontalInset)
        .padding(.vertical, 10)
        .background(RascSurfacePalette.raisedFill(for: colorScheme))
        .accessibilityElement(children: .contain)
    }

    private var showsScratchpadChrome: Bool {
        switch session.surface {
        case .editor, .refining, .refinementPreview, .message:
            true
        case .search, .commandPalette:
            false
        }
    }

    private var showsHomeAffordance: Bool {
        switch session.surface {
        case .editor, .message:
            true
        case .search, .commandPalette, .refining, .refinementPreview:
            false
        }
    }

    private var showsRefineAction: Bool {
        session.surface == .editor
            && session.hasPersistableContent
            && session.canPerformThoughtCompletion
    }

    private var scratchpadChrome: some View {
        HStack(alignment: .center, spacing: RascSurfaceLayout.orbToAccessoryGap) {
            RascOrb(state: resolvedOrbState, size: .inline, decorative: true)
                .frame(width: RascSurfaceLayout.orbSize, height: RascSurfaceLayout.orbSize)

            if let statusText {
                Text(statusText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(RascSurfacePalette.homeSupportingText(for: colorScheme))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            scratchpadTrailingActions
                .layoutPriority(1)
        }
        .padding(.horizontal, RascSurfaceLayout.horizontalInset)
        .padding(.top, RascSurfaceLayout.topInset)
        .padding(.bottom, RascSurfaceLayout.scratchpadChromeBottomPadding)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var scratchpadTrailingActions: some View {
        HStack(spacing: 2) {
            reservedChromeButton(
                title: "New",
                shortcut: InternalShortcutStore.shared.displayString(for: .newScratch),
                isVisible: showsRefineAction,
                action: { onPaletteCommand(.newScratch) }
            )
            .accessibilityLabel("New Scratch")
            .accessibilityHint(PaletteCommand.newScratch.accessibilityHint)
            .help("New Scratch (\(InternalShortcutStore.shared.displayString(for: .newScratch)))")

            reservedChromeButton(
                title: "Refine",
                shortcut: InternalShortcutStore.shared.displayString(for: .refine),
                isVisible: showsRefineAction,
                action: { session.startRefinement() }
            )
            .accessibilityLabel("Refine")
            .help("Refine note")

            reservedChromeButton(
                title: session.isActiveNoteKept ? "Unkeep" : "Keep",
                shortcut: session.isActiveNoteKept ? nil : InternalShortcutStore.shared.displayString(for: .keep),
                isPrimary: !session.isActiveNoteKept,
                isVisible: showsThoughtCompletionAction,
                action: session.isActiveNoteKept ? onUnkeep : onKeep
            )
            .accessibilityLabel(session.isActiveNoteKept ? "Unkeep" : "Keep")

            scratchpadHomeButton
                .opacity(showsHomeAffordance ? 1 : 0)
                .allowsHitTesting(showsHomeAffordance)
                .accessibilityHidden(!showsHomeAffordance)
        }
        .animation(RascMotion.micro(reduceMotion: reduceMotion), value: showsRefineAction)
        .animation(RascMotion.micro(reduceMotion: reduceMotion), value: showsThoughtCompletionAction)
    }

    private var showsThoughtCompletionAction: Bool {
        session.surface == .editor
            && session.canPerformThoughtCompletion
            && (session.isActiveNoteKept || session.hasPersistableContent)
    }

    private func reservedChromeButton(
        title: String,
        shortcut: String?,
        isPrimary: Bool = false,
        isVisible: Bool,
        action: @escaping () -> Void
    ) -> some View {
        ScratchpadChromeButton(
            title: title,
            shortcut: shortcut,
            isPrimary: isPrimary,
            action: action
        )
        .opacity(isVisible ? 1 : 0)
        .allowsHitTesting(isVisible)
        .accessibilityHidden(!isVisible)
    }

    private var scratchpadHomeButton: some View {
        ScratchpadChromeIconButton(
            systemName: "house",
            action: onOpenHome
        )
        .help("Open Home (\(GlobalShortcutFormatting.currentHomeShortcutDisplay()))")
        .accessibilityLabel("Open Rasc Home")
    }

    @ViewBuilder
    private var surfaceBodyContent: some View {
        switch session.surface {
        case .editor, .message:
            editorSurface
        case .search:
            HistorySearchView(session: session)
        case .commandPalette:
            CommandPaletteView(session: session, onExecute: onPaletteCommand)
        case .refining:
            refiningSurface
        case .refinementPreview:
            refinementPreviewSurface
        }
    }

    private var resolvedOrbState: RascOrbState {
        session.surface == .refining ? .refining : .composing
    }

    @ViewBuilder
    private var editorSurface: some View {
        ZStack(alignment: .topLeading) {
            ScratchEditor(session: session, onEscape: handleEscape)
                .id(session.editorIdentity)
                .padding(.horizontal, RascSurfaceMetrics.editorHorizontalPadding)
                .padding(.top, RascSurfaceMetrics.editorTopPadding)

            if session.surface == .editor, !session.hasPersistableContent {
                ScratchpadEmptyState()
                    .padding(.leading, RascSurfaceMetrics.editorHorizontalPadding)
                    .padding(.top, RascSurfaceMetrics.editorTopPadding)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
    }

    private var refiningSurface: some View {
        TextEditor(text: .constant(session.text))
            .scrollContentBackground(.hidden)
            .background(.clear)
            .font(.system(
                size: RascSurfaceMetrics.noteFontSize,
                weight: .regular
            ))
            .lineSpacing(RascSurfaceMetrics.noteLineSpacing)
            .foregroundStyle(.primary.opacity(0.78))
            .padding(.horizontal, RascSurfaceMetrics.editorHorizontalPadding)
            .padding(.top, RascSurfaceMetrics.editorTopPadding)
            .disabled(true)
            .accessibilityLabel("Scratch editor")
            .accessibilityValue("Refining note")
            .onExitCommand(perform: handleEscape)
    }

    private var refinementPreviewSurface: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Text(session.refinementPreview?.request.scope == .selection ? "Selection preview" : "Preview")
                    .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                Spacer()
                Picker("Compare refinement", selection: $showsOriginal) {
                    Text("Suggested").tag(false)
                    Text("Original").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 190)
                .controlSize(.small)
            }
            .padding(.horizontal, RascSurfaceLayout.horizontalInset)
            .padding(.vertical, 8)
            ScrollView {
                Text(showsOriginal ? (session.refinementPreview?.request.snapshot.text ?? "") : (session.refinementPreview?.proposedNoteText ?? ""))
                    .font(.system(
                        size: RascSurfaceMetrics.noteFontSize,
                        weight: .regular
                    ))
                    .lineSpacing(RascSurfaceMetrics.noteLineSpacing)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(.horizontal, RascSurfaceLayout.noteTextLeadingInset)
                    .padding(.top, RascSurfaceMetrics.editorTopPadding)
                    .padding(.bottom, 20)
            }
            .accessibilityLabel("Refined preview")

            Rectangle()
                .fill(.primary.opacity(0.07))
                .frame(height: 1)

            HStack(spacing: 12) {
                Button {
                    _ = session.handleEscape()
                } label: {
                    RefinementActionLabel(title: "Keep original", shortcut: RascShortcutCatalog.keepOriginal.shortcut)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel("Cancel refinement")

                Spacer()

                Button {
                    Task {
                        try? await session.acceptRefinement(undoManager: undoManager)
                    }
                } label: {
                    RefinementActionLabel(title: "Accept suggestion", shortcut: RascShortcutCatalog.acceptSuggestion.shortcut, isPrimary: true)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
                .accessibilityLabel("Accept refinement")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Refinement preview")
        .onChange(of: session.refinementPreview?.request.requestID, initial: true) { showsOriginal = false }
        .onExitCommand(perform: handleEscape)
    }

    private var statusText: String? {
        switch session.surface {
        case .refining:
            "Refining…"
        case .refinementPreview:
            "Preview"
        case .message:
            session.message == .alreadyUseful ? "Already useful" : (session.message?.isTransient == true ? session.message?.text : nil)
        case .editor, .search, .commandPalette:
            if let transientFeedback = session.transientFeedback {
                transientFeedback
            } else if session.isActiveNoteKept {
                "Kept"
            } else {
                nil
            }
        }
    }

    private func handleEscape() {
        if !session.handleEscape() {
            onEscape()
        }
    }
}

/// A plain-text editor: list markers remain part of the note for search and handoff.
private struct ScratchEditor: NSViewRepresentable {
    @Bindable var session: ScratchpadSession
    let onEscape: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(session: session) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        let editor = ListTextView()
        editor.delegate = context.coordinator
        editor.escapeAction = onEscape
        editor.imagePaste = { [weak coordinator = context.coordinator] source in coordinator?.pasteImage(source) }
        editor.imagePasteFailure = { session.reportImageImportFailure("Couldn't paste this mixed content. Try copying the image separately.") }
        editor.imageBoundaryFailure = { session.reportImageImportFailure("Images stay on separate lines. Select an image to remove it.") }
        editor.imageCopyFailure = { session.reportImageImportFailure("Couldn't copy images. Select one range and try again.") }
        editor.imageCopySuccess = { session.reportImageCopy($0) }
        editor.isRichText = true
        editor.allowsUndo = true
        editor.drawsBackground = false
        editor.syncLayoutMetrics()
        editor.applyBodyAttributes()
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = true
        editor.textContainer?.containerSize = NSSize(width: scroll.contentSize.width, height: .greatestFiniteMagnitude)
        editor.setAccessibilityLabel("Scratchpad")
        editor.setAccessibilityHelp("Write an unfinished thought. Select an image and press Space to open a larger preview. Refine is optional; Keep finishes it.")
        scroll.documentView = editor
        context.coordinator.editor = editor
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let editor = scroll.documentView as? ListTextView else { return }
        context.coordinator.session = session
        editor.escapeAction = onEscape
        editor.imagePaste = { [weak coordinator = context.coordinator] source in coordinator?.pasteImage(source) }
        editor.imagePasteFailure = { session.reportImageImportFailure("Couldn't paste this mixed content. Try copying the image separately.") }
        editor.imageBoundaryFailure = { session.reportImageImportFailure("Images stay on separate lines. Select an image to remove it.") }
        editor.imageCopyFailure = { session.reportImageImportFailure("Couldn't copy images. Select one range and try again.") }
        editor.imageCopySuccess = { session.reportImageCopy($0) }
        if editor.string != session.text || context.coordinator.renderedDocument != session.document {
            let selection = session.editorSelection
            let previousSelection = editor.selectedRange()
            context.coordinator.renderedDocument = session.document
            if let document = session.document {
                editor.render(document)
            } else {
                editor.setPlainNoteText(session.text)
            }
            if let caret = context.coordinator.pendingCaret {
                editor.setSelectedRange(NSRange(location: min(caret, (editor.string as NSString).length), length: 0))
                context.coordinator.pendingCaret = nil
            } else if let selection {
                editor.setSelectedRange(NSRange(selection, in: session.text))
            } else {
                let length = (editor.string as NSString).length
                let location = min(previousSelection.location, length)
                editor.setSelectedRange(NSRange(location: location, length: min(previousSelection.length, length - location)))
            }
            editor.syncLayoutMetrics()
            editor.applyParagraphStyles()
        } else {
            editor.syncLayoutMetrics()
            editor.applyBodyAttributes()
        }
        if context.coordinator.focusRequest != session.focusRequest {
            context.coordinator.focusRequest = session.focusRequest
            DispatchQueue.main.async { [weak editor] in
                guard let editor, let window = editor.window else { return }
                window.makeFirstResponder(editor)
            }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var session: ScratchpadSession
        weak var editor: ListTextView?
        var focusRequest = -1
        var renderedDocument: NoteDocument?
        var pendingCaret: Int?

        init(session: ScratchpadSession) { self.session = session }

        func textDidChange(_ notification: Notification) {
            guard let editor else { return }
            if session.document != nil {
                let document = editor.currentDocument()
                renderedDocument = document
                session.replaceDocumentFromEditor(document)
            } else {
                session.text = editor.string
                session.scheduleAutosave()
            }
            editor.applyParagraphStyles()
            updateSelection(editor)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let editor else { return }
            updateSelection(editor)
        }

        @MainActor func pasteImage(_ sources: [NoteImageImport.Source]) {
            guard let editor else { return }
            guard editor.selectedRanges.count == 1 else {
                session.reportImageImportFailure("Select one insertion point for images.")
                return
            }
            let selection = editor.selectedRange()
            let epoch = session.editorEpoch
            let old = session.document ?? NoteDocument(parts: [.text(session.text)])
            guard let importTask = session.beginImageImports(sources, selection: selection) else {
                session.reportImageImportFailure("Wait for the current image to finish importing.")
                return
            }
            Task { @MainActor in
                do {
                    guard let caret = try await importTask.value else {
                        session.reportImageImportFailure("The thought changed. Paste the image again.")
                        return
                    }
                    guard session.editorEpoch == epoch else {
                        session.reportImageImportFailure("The thought changed. Paste the image again.")
                        return
                    }
                    pendingCaret = caret
                    if editor.string == session.text {
                        editor.setSelectedRange(NSRange(location: min(caret, (editor.string as NSString).length), length: 0))
                        pendingCaret = nil
                    }
                    if let undo = editor.undoManager, let current = session.document {
                        registerImageUndo(undo, restoring: old, inverse: current)
                    }
                } catch NoteImageImport.ImportError.tooLarge {
                    session.reportImageImportFailure("Images larger than 128 MB can't be pasted.")
                } catch NoteImageImport.ImportError.tooMuchContent {
                    session.reportImageImportFailure("This thought can't contain more than 256 MB of images.")
                } catch {
                    session.reportImageImportFailure("Couldn't import this image. Try another image.")
                }
            }
        }

        @MainActor private func registerImageUndo(_ undo: UndoManager, restoring: NoteDocument, inverse: NoteDocument) {
            let identity = session.editorIdentity
            undo.registerUndo(withTarget: session) { target in
                guard target.editorIdentity == identity else { return }
                self.registerImageUndo(undo, restoring: inverse, inverse: restoring)
                target.replaceDocumentFromEditor(restoring)
            }
            undo.setActionName("Paste Image")
        }

        @MainActor private func updateSelection(_ editor: NSTextView) {
            let ranges = editor.selectedRanges
            let range = editor.selectedRange()
            let selection = range.length > 0 ? Range(range, in: session.text) : nil
            session.updateEditorSelection(selection, hasMultipleSelections: ranges.count > 1)
        }
    }
}

/// List syntax is deliberately plain text, so no separate formatting state can diverge.
final class ListTextView: NSTextView {
    var escapeAction: (() -> Void)?
    var imagePaste: (([NoteImageImport.Source]) -> Void)?
    var imagePasteFailure: (() -> Void)?
    var imageBoundaryFailure: (() -> Void)?
    var imageCopyFailure: (() -> Void)?
    var imageCopySuccess: ((NoteDocument) -> Void)?
    private var previewWindow: NSWindow?
    private let marker = "• "

    override func cancelOperation(_ sender: Any?) { escapeAction?() }

    // Formatting other than lists is not part of the note model.
    override func changeFont(_ sender: Any?) { }
    override func changeAttributes(_ sender: Any?) { }
    override func underline(_ sender: Any?) { }
    override func `subscript`(_ sender: Any?) { }
    override func superscript(_ sender: Any?) { }
    override func unscript(_ sender: Any?) { }
    override func pasteFont(_ sender: Any?) { }
    override func pasteRuler(_ sender: Any?) { }
    override func alignLeft(_ sender: Any?) { }
    override func alignRight(_ sender: Any?) { }
    override func alignCenter(_ sender: Any?) { }

    override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        if let action = item.action, ["changeFont:", "changeAttributes:", "underline:", "subscript:", "superscript:", "unscript:", "pasteFont:", "pasteRuler:", "alignLeft:", "alignRight:", "alignCenter:"].contains(NSStringFromSelector(action)) {
            return false
        }
        return super.validateUserInterfaceItem(item)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == .command, event.charactersIgnoringModifiers?.lowercased() == "v" {
            paste(self)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func pasteAsPlainText(_ sender: Any?) {
        if Self.canImportImage(from: .general) {
            paste(sender)
        } else {
            super.pasteAsPlainText(sender)
        }
    }

    override func paste(_ sender: Any?) {
        let board = NSPasteboard.general
        if (board.types ?? []).contains(NoteHandoff.documentPasteboardType) {
            imagePaste?([.documentPasteboard(name: board.name.rawValue, type: NoteHandoff.documentPasteboardType.rawValue, changeCount: board.changeCount)])
            return
        }
        if let sources = Self.preferredImportSources(from: board) {
            imagePaste?(sources)
            return
        }
        if Self.containsImage(board) {
            let fileItemCount = (board.pasteboardItems ?? []).filter { $0.types.contains(.fileURL) }.count
            let urls = Self.fileURLs(in: board)
            let images = urls.filter { UTType(filenameExtension: $0.pathExtension)?.conforms(to: .image) == true }
            if fileItemCount > 0, urls.count != fileItemCount || images.count != urls.count {
                imagePasteFailure?()
            } else if !images.isEmpty {
                imagePaste?(images.map { .file($0) })
            } else {
                imagePasteFailure?()
            }
            return
        }
        if (board.types ?? []).contains(.rtfd) {
            imagePaste?([.documentPasteboard(name: board.name.rawValue, type: NSPasteboard.PasteboardType.rtfd.rawValue, changeCount: board.changeCount)])
            return
        }
        super.pasteAsPlainText(sender)
    }

    func documentForSelection() -> NoteDocument? {
        let selection = selectedRange()
        guard selection.length > 0 else { return nil }
        return try? currentDocument().selecting(selection)
    }

    override func copy(_ sender: Any?) {
        if selectedRanges.count > 1 {
            let document = currentDocument()
            if selectedRanges.contains(where: { (try? document.selecting($0.rangeValue).hasImages) == true }) {
                imageCopyFailure?()
                return
            }
        }
        guard let selection = documentForSelection(), selection.hasImages else {
            super.copy(sender)
            return
        }
        Task { @MainActor in
            do {
                try await NoteHandoff.copy(selection)
                imageCopySuccess?(selection)
            } catch { imageCopyFailure?() }
        }
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        if Self.containsImage(sender.draggingPasteboard) {
            imagePasteFailure?()
            return false
        }
        return super.performDragOperation(sender)
    }

    static func fileURLs(in pasteboard: NSPasteboard) -> [URL] {
        (pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) ?? [])
            .compactMap { $0 as? URL }
    }

    static func containsImage(_ pasteboard: NSPasteboard) -> Bool {
        if preferredImportSources(from: pasteboard) != nil { return true }
        if (pasteboard.types ?? []).contains(.rtfd) { return true }
        for item in pasteboard.pasteboardItems ?? [] {
            guard let value = item.string(forType: .fileURL),
                  let url = URL(string: value), url.isFileURL,
                  let type = UTType(filenameExtension: url.pathExtension),
                  type.conforms(to: .image) else { continue }
            return true
        }
        return false
    }

    static func canImportImage(from pasteboard: NSPasteboard) -> Bool {
        if (pasteboard.types ?? []).contains(NoteHandoff.documentPasteboardType) { return true }
        if preferredImportSources(from: pasteboard) != nil { return true }
        return containsImage(pasteboard)
    }

    /// Clipboard screenshots and copy-image usually include bitmap bytes; RTFD can fail in sandboxed apps.
    static func preferredImportSources(from pasteboard: NSPasteboard) -> [NoteImageImport.Source]? {
        let changeCount = pasteboard.changeCount
        let name = pasteboard.name.rawValue
        if let sources = preferredImportSources(in: pasteboard.pasteboardItems, name: name, changeCount: changeCount) {
            return sources
        }
        for raw in Self.preferredPasteboardTypeOrder {
            let type = NSPasteboard.PasteboardType(raw)
            guard pasteboard.data(forType: type) != nil else { continue }
            return [.pasteboard(name: name, type: raw, changeCount: changeCount)]
        }
        if let type = pasteboard.types?.first(where: { UTType($0.rawValue)?.conforms(to: .image) == true }),
           pasteboard.data(forType: type) != nil {
            return [.pasteboard(name: name, type: type.rawValue, changeCount: changeCount)]
        }
        if let image = NSImage(pasteboard: pasteboard),
           let data = Self.pngData(from: image) {
            return [.data(data)]
        }
        return nil
    }

    private static func preferredImportSources(in items: [NSPasteboardItem]?, name: String, changeCount: Int) -> [NoteImageImport.Source]? {
        guard let items else { return nil }
        for item in items {
            for raw in preferredPasteboardTypeOrder {
                let type = NSPasteboard.PasteboardType(raw)
                guard item.data(forType: type) != nil else { continue }
                return [.pasteboard(name: name, type: raw, changeCount: changeCount)]
            }
            for type in item.types where UTType(type.rawValue)?.conforms(to: .image) == true {
                guard item.data(forType: type) != nil else { continue }
                return [.pasteboard(name: name, type: type.rawValue, changeCount: changeCount)]
            }
        }
        return nil
    }

    private static let preferredPasteboardTypeOrder = [
        NSPasteboard.PasteboardType.png.rawValue,
        NSPasteboard.PasteboardType.tiff.rawValue,
        "public.png",
        "public.tiff",
        "public.jpeg",
        "public.heic",
        "public.heif",
        "com.compuserve.gif",
        "org.webmproject.webp",
    ]

    private static func pngData(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2, let container = textContainer, let layout = layoutManager {
            var point = convert(event.locationInWindow, from: nil)
            point.x -= textContainerOrigin.x
            point.y -= textContainerOrigin.y
            let index = layout.characterIndex(for: point, in: container, fractionOfDistanceBetweenInsertionPoints: nil)
            if let attachment = imageAttachment(at: index) {
                openPreview(attachment)
                return
            }
        }
        super.mouseDown(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let base = super.menu(for: event)
        guard let container = textContainer, let layout = layoutManager else { return base }
        var point = convert(event.locationInWindow, from: nil)
        point.x -= textContainerOrigin.x
        point.y -= textContainerOrigin.y
        let index = layout.characterIndex(for: point, in: container, fractionOfDistanceBetweenInsertionPoints: nil)
        guard let attachment = imageAttachment(at: index) else { return base }
        let menu = (base?.copy() as? NSMenu) ?? NSMenu()
        let item = NSMenuItem(title: "Open Image", action: #selector(openImageFromMenu(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = attachment
        menu.insertItem(.separator(), at: 0)
        menu.insertItem(item, at: 0)
        return menu
    }

    @objc private func openImageFromMenu(_ item: NSMenuItem) {
        if let attachment = item.representedObject as? RascImageAttachment { openPreview(attachment) }
    }

    override func keyDown(with event: NSEvent) {
        let selected = selectedRange()
        if event.charactersIgnoringModifiers == " ", selected.length == 1,
           event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty,
           let attachment = imageAttachment(at: selected.location) {
            openPreview(attachment)
            return
        }
        super.keyDown(with: event)
    }

    private func imageAttachment(at index: Int) -> RascImageAttachment? {
        guard let storage = textStorage, index >= 0, index < storage.length else { return nil }
        return storage.attribute(.attachment, at: index, effectiveRange: nil) as? RascImageAttachment
    }

    private func openPreview(_ attachment: RascImageAttachment) {
        let data = attachment.imageData
        Task { [weak self] in
            let image = await Task.detached(priority: .userInitiated) { () -> CGImage? in
                guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
                return CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 4096, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary)
            }.value
            guard let self, let image else { return }
            let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1000, height: 700)
            let size = NSSize(width: min(1000, visible.width * 0.85), height: min(700, visible.height * 0.85))
            let window = RascImagePreviewWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            window.title = "Image"
            window.level = self.window?.level ?? .normal
            window.isReleasedWhenClosed = false
            let scroll = NSScrollView(frame: NSRect(origin: .zero, size: size))
            scroll.hasVerticalScroller = true
            scroll.hasHorizontalScroller = true
            scroll.autoresizingMask = [.width, .height]
            let imageSize = NSSize(width: image.width, height: image.height)
            let view = NSImageView(frame: NSRect(origin: .zero, size: imageSize))
            view.image = NSImage(cgImage: image, size: imageSize)
            view.imageScaling = .scaleNone
            view.setAccessibilityLabel("Image preview")
            scroll.documentView = view
            window.contentView = scroll
            window.center()
            self.previewWindow?.close()
            self.previewWindow = window
            window.makeKeyAndOrderFront(nil)
        }
    }

    func setPlainNoteText(_ text: String) {
        textStorage?.setAttributedString(NSAttributedString(string: text, attributes: bodyAttributes))
        applyBodyAttributes()
    }

    func applyBodyAttributes() {
        typingAttributes = bodyAttributes
        insertionPointColor = RascSurfacePalette.scratchpadInsertionPoint
        guard let storage = textStorage else { return }
        let text = storage.string as NSString
        var location = 0
        while location < text.length {
            if imageAttachment(at: location) != nil {
                location += 1
                continue
            }
            var range = NSRange(location: location, length: 0)
            while range.location + range.length < text.length, imageAttachment(at: range.location + range.length) == nil {
                range.length += 1
            }
            guard range.length > 0 else { break }
            storage.addAttributes(bodyAttributes, range: range)
            location = NSMaxRange(range)
        }
    }

    func syncLayoutMetrics() {
        font = RascSurfaceMetrics.noteFont
        textColor = .labelColor
        insertionPointColor = RascSurfacePalette.scratchpadInsertionPoint
        textContainer?.lineFragmentPadding = 0
        textContainer?.widthTracksTextView = true
        textContainerInset = NSSize(
            width: RascSurfaceLayout.textContainerHorizontalInset,
            height: RascSurfaceLayout.scratchpadEditorCaretTopInset
        )
        applyBodyAttributes()
    }

    private var bodyAttributes: [NSAttributedString.Key: Any] {
        [
            .font: font ?? RascSurfaceMetrics.noteFont,
            .foregroundColor: NSColor.labelColor,
        ]
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyBodyAttributes()
        applyParagraphStyles()
    }

    func render(_ document: NoteDocument) {
        let output = NSMutableAttributedString()
        for part in document.parts {
            switch part {
            case .text(let text):
                output.append(NSAttributedString(string: text, attributes: bodyAttributes))
            case let .image(data, type):
                let attachment = RascImageAttachment(data: data, type: type)
                configureImageAttachmentCell(attachment, data: data)
                output.append(NSAttributedString(attachment: attachment))
                Task { [weak self, weak attachment] in
                    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return }
                    let cgImage = await Task.detached(priority: .userInitiated) {
                        CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 1600, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary)
                    }.value
                    guard let self, let attachment, let cgImage, attachment.preview == nil || attachment.preview!.width < cgImage.width else { return }
                    attachment.preview = cgImage
                    self.configureImageAttachmentCell(attachment, data: data)
                    self.resizeImageAttachments()
                }
            }
        }
        textStorage?.setAttributedString(output)
        applyBodyAttributes()
    }

    override func setFrameSize(_ newSize: NSSize) {
        let oldWidth = frame.width
        super.setFrameSize(newSize)
        if abs(oldWidth - newSize.width) > 1 { resizeImageAttachments() }
    }

    private func configureImageAttachmentCell(_ attachment: RascImageAttachment, data: Data) {
        if attachment.preview == nil {
            attachment.preview = Self.thumbnail(for: data, maxPixelSize: 1600)
        }
        let width = max(1, bounds.width - 12)
        if let preview = attachment.preview {
            let imageWidth = min(CGFloat(preview.width), width)
            let size = NSSize(width: imageWidth, height: imageWidth * CGFloat(preview.height) / CGFloat(preview.width))
            let image = NSImage(cgImage: preview, size: size)
            image.accessibilityDescription = "Image. Select it and press Space to open a larger preview."
            attachment.attachmentCell = NSTextAttachmentCell(imageCell: image)
            return
        }
        let placeholderSize = NSSize(width: min(200, width), height: 120)
        let placeholder = NSImage(size: placeholderSize)
        placeholder.lockFocus()
        NSColor.quaternaryLabelColor.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: placeholderSize)).fill()
        placeholder.unlockFocus()
        attachment.attachmentCell = NSTextAttachmentCell(imageCell: placeholder)
    }

    private static func thumbnail(for data: Data, maxPixelSize: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ] as CFDictionary)
    }

    private func resizeImageAttachments() {
        guard let storage = textStorage else { return }
        storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { value, _, _ in
            guard let attachment = value as? RascImageAttachment, let preview = attachment.preview else { return }
            let width = min(CGFloat(preview.width), max(1, bounds.width - 12))
            let size = NSSize(width: width, height: width * CGFloat(preview.height) / CGFloat(preview.width))
            let image = NSImage(cgImage: preview, size: size)
            image.accessibilityDescription = "Image. Select it and press Space to open a larger preview."
            attachment.attachmentCell = NSTextAttachmentCell(imageCell: image)
        }
        layoutManager?.invalidateLayout(forCharacterRange: NSRange(location: 0, length: storage.length), actualCharacterRange: nil)
        needsDisplay = true
    }

    func currentDocument() -> NoteDocument {
        guard let storage = textStorage else { return NoteDocument(parts: [.text(string)]) }
        var parts: [NoteDocument.Part] = []
        storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            if let image = value as? RascImageAttachment {
                parts.append(.image(data: image.imageData, typeIdentifier: image.typeIdentifier))
            } else {
                parts.append(.text((storage.string as NSString).substring(with: range)))
            }
        }
        return NoteDocument(parts: parts)
    }

    override func shouldChangeText(in affectedCharRange: NSRange, replacementString: String?) -> Bool {
        guard let replacementString, let storage = textStorage,
              affectedCharRange.location != NSNotFound,
              affectedCharRange.location <= storage.length,
              affectedCharRange.length <= storage.length - affectedCharRange.location else {
            return super.shouldChangeText(in: affectedCharRange, replacementString: replacementString)
        }
        let end = NSMaxRange(affectedCharRange)
        let beforeImage = affectedCharRange.location > 0 && imageAttachment(at: affectedCharRange.location - 1) != nil
        let afterImage = end < storage.length && imageAttachment(at: end) != nil
        let text = storage.string as NSString
        if beforeImage {
            let nextIsNewline = end < storage.length && text.substring(with: NSRange(location: end, length: 1)) == "\n"
            guard replacementString.hasPrefix("\n") || (replacementString.isEmpty && (nextIsNewline || end == storage.length)) else {
                imageBoundaryFailure?()
                return false
            }
        }
        if afterImage {
            let previousIsNewline = affectedCharRange.location > 0 && text.substring(with: NSRange(location: affectedCharRange.location - 1, length: 1)) == "\n"
            guard replacementString.hasSuffix("\n") || (replacementString.isEmpty && (previousIsNewline || affectedCharRange.location == 0)) else {
                imageBoundaryFailure?()
                return false
            }
        }
        return super.shouldChangeText(in: affectedCharRange, replacementString: replacementString)
    }

    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        typingAttributes = bodyAttributes
        if let attributed = insertString as? NSAttributedString {
            var unsupported = false
            attributed.enumerateAttribute(.attachment, in: NSRange(location: 0, length: attributed.length)) { value, _, _ in
                if value != nil && !(value is RascImageAttachment) { unsupported = true }
            }
            if unsupported { imagePasteFailure?(); return }
        }
        let value = (insertString as? NSAttributedString)?.string ?? (insertString as? String)
        let selected = replacementRange.location == NSNotFound ? selectedRange() : replacementRange
        if let value, !value.isEmpty, selected.length == 0,
           selected.location <= (string as NSString).length {
            let before = selected.location > 0 && imageAttachment(at: selected.location - 1) != nil
            let after = selected.location < (string as NSString).length && imageAttachment(at: selected.location) != nil
            if before || after {
                let prefix = before && !value.hasPrefix("\n") ? "\n" : ""
                let suffix = after && !value.hasSuffix("\n") ? "\n" : ""
                super.insertText(prefix + value + suffix, replacementRange: selected)
                setSelectedRange(NSRange(location: selected.location + ((prefix + value) as NSString).length, length: 0))
                return
            }
        }
        if value == " ", selected.length == 0, selected.location > 0 {
            let text = string as NSString
            let line = text.lineRange(for: NSRange(location: selected.location, length: 0))
            if selected.location == line.location + 1, text.substring(with: NSRange(location: line.location, length: 1)) == "-" {
                super.insertText(marker, replacementRange: NSRange(location: line.location, length: 1))
                return
            }
        }
        super.insertText(insertString, replacementRange: replacementRange)
    }

    override func insertNewline(_ sender: Any?) {
        let selection = selectedRange()
        guard selection.length == 0 else { super.insertNewline(sender); return }
        let text = string as NSString
        let line = text.lineRange(for: selection)
        let prefixLength = (marker as NSString).length
        guard line.length >= prefixLength,
              text.substring(with: NSRange(location: line.location, length: prefixLength)) == marker,
              selection.location >= line.location + prefixLength else {
            super.insertNewline(sender); return
        }
        let lineText = text.substring(with: line).trimmingCharacters(in: .newlines)
        if lineText == marker {
            super.insertText("", replacementRange: NSRange(location: line.location, length: prefixLength))
        } else {
            super.insertText("\n" + marker, replacementRange: selection)
        }
    }

    override func deleteBackward(_ sender: Any?) {
        let selection = selectedRange()
        if selection.length == 0, selection.location >= 2,
           (string as NSString).substring(with: NSRange(location: selection.location - 1, length: 1)) == "\n",
           imageAttachment(at: selection.location - 2) != nil {
            setSelectedRange(NSRange(location: selection.location - 2, length: 1))
            return
        }
        let length = (marker as NSString).length
        if selection.length == 0, selection.location >= length {
            let text = string as NSString
            let line = text.lineRange(for: selection)
            if selection.location == line.location + length,
               text.substring(with: NSRange(location: line.location, length: length)) == marker {
                super.insertText("", replacementRange: NSRange(location: line.location, length: length))
                return
            }
        }
        super.deleteBackward(sender)
    }

    override func deleteForward(_ sender: Any?) {
        let selection = selectedRange()
        let text = string as NSString
        if selection.length == 0, selection.location + 1 < text.length,
           text.substring(with: NSRange(location: selection.location, length: 1)) == "\n",
           imageAttachment(at: selection.location + 1) != nil {
            setSelectedRange(NSRange(location: selection.location + 1, length: 1))
            return
        }
        super.deleteForward(sender)
    }

    func applyParagraphStyles() {
        applyBodyAttributes()
        guard let layoutManager, let textStorage else { return }
        let full = NSRange(location: 0, length: textStorage.length)
        layoutManager.removeTemporaryAttribute(.paragraphStyle, forCharacterRange: full)
        let text = string as NSString
        var location = 0
        while location < text.length {
            let line = text.lineRange(for: NSRange(location: location, length: 0))
            let style = NSMutableParagraphStyle()
            style.lineSpacing = RascSurfaceMetrics.noteLineSpacing
            if line.length >= 2, text.substring(with: NSRange(location: location, length: 2)) == marker {
                style.headIndent = (marker as NSString).size(withAttributes: [.font: font ?? RascSurfaceMetrics.noteFont]).width
            }
            layoutManager.addTemporaryAttribute(.paragraphStyle, value: style, forCharacterRange: line)
            location = NSMaxRange(line)
        }
    }
}

private final class RascImagePreviewWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) { close() }
}

private final class RascImageAttachment: NSTextAttachment {
    let imageData: Data
    let typeIdentifier: String
    var preview: CGImage?

    init(data: Data, type: String) {
        imageData = data
        typeIdentifier = type
        super.init(data: data, ofType: type)
    }

    required init?(coder: NSCoder) { nil }
}

private struct ScratchpadEmptyState: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: RascSurfaceMetrics.scratchpadEmptySupportingGap) {
            Text("Write something unfinished…")
                .font(.system(size: RascSurfaceMetrics.scratchpadPlaceholderFontSize, weight: .regular))
                .foregroundStyle(scratchpadPlaceholderText)

            Text("Thoughts, ideas, or images. Type “- ” to start a list.")
                .font(.system(size: 13.5, weight: .regular))
                .foregroundStyle(scratchpadSupportingText)
        }
        .padding(.leading, RascSurfaceLayout.textContainerHorizontalInset)
        .padding(.top, RascSurfaceLayout.scratchpadEditorCaretTopInset)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var scratchpadPlaceholderText: Color {
        colorScheme == .dark
            ? Color.secondary.opacity(0.76)
            : Color.primary.opacity(0.38)
    }

    private var scratchpadSupportingText: Color {
        RascSurfacePalette.homeSupportingText(for: colorScheme)
            .opacity(colorScheme == .dark ? 0.86 : 0.88)
    }
}

private struct ScratchpadChromeIconButton: View {
    let systemName: String
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.tertiary)
                .frame(width: 26, height: 26)
                .background {
                    if isHovered {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(RascSurfacePalette.subtleFill(for: colorScheme))
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

private struct ScratchpadChromeButton: View {
    let title: String
    var shortcut: String?
    var isPrimary = false
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let shortcut {
                    Text(shortcut)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isPrimary ? RascSurfacePalette.actionAccent(for: colorScheme) : Color.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background {
                if isHovered || isPrimary {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isPrimary ? RascSurfacePalette.actionAccent(for: colorScheme).opacity(0.08) : RascSurfacePalette.subtleFill(for: colorScheme))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

private struct RefinementActionLabel: View {
    let title: String
    let shortcut: String
    var isPrimary = false

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 7) {
            Text(shortcut)
                .font(.caption2.monospaced().weight(.medium))
                .foregroundStyle(
                    isPrimary
                        ? RascSurfacePalette.actionAccent(for: colorScheme)
                        : Color.secondary
                )

            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(
                    isPrimary
                        ? RascSurfacePalette.actionAccent(for: colorScheme)
                        : Color.secondary
                )
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background {
            if isPrimary {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(RascSurfacePalette.actionAccent(for: colorScheme).opacity(0.10))
            }
        }
        .overlay {
            if isPrimary {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        RascSurfacePalette.actionAccent(for: colorScheme).opacity(0.22),
                        lineWidth: 1
                    )
            }
        }
        .contentShape(Rectangle())
    }
}

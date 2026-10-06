import AppKit
import SwiftUI

struct ScratchpadView: View {
    @Bindable var session: ScratchpadSession
    @FocusState private var editorIsFocused: Bool
    @State private var showsOriginal = false
    @Environment(\.undoManager) private var undoManager
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let onEscape: () -> Void
    let onPaletteCommand: (PaletteCommand) -> Void
    let onOpenHome: () -> Void
    let onKeep: () -> Void
    let onUnkeep: () -> Void

    var body: some View {
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
        .animation(RascMotion.micro(reduceMotion: reduceMotion), value: session.message)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let saveErrorMessage = session.saveErrorMessage {
                feedbackRow(saveErrorMessage) {
                    if session.lastDiscard != nil {
                        Button("Undo") { Task { await session.undoDiscard() } }
                    } else {
                        Button("Retry") { Task { await session.retrySave() } }
                    }
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
        }
        .padding(.horizontal, RascSurfaceLayout.horizontalInset)
        .padding(.top, RascSurfaceLayout.topInset)
        .padding(.bottom, RascSurfaceLayout.scratchpadChromeBottomPadding)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var scratchpadTrailingActions: some View {
        HStack(spacing: 2) {
            if showsRefineAction {
                ScratchpadChromeButton(
                    title: "Refine",
                    shortcut: "⌘J",
                    action: { session.startRefinement() }
                )
                .keyboardShortcut("j", modifiers: .command)
                .accessibilityLabel("Refine")
                .help("Refine note")
                .transition(.opacity)
            }

            if session.surface == .editor, session.canPerformThoughtCompletion {
                if session.isActiveNoteKept {
                    ScratchpadChromeButton(title: "Unkeep", action: onUnkeep)
                        .accessibilityLabel("Unkeep")
                } else if session.hasPersistableContent {
                    ScratchpadChromeButton(
                        title: "Keep",
                        shortcut: "⇧⌘K",
                        isPrimary: true,
                        action: onKeep
                    )
                    .keyboardShortcut("k", modifiers: [.command, .shift])
                    .accessibilityLabel("Keep")
                    .help("Keep note")
                }
            }

            if showsHomeAffordance {
                scratchpadHomeButton
            }
        }
        .animation(RascMotion.micro(reduceMotion: reduceMotion), value: showsRefineAction)
    }

    private var scratchpadHomeButton: some View {
        ScratchpadChromeIconButton(
            systemName: "house",
            action: onOpenHome
        )
        .help("Open Home (⌘⌥\\)")
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
            if #available(macOS 15.0, *) {
                SelectableScratchEditor(session: session, onEscape: handleEscape)
            } else {
                TextEditor(text: $session.text)
                    .scrollContentBackground(.hidden)
                    .background(.clear)
                    .font(.system(
                        size: RascSurfaceMetrics.noteFontSize,
                        weight: .regular
                    ))
                    .lineSpacing(RascSurfaceMetrics.noteLineSpacing)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, RascSurfaceMetrics.editorHorizontalPadding)
                    .padding(.top, RascSurfaceMetrics.editorTopPadding)
                    .focused($editorIsFocused)
                    .accessibilityLabel("Scratchpad")
                    .accessibilityHint("Write an unfinished thought. Refine is optional; Keep finishes it.")
                    .onChange(of: session.focusRequest, initial: true) {
                        requestEditorFocus()
                    }
                    .onChange(of: session.text) {
                        session.scheduleAutosave()
                    }
                    .onExitCommand(perform: handleEscape)
            }

            if session.surface == .editor, session.text.isEmpty {
                ScratchpadEmptyState()
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
                    RefinementActionLabel(title: "Keep original", shortcut: "Esc")
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
                    RefinementActionLabel(title: "Accept suggestion", shortcut: "↵", isPrimary: true)
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

    private func requestEditorFocus() {
        Task { @MainActor in
            editorIsFocused = true
        }
    }

    private func handleEscape() {
        if !session.handleEscape() {
            onEscape()
        }
    }
}

@available(macOS 15.0, *)
private struct SelectableScratchEditor: View {
    @Bindable var session: ScratchpadSession
    @State private var selection: TextSelection?
    @FocusState private var isFocused: Bool

    let onEscape: () -> Void

    init(session: ScratchpadSession, onEscape: @escaping () -> Void) {
        self.session = session
        self.onEscape = onEscape
        _selection = State(initialValue: session.editorSelection.map { TextSelection(range: $0) })
    }

    var body: some View {
        TextEditor(text: $session.text, selection: $selection)
            .scrollContentBackground(.hidden)
            .background(.clear)
            .font(.system(
                size: RascSurfaceMetrics.noteFontSize,
                weight: .regular
            ))
            .lineSpacing(RascSurfaceMetrics.noteLineSpacing)
            .foregroundStyle(.primary)
            .padding(.horizontal, RascSurfaceMetrics.editorHorizontalPadding)
            .padding(.top, RascSurfaceMetrics.editorTopPadding)
            .focused($isFocused)
            .accessibilityLabel("Scratchpad")
            .accessibilityHint("Write an unfinished thought. Refine is optional; Keep finishes it.")
            .onChange(of: session.focusRequest, initial: true) {
                Task { @MainActor in
                    isFocused = true
                }
            }
            .onChange(of: selection, initial: true) {
                session.updateEditorSelection(
                    singleSelectionRange,
                    hasMultipleSelections: selectionIsMultiple
                )
            }
            .onChange(of: session.text) {
                session.updateEditorSelection(
                    singleSelectionRange,
                    hasMultipleSelections: selectionIsMultiple
                )
                session.scheduleAutosave()
            }
            .onExitCommand(perform: onEscape)
    }

    private var singleSelectionRange: Range<String.Index>? {
        guard let selection else { return nil }
        switch selection.indices {
        case let .selection(range):
            return range.isEmpty ? nil : range
        case let .multiSelection(ranges):
            guard ranges.ranges.count == 1,
                  let range = ranges.ranges.first,
                  !range.isEmpty
            else {
                return nil
            }
            return range
        @unknown default:
            return nil
        }
    }

    private var selectionIsMultiple: Bool {
        guard let selection else { return false }
        if case let .multiSelection(ranges) = selection.indices {
            return ranges.ranges.count > 1
        }
        return false
    }
}

private struct ScratchpadEmptyState: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: RascSurfaceMetrics.scratchpadEmptySupportingGap) {
            Text("Write something unfinished…")
                .font(.system(size: RascSurfaceMetrics.scratchpadPlaceholderFontSize, weight: .regular))
                .foregroundStyle(scratchpadPlaceholderText)

            Text("Thoughts, tasks, messages, ideas. Anything goes.")
                .font(.system(size: 13.5, weight: .regular))
                .foregroundStyle(scratchpadSupportingText)
        }
        .padding(.leading, RascSurfaceMetrics.placeholderLeadingInset)
        .padding(.top, RascSurfaceMetrics.placeholderTopInset)
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
                        .foregroundStyle(.tertiary)
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

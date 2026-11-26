import KeyboardShortcuts
import SwiftUI

enum StudyAppearance: String, CaseIterable, Identifiable {
    case system = "System", light = "Light", dark = "Dark"
    var id: Self { self }
    var scheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

struct StudyView: View {
    @Bindable var session: StudySession
    @Environment(\.colorScheme) private var scheme
    @FocusState private var transcriptFocused: Bool
    @State private var showOriginal = false
    @State private var editing: EditSnapshot?
    @State private var update = ""
    @State private var writingEdit = false

    private struct EditSnapshot: Identifiable {
        let note: Note
        var id: UUID { note.id }
    }

    private var palette: RascSurfacePalette { .init(preset: session.theme) }
    private var reviewing: Bool {
        session.phase == .review || session.canRetryWrite ||
            (!session.raw.isEmpty && [.saving, .discarding].contains(session.phase))
    }
    private var reviewingBusy: Bool { [.saving, .discarding].contains(session.phase) || session.dataBusy }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                header
                Group {
                    if reviewing { review }
                    else if let note = session.opened { thought(note) }
                    else { scratch }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                if let message = secondaryMessage {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(palette.secondaryText(for: scheme))
                        .padding(.top, 8)
                        .accessibilityIdentifier("study-status")
                }
                footer
            }
            .padding(24)
        }
        .frame(minWidth: 585, minHeight: 365)
        .foregroundStyle(palette.noteText(for: scheme))
        .background(palette.canvas(for: scheme))
        .environment(\.rascPalette, palette)
        .onChange(of: session.phase) { _, phase in
            guard phase == .review else { return }
            showOriginal = false
            transcriptFocused = true
        }
        .onExitCommand {
            if session.canCancel { session.cancel() }
            else { session.opened = nil }
        }
        .sheet(isPresented: $session.showingOptions) { StudyOptions(session: session) }
        .sheet(item: $editing, onDismiss: { session.editingKeptThought = false }) { snapshot in
            VStack(alignment: .leading, spacing: 16) {
                Text("Edit thought").font(.title2.weight(.semibold))
                TextEditor(text: $update).font(.body)
                    .disabled(writingEdit)
                    .accessibilityLabel("Thought text")
                    .frame(minHeight: 170)
                HStack {
                    Button("Cancel") { editing = nil }
                        .keyboardShortcut(.cancelAction)
                        .disabled(writingEdit)
                    Spacer()
                    Button(writingEdit ? "Saving…" : "Save") {
                        writingEdit = true
                        let text = update
                        Task {
                            if await session.editThought(snapshot.note, text: text) { editing = nil }
                            writingEdit = false
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(writingEdit || !update.contains(where: { $0.isLetter || $0.isNumber }))
                }
            }
            .padding(24)
            .frame(width: 460)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(reviewing ? "Review thought" : session.opened == nil ? "Scratch" : "Thought")
                .font(.system(size: 24, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if reviewing {
                Button(showOriginal ? "Edit transcript" : "Original transcript") {
                    showOriginal.toggle()
                    if !showOriginal { transcriptFocused = true }
                }
                .buttonStyle(.borderless)
            } else if let note = session.opened {
                Button("Edit") {
                    update = note.content
                    session.editingKeptThought = true
                    editing = EditSnapshot(note: note)
                }
                .buttonStyle(.borderless)
                Label("Kept", systemImage: "checkmark")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .foregroundStyle(palette.keepAccent(for: scheme))
                    .background(palette.keepFill(for: scheme), in: Capsule())
            }
        }
        .padding(.bottom, 12)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 10) {
            nav("Scratch", symbol: "square.and.pencil", selected: session.opened == nil && !reviewing) {
                session.opened = nil
            }
            .disabled(reviewing)
            Text("Kept")
                .font(.caption.weight(.semibold))
                .foregroundStyle(palette.metadataText(for: scheme))
                .padding(.leading, 8)
                .padding(.top, 8)
                .accessibilityAddTraits(.isHeader)
            if session.notes.isEmpty {
                Text("Kept thoughts appear here.")
                    .font(.caption)
                    .foregroundStyle(palette.secondaryText(for: scheme))
                    .padding(.horizontal, 8)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 3) {
                    ForEach(session.notes, id: \.id) { note in
                        nav(note.displayTitle, selected: session.opened?.id == note.id && !reviewing) {
                            session.opened = note
                        }.disabled(reviewing)
                    }
                }
            }
            Spacer(minLength: 2)
            Button("Study Options", systemImage: "slider.horizontal.3") { session.showingOptions = true }
                .buttonStyle(.borderless)
                .disabled(!session.optionsEnabled)
                .help("Change speech engine, shortcut, or Keep behavior")
                .padding(.horizontal, 8)
        }
        .padding(12)
        .frame(width: 174)
        .background(palette.subtleFill(for: scheme))
    }

    private func nav(_ title: String, symbol: String? = nil, selected: Bool,
                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let symbol { Image(systemName: symbol).accessibilityHidden(true) }
                Text(title).lineLimit(2).multilineTextAlignment(.leading)
            }
            .font(.callout.weight(selected ? .medium : .regular))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8).padding(.vertical, 7)
            .background(selected ? palette.raisedFill(for: scheme) : .clear,
                        in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var scratch: some View {
        ZStack(alignment: .topLeading) {
            if session.draft.isEmpty {
                Text("Start typing.")
                    .font(.body)
                    .foregroundStyle(palette.secondaryText(for: scheme))
                    .padding(.leading, 5).padding(.top, 5)
                    .accessibilityHidden(true)
            }
            TextEditor(text: $session.draft)
                .font(.body)
                .scrollContentBackground(.hidden)
                .accessibilityLabel("Unfinished scratch")
                .disabled(!session.storageReady || session.dataBusy)
                .onChange(of: session.draft) { _, text in session.saveDraft(text) }
        }
    }

    @ViewBuilder private var review: some View {
        if showOriginal {
            ScrollView {
                Text(session.raw)
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityLabel("Original transcript")
        } else {
            TextEditor(text: $session.edited)
                .font(.body)
                .scrollContentBackground(.hidden)
                .focused($transcriptFocused)
                .accessibilityLabel("Edit transcript")
                .disabled(reviewingBusy)
                .onChange(of: session.edited) { _, _ in session.saveReviewEdit() }
        }
    }

    private func thought(_ note: Note) -> some View {
        ScrollView {
            Text(note.content).font(.body).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var secondaryMessage: String? {
        if let issue = session.draftIssue { return issue }
        if let notice = session.notice { return notice }
        switch session.phase {
        case .recovery(.permissionDenied): return "Allow Rasc Voice Capture in Privacy & Security, then try again."
        case .recovery(.microphone): return "Check the selected sound input and try again."
        case .recovery(.setup):
            return session.selectedEngine == .apple
                ? "Prepare speech for the selected language in Study Options."
                : "The bundled speech model couldn’t open. Reinstall the signed study app if preparation keeps failing."
        case .recovery(.transcript), .recovery(.timeout): return "The recording is still here. Retry or discard it."
        case .recovery(.save): return "The transcript is still here. Try keeping it again."
        case .silent: return "No speech heard."
        default: return nil
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if !session.storageReady {
                if session.draftIssue == nil {
                    Text("Opening study…")
                        .font(.callout)
                        .foregroundStyle(palette.secondaryText(for: scheme))
                }
                Spacer(minLength: 0)
            } else if reviewingBusy && reviewing {
                Text(session.phase.text)
                    .font(.callout)
                    .foregroundStyle(palette.secondaryText(for: scheme))
                Spacer(minLength: 0)
            } else if reviewing {
                if session.hasAudio && session.logTimings {
                    Menu("Evaluation") {
                        Button("Save recording locally", action: session.exportEvaluationAudio)
                    }
                    .menuStyle(.button)
                    .fixedSize()
                }
                Spacer(minLength: 0)
                Button("Discard", action: session.cancel)
                Button(session.canRetryWrite ? "Retry Keep" : "Keep", action: session.keep)
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(KeepStyle(palette: palette, scheme: scheme))
                    .disabled(!session.edited.contains(where: { $0.isLetter || $0.isNumber }))
            } else if session.canRetry {
                Button("Retry Transcription", action: session.retryTranscription)
                Button("Discard", action: session.cancel)
                Spacer(minLength: 0)
            } else if session.phase == .recovery(.permissionDenied) {
                Button("Open Microphone Settings", action: session.openMicrophoneSettings)
                Button("Try Again", action: session.start)
                Spacer(minLength: 0)
            } else if session.canStart {
                if session.assetReady {
                    Button("Start Recording", systemImage: "mic", action: session.start)
                        .accessibilityIdentifier("start-recording")
                    if session.globalShortcut, let shortcut = KeyboardShortcuts.getShortcut(for: .voiceStudy) {
                        ShortcutKeycapView(label: shortcut.description, style: .compact)
                    }
                } else {
                    Button("Prepare Speech", action: session.prepareModel)
                        .help("Prepares the selected on-device speech model")
                }
                Spacer(minLength: 0)
                if session.phase == .kept {
                    Button("Undo Capture", action: session.undo)
                        .buttonStyle(.borderless)
                }
            } else {
                Text(session.phase.text)
                    .font(.callout)
                    .foregroundStyle(palette.secondaryText(for: scheme))
                Spacer(minLength: 0)
                if [.starting, .listening].contains(session.phase) {
                    Button("Finish") { session.finish() }
                }
                if session.canCancel { Button("Cancel", action: session.cancel) }
            }
        }
        .controlSize(.regular)
        .padding(.top, 12)
    }
}

private struct StudyOptions: View {
    @Bindable var session: StudySession
    @Environment(\.dismiss) private var dismiss
    @State private var reset = false
    @State private var shareText = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Study Options").font(.title2.weight(.semibold)).accessibilityAddTraits(.isHeader)
            Form {
                Section("Capture") {
                    Picker("Speech engine", selection: Binding(get: { session.selectedEngine }, set: { engine in session.chooseEngine(engine) })) {
                        ForEach(StudyEngine.allCases) { Text($0.title).tag($0) }
                    }
                    if session.selectedEngine == .apple {
                        Picker("Speech language", selection: $session.language) {
                            Text("Português (Brasil)").tag("pt-BR")
                            Text("English (US)").tag("en-US")
                        }
                        .onChange(of: session.language) { _, _ in Task { await session.checkModel() } }
                    }
                    Picker("Shortcut behavior", selection: $session.activation) {
                        ForEach(Activation.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Picker("After finishing", selection: $session.completion) {
                        ForEach(Completion.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Toggle("Use a global shortcut", isOn: $session.globalShortcut)
                    if session.globalShortcut {
                        KeyboardShortcuts.Recorder("Voice Capture", name: .voiceStudy)
                    }
                }
                Section("Appearance") {
                    Picker("Theme", selection: $session.theme) {
                        ForEach(ThemePreset.allCases.filter { $0 != .custom }) { Text($0.displayName).tag($0) }
                    }
                    Picker("Appearance", selection: $session.appearance) {
                        ForEach(StudyAppearance.allCases) { Text($0.rawValue).tag($0) }
                    }
                }
                Section("Evaluation") {
                    Toggle("Save timing results locally", isOn: $session.logTimings)
                    if !session.metrics.isEmpty {
                        ForEach(session.metrics.keys.sorted(), id: \.self) { key in
                            LabeledContent(key, value: "\(Int(session.metrics[key] ?? 0)) ms")
                                .monospacedDigit()
                        }
                    }
                    if session.logTimings && session.phase == .kept && !session.raw.isEmpty {
                        Button("Save transcript comparison…") { shareText = true }
                    }
                    Button("Show Study Files", action: session.revealStudyFiles)
                    Button("Reset Study Data…", role: .destructive) { reset = true }
                }
            }
            .formStyle(.grouped)
            .frame(height: 355)
            HStack {
                Button("Prepare Speech") { dismiss(); session.prepareModel() }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 469)
        .alert("Reset study data?", isPresented: $reset) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) { dismiss(); session.resetStudyData() }
        } message: {
            Text("This removes the study’s scratch, Kept thoughts, and evaluation files.")
        }
        .alert("Save both versions locally?", isPresented: $shareText) {
            Button("Cancel", role: .cancel) {}
            Button("Save") { session.exportTranscriptComparison() }
        } message: {
            Text("The original transcript and Kept text will be written to the study’s Evaluation folder.")
        }
    }
}

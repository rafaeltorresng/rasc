import AppKit
import AVFoundation
import KeyboardShortcuts
import SwiftUI
#if STUDY_UPDATER
import Sparkle
#endif

private final class CapturePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class StudyDelegate: NSObject, NSApplicationDelegate {
    let session = StudySession()
    weak var window: NSWindow?
    private var panel: CapturePanel?
    private var item: NSStatusItem?
    #if STUDY_UPDATER
    private var updater: SPUStandardUpdaterController?
    #endif

    func applicationDidFinishLaunching(_ notification: Notification) {
        session.presentStatus = { [weak self] in self?.showStatus() }
        session.hideStatus = { [weak self] in self?.panel?.orderOut(nil) }
        session.showStudy = { [weak self] in self?.bringForward() }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(willSleep),
                                                          name: NSWorkspace.willSleepNotification, object: nil)
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "mic", accessibilityDescription: "Rasc Voice Study")
        let menu = NSMenu()
        for (title, action) in [
            ("Start or Finish Recording", #selector(toggle)),
            ("Cancel Recording", #selector(cancel)),
            ("Open Last Capture", #selector(openLast)),
            ("Undo Last Capture", #selector(undo)),
            ("Open Rasc Voice Study", #selector(openWindow)),
        ] {
            let entry = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
            entry.target = self
        }
        #if STUDY_UPDATER
        updater = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        let update = menu.addItem(withTitle: "Check for Study Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
        update.target = self
        if CommandLine.arguments.contains("--check-study-update") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.checkForUpdates() }
        }
        #endif
        item.menu = menu
        self.item = item
        Task { await session.load() }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Task {
            let canQuit = await session.prepareToQuit()
            if !canQuit {
                bringForward()
                session.notice = "Keep, discard, or retry your capture before quitting."
            }
            sender.reply(toApplicationShouldTerminate: canQuit)
        }
        return .terminateLater
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        bringForward()
        return true
    }

    private func showStatus() {
        let frame = CGRect(x: 0, y: 0, width: 322, height: 74)
        let panel = panel ?? CapturePanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                                          backing: .buffered, defer: false)
        if self.panel == nil {
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            panel.contentView = NSHostingView(rootView: StatusCapsule(session: session))
            self.panel = panel
        }
        if !panel.isVisible {
            let pointer = NSEvent.mouseLocation
            if let screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) }) ?? NSScreen.main {
                panel.setFrameOrigin(.init(x: screen.visibleFrame.midX - frame.width / 2,
                                           y: screen.visibleFrame.minY + 22))
            }
        }
        panel.orderFrontRegardless()
    }

    private func bringForward() {
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    @objc private func toggle() { session.shortcutAction() }
    @objc private func cancel() { session.cancel() }
    @objc private func openLast() { session.openReceipt() }
    @objc private func undo() { session.undo() }
    @objc private func openWindow() { bringForward() }
    @objc private func willSleep() { session.finish(interrupted: true) }
    #if STUDY_UPDATER
    @objc private func checkForUpdates() { updater?.checkForUpdates(nil) }
    #endif
}

private struct WindowRegistration: NSViewRepresentable {
    let result: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { if let window = view.window { result(window) } }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) { }
}

private struct StatusCapsule: View {
    var session: StudySession
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let palette = RascSurfacePalette(preset: session.theme)
        HStack(spacing: 7) {
            if session.phase == .kept {
                Label("Kept", systemImage: "checkmark")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .foregroundStyle(palette.keepAccent(for: scheme))
                    .background(palette.keepFill(for: scheme), in: Capsule())
                Spacer(minLength: 5)
                if session.completion == .receipt {
                    textButton("Open", action: session.openReceipt)
                    textButton("Undo", action: session.undo)
                }
            } else {
                Image(systemName: session.phase == .listening ? "mic.fill" : "mic")
                    .accessibilityHidden(true)
                Text(session.phase.text).font(.system(size: 13, weight: .semibold)).lineLimit(2)
                Spacer(minLength: 4)
                if session.phase == .listening {
                    MicLevel(value: session.level)
                    iconButton("Finish recording", icon: "stop.fill") { session.finish() }
                }
                if session.canCancel {
                    iconButton("Cancel recording", icon: "xmark", action: session.cancel)
                }
            }
        }
        .padding(.leading, 15).padding(.trailing, 9)
        .frame(width: 300, height: 49)
        .foregroundStyle(palette.noteText(for: scheme))
        .background(palette.raisedFill(for: scheme), in: Capsule())
        .overlay { Capsule().strokeBorder(palette.border(for: scheme), lineWidth: contrast == .increased ? 2 : 1) }
        .shadow(color: .black.opacity(scheme == .dark ? 0.25 : 0.14), radius: 10, y: 5)
        .padding(8)
        .accessibilityElement(children: .contain)
        .onChange(of: session.phase) { _, phase in announce(phase.text) }
    }

    private func textButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 12, weight: .medium)).frame(minWidth: 40, minHeight: 40)
                .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    private func iconButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 11, weight: .semibold))
                .frame(width: 40, height: 40).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel(title).help(title)
    }

    private func announce(_ value: String) {
        guard let window = NSApp.keyWindow ?? NSApp.windows.first else { return }
        NSAccessibility.post(element: window, notification: .announcementRequested,
                             userInfo: [.announcement: value, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
    }
}

private struct MicLevel: View {
    let value: Float
    var body: some View {
        let level = min(1, max(0, (20 * log10(max(value, 0.00001)) + 58) / 42))
        HStack(spacing: 2) {
            ForEach(0..<6) { index in
                Capsule().frame(width: 2, height: CGFloat(4 + index * 2))
                    .opacity(Float(index + 1) / 6 <= level ? 0.9 : 0.16)
            }
        }
        .frame(width: 24, height: 16)
        .accessibilityHidden(true)
    }
}

private struct StudyView: View {
    @Bindable var session: StudySession
    @Environment(\.colorScheme) private var scheme
    @FocusState private var reviewFocused: Bool
    @State private var showingRaw = false

    private var palette: RascSurfacePalette { .init(preset: session.theme) }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            VStack(alignment: .leading, spacing: 15) {
                if session.phase == .review || session.canRetryWrite {
                    review
                } else if let opened = session.opened {
                    kept(opened)
                } else {
                    scratch
                }
                if case .failure(let message) = session.phase { recovery(message) }
                if case .notice(let message) = session.phase {
                    Text(message).font(.callout).foregroundStyle(palette.secondaryText(for: scheme))
                } else if let notice = session.notice {
                    Text(notice).font(.callout).foregroundStyle(palette.secondaryText(for: scheme))
                }
                Divider()
                controls
            }.padding(25)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(palette.canvas(for: scheme))
        .foregroundStyle(palette.noteText(for: scheme))
        .frame(minWidth: 725, minHeight: 455)
        .onChange(of: session.phase) { _, phase in
            if case .review = phase { showingRaw = false; reviewFocused = true }
        }
        .onExitCommand {
            if session.canCancel { session.cancel() }
            else { session.opened = nil }
        }
        .sheet(isPresented: $session.showingOptions) { StudyOptions(session: session) }
        .task(id: session.selectedEngine.rawValue + session.language) { await session.checkModel() }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("Voice Study").font(.system(size: 15, weight: .semibold))
            Button {
                session.opened = nil
            } label: {
                Label("Scratch", systemImage: "square.and.pencil")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(session.opened == nil ? palette.raisedFill(for: scheme) : .clear,
                                in: RoundedRectangle(cornerRadius: 8))
            }.buttonStyle(.plain)
            Divider()
            Text("Kept thoughts").font(.caption.weight(.semibold))
                .foregroundStyle(palette.secondaryText(for: scheme))
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 5) {
                    ForEach(session.notes, id: \.id) { note in
                        Button { session.opened = note } label: {
                            Text(note.displayTitle).lineLimit(2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(7)
                                .background(session.opened?.id == note.id ? palette.raisedFill(for: scheme) : .clear,
                                            in: RoundedRectangle(cornerRadius: 8))
                        }.buttonStyle(.plain)
                    }
                }
            }
            Button("Study Options…", systemImage: "slider.horizontal.3") { session.showingOptions = true }
                .disabled(!session.optionsEnabled)
        }
        .padding(14).frame(width: 204)
        .background(palette.subtleFill(for: scheme))
    }

    private var scratch: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Scratch").font(.system(size: 23, weight: .semibold))
            TextEditor(text: $session.draft)
                .font(.system(size: 16))
                .scrollContentBackground(.hidden)
                .accessibilityLabel("Unfinished study scratch")
                .onChange(of: session.draft) { _, text in session.saveDraft(text) }
            if let failure = session.draftIssue {
                Text(failure).font(.callout)
                    .foregroundStyle(palette.destructiveText(for: scheme))
            }
        }
    }

    private var review: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Review thought").font(.system(size: 23, weight: .semibold))
                Spacer()
                Toggle("Recognized text", isOn: $showingRaw).toggleStyle(.switch).controlSize(.small)
            }
            if showingRaw {
                ScrollView {
                    Text(session.raw).textSelection(.enabled).font(.system(size: 16))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                TextEditor(text: $session.edited)
                    .font(.system(size: 16))
                    .scrollContentBackground(.hidden)
                    .focused($reviewFocused)
                    .accessibilityLabel("Edit voice transcript")
            }
            HStack {
                if session.hasAudio { Button("Save Evaluation Audio", action: session.exportEvaluationAudio) }
                Spacer()
                Button("Discard", action: session.cancel)
                Button("Keep", action: session.keep)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(session.edited.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .buttonStyle(KeepStyle(palette: palette, scheme: scheme))
            }
        }
    }

    private func kept(_ note: Note) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Thought").font(.system(size: 23, weight: .semibold))
                Spacer()
                Label("Kept", systemImage: "checkmark").font(.callout.bold())
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .foregroundStyle(palette.keepAccent(for: scheme))
                    .background(palette.keepFill(for: scheme), in: Capsule())
            }
            ScrollView {
                Text(note.content).font(.system(size: 16)).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func recovery(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(message).foregroundStyle(palette.destructiveText(for: scheme))
            HStack {
                if session.canRetryWrite { Button("Retry Save", action: session.keep) }
                else if session.canRetry { Button("Retry Transcription", action: session.retryTranscription) }
                if session.canCancel { Button("Discard", action: session.cancel) }
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 10) {
            if !session.modelReady && session.selectedEngine == .apple && session.canStart {
                Button("Prepare Language…", action: session.prepareModel)
            } else if session.canStart {
                Button("Start Recording", systemImage: "mic", action: session.start)
                    .disabled(!session.modelReady)
                if session.selectedEngine != .apple && session.receipt == nil {
                    Button("Prepare Model", action: session.prepareModel)
                        .help("Prepare the local model before speaking. Cold loads can take several seconds.")
                        .disabled(!session.modelReady)
                }
                if session.receipt != nil {
                    Button("Open Last Capture", action: session.openReceipt)
                    Button("Undo", action: session.undo)
                }
            } else if session.phase == .listening || session.phase == .starting {
                Button("Finish Recording") { session.finish() }
                Button("Cancel", action: session.cancel)
            } else if session.phase != .review && session.phase != .kept {
                Text(session.phase.text).font(.callout)
                if session.canCancel && !session.canRetry { Button("Cancel", action: session.cancel) }
            }
            Spacer()
            Text(session.selectedEngine.title).font(.caption)
                .foregroundStyle(palette.metadataText(for: scheme))
        }
    }
}

private struct KeepStyle: ButtonStyle {
    let palette: RascSurfacePalette
    let scheme: ColorScheme
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .padding(.horizontal, 15).padding(.vertical, 7)
            .foregroundStyle(palette.keepAccent(for: scheme))
            .background(palette.keepFill(for: scheme), in: Capsule())
            .opacity(!enabled ? 0.45 : (configuration.isPressed ? 0.75 : 1))
    }
}

private struct StudyOptions: View {
    @Bindable var session: StudySession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text("Study Options").font(.title2.weight(.semibold))
            Form {
                Picker("Engine", selection: $session.selectedEngine) {
                    ForEach(StudyEngine.allCases) { Text($0.title).tag($0) }
                }
                if session.selectedEngine == .apple {
                    Picker("Speech language", selection: $session.language) {
                        Text("Português (Brasil)").tag("pt-BR")
                        Text("English (US)").tag("en-US")
                    }
                } else {
                    LabeledContent("Speech language", value: "Automatic")
                }
                Picker("Activation", selection: $session.activation) {
                    ForEach(Activation.allCases) { Text($0.rawValue).tag($0) }
                }
                Picker("After finishing", selection: $session.completion) {
                    ForEach(Completion.allCases) { Text($0.rawValue).tag($0) }
                }
                Picker("Theme", selection: $session.theme) {
                    ForEach(ThemePreset.allCases.filter { $0 != .custom }) { Text($0.displayName).tag($0) }
                }
                Toggle("Use a global shortcut", isOn: $session.globalShortcut)
                if session.globalShortcut {
                    KeyboardShortcuts.Recorder("Voice Capture", name: .voiceStudy)
                }
            }.formStyle(.grouped).frame(height: 268)
            if !session.metrics.isEmpty {
                Grid(alignment: .leading, verticalSpacing: 4) {
                    ForEach(session.metrics.keys.sorted(), id: \.self) { key in
                        GridRow {
                            Text(key)
                            Text("\(Int(session.metrics[key] ?? 0)) ms").monospacedDigit()
                        }
                    }
                }.font(.caption).padding(.horizontal, 6)
            }
            HStack {
                Button("Show Study Files", action: session.revealEvaluationClips)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }.padding(20).frame(width: 520)
    }
}

private struct StudyScene: App {
    @NSApplicationDelegateAdaptor(StudyDelegate.self) var delegate
    var body: some Scene {
        Window("Rasc Voice Study", id: "study") {
            StudyView(session: delegate.session)
                .background(WindowRegistration { delegate.window = $0 })
        }
        .defaultSize(width: 800, height: 510)
    }
}

@main @MainActor
enum VoiceStudyMain {
    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments.first == "--benchmark" {
            Task.detached {
                await LocalBenchmark.run(Array(arguments.dropFirst()))
            }
            dispatchMain()
        }
        if arguments.first == "--prepare", arguments.count == 2 {
            let language = arguments[1]
            Task.detached {
                do {
                    try await StudyRecognizer.installApple(language: language)
                    print("Prepared \(language)")
                    exit(0)
                } catch {
                    print("Preparation failed: \(error.localizedDescription)")
                    exit(1)
                }
            }
            dispatchMain()
        }
        if arguments.first == "--validate" {
            Task { await LocalBenchmark.validate() }
            dispatchMain()
        }
        StudyScene.main()
    }
}

import AppKit
import KeyboardShortcuts
import SwiftUI

@MainActor
final class VoiceCaptureWindows: NSObject, NSWindowDelegate {
    private unowned let capture: VoiceCapture
    private(set) var status: NSPanel?
    private var review: NSPanel?
    private var previousApp: NSRunningApplication?
    private weak var previousKeyWindow: NSWindow?
    private var screenFrame: CGRect?

    init(capture: VoiceCapture) {
        self.capture = capture
    }

    var hasBlockingSheet: Bool { NSApp.modalWindow != nil || NSApp.keyWindow?.attachedSheet != nil }

    func showStatus(reposition: Bool = true) {
        let panel: NSPanel
        if let status {
            panel = status
        } else {
            let rect = CGRect(origin: .zero, size: CGSize(width: 304, height: 70))
            panel = VoiceStatusPanel(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel],
                                     backing: .buffered, defer: true)
            let capture = self.capture
            panel.contentView = NSHostingView(rootView: RascAppearanceView { VoiceStatusView(capture: capture) })
            panel.title = "Voice Capture"
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            status = panel
        }
        if reposition, !panel.isVisible {
            previousApp = NSWorkspace.shared.frontmostApplication
            previousKeyWindow = NSApp.keyWindow
            let target = NSApp.isActive ? NSApp.keyWindow?.screen : nil
            screenFrame = (target ?? WindowFramePlacement.targetPresentationScreen(
                excludingProcessID: NSRunningApplication.current.processIdentifier
            ))?.visibleFrame
        }
        if let frame = screenFrame {
            panel.setFrameOrigin(CGPoint(x: frame.midX - panel.frame.width / 2, y: frame.minY + 18))
        }
        panel.orderFrontRegardless()
    }

    func showReview() {
        if hasBlockingSheet {
            showStatus(reposition: false)
            return
        }
        hideStatus()
        let panel: NSPanel
        if let review {
            panel = review
        } else {
            panel = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 454, height: 304),
                            styleMask: [.titled, .closable, .resizable],
                            backing: .buffered, defer: true)
            panel.title = "Review Voice Capture"
            panel.isReleasedWhenClosed = false
            panel.hidesOnDeactivate = false
            panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            panel.contentMinSize = CGSize(width: 342, height: 238)
            panel.delegate = self
            let capture = self.capture
            panel.contentView = NSHostingView(rootView: RascAppearanceView { VoiceReviewView(capture: capture) })
            review = panel
        }
        if !panel.isVisible {
            if let frame = screenFrame {
                panel.setFrameOrigin(WindowFramePlacement.centeredOrigin(for: panel.frame.size, in: frame))
            } else {
                panel.center()
            }
            // A person may switch apps during a cold decode. Restore that app after review.
            previousApp = NSWorkspace.shared.frontmostApplication
            previousKeyWindow = NSApp.keyWindow
        }
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
    }

    func restorePreviousApplicationAfterPermission() {
        if NSApp.isActive, let previousApp, previousApp != .current, !previousApp.isTerminated {
            previousApp.activate()
        }
    }

    func hideStatus() { status?.orderOut(nil) }

    func hideReview() {
        guard let review, review.isVisible else { return }
        let restoreFocus = review.isKeyWindow && NSApp.isActive
        review.orderOut(nil)
        if restoreFocus {
            if let previousKeyWindow, previousKeyWindow.isVisible, previousApp == .current {
                previousKeyWindow.makeKeyAndOrderFront(nil)
            } else {
                restorePreviousApplicationAfterPermission()
            }
        }
    }

    func hide() {
        hideStatus()
        hideReview()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        capture.closeReview()
        return false
    }

    func announce(_ phase: VoiceCapture.Phase) {
        guard let status, status.isVisible else { return }
        let message: String
        switch phase {
        case .listening: message = "Listening"
        case .waitingForModel: message = "Preparing speech"
        case .transcribing: message = "Transcribing"
        case .reviewing: message = "Transcript ready to review"
        case .kept: message = "Thought kept"
        case .issue(let issue): message = issue.message
        default: return
        }
        NSAccessibility.post(element: status, notification: .announcementRequested,
                             userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
    }

    func showUndoFailure() {
        let alert = NSAlert()
        alert.messageText = "Couldn’t undo Keep"
        alert.informativeText = "The thought may have changed. Find it in Home."
        NSApp.activate()
        alert.runModal()
    }
}

private final class VoiceStatusPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

struct VoiceStatusView: View {
    @ObservedObject var capture: VoiceCapture
    @Environment(\.rascPalette) private var palette
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 26, height: 26)
                .foregroundStyle(capture.phase == .kept ? palette.keepAccent(for: scheme) : palette.secondaryText(for: scheme))
                .background(capture.phase == .kept ? palette.keepFill(for: scheme) : palette.subtleFill(for: scheme), in: Circle())
                .accessibilityHidden(true)
            Text(title)
                .font(.callout.weight(.semibold))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            actions
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .frame(width: 280, height: 48)
        .foregroundStyle(palette.noteText(for: scheme))
        .background(palette.raisedFill(for: scheme), in: Capsule())
        .overlay {
            Capsule().strokeBorder(palette.border(for: scheme), lineWidth: contrast == .increased ? 2 : 1)
                .allowsHitTesting(false)
        }
        .shadow(color: .black.opacity(scheme == .dark ? 0.28 : 0.14), radius: 8, y: 4)
        .frame(width: 304, height: 70)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Voice Capture")
    }

    @ViewBuilder private var actions: some View {
        switch capture.phase {
        case .kept:
            action("Open", call: { capture.openThought() })
            action("Undo", call: { capture.undo() })
        case .reviewing:
            action("Review", call: { capture.showReview() })
        case .listening:
            VoiceLevelMeter(rms: capture.level)
            action("Finish recording", icon: "stop.fill") { capture.finish() }
            action("Cancel recording", icon: "xmark", call: { capture.cancel() })
        case .issue(let issue):
            if issue == .permission {
                action("Settings", call: { capture.openMicrophoneSettings() })
            } else if issue == .transcription && capture.canRetryAudio {
                action("Retry", call: { capture.retry() })
            } else {
                action("Try again", call: { capture.retry() })
            }
            action("Dismiss", icon: "xmark", call: { capture.cancel() })
        case .checking, .starting, .finishing, .waitingForModel, .transcribing:
            action("Cancel recording", icon: "xmark", call: { capture.cancel() })
        default: EmptyView()
        }
    }

    private var title: String {
        switch capture.phase {
        case .idle, .checking, .starting: "Getting ready…"
        case .listening: "Listening"
        case .finishing: "Finishing…"
        case .waitingForModel: "Preparing speech…"
        case .transcribing: "Transcribing…"
        case .stopping: "Cancelling…"
        case .reviewing: "Transcript ready"
        case .saving: "Saving…"
        case .kept: "Kept"
        case .undoing: "Undoing…"
        case .issue(.permission): "Microphone access needed"
        case .issue(.microphone): "Microphone unavailable"
        case .issue(.noSpeech): "No speech heard"
        case .issue(.transcription): "Couldn’t transcribe"
        case .issue(.persistence): "Couldn’t recover capture"
        }
    }

    private var icon: String {
        switch capture.phase {
        case .kept: "checkmark"
        case .listening, .finishing: "mic.fill"
        case .waitingForModel, .transcribing, .undoing: "ellipsis"
        case .issue(.noSpeech): "waveform.slash"
        case .issue: "exclamationmark"
        default: "mic"
        }
    }

    private func action(_ title: String, icon: String? = nil, call: @escaping () -> Void) -> some View {
        Button(action: call) {
            Group {
                if let icon { Image(systemName: icon).font(.system(size: 10, weight: .semibold)) }
                else { Text(title).font(.caption.weight(.medium)) }
            }
            .padding(.horizontal, icon == nil ? 5 : 0)
            .frame(minWidth: 39, minHeight: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(VoiceStatusButton(fill: palette.subtleFill(for: scheme), reduceMotion: reduceMotion))
        .accessibilityLabel(title)
        .help(title)
    }
}

private struct VoiceStatusButton: ButtonStyle {
    let fill: Color
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? fill : .clear, in: Capsule())
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
    }
}

private struct VoiceLevelMeter: View {
    let rms: Float

    var body: some View {
        let level = min(1, max(0, (20 * log10(max(rms, 0.00001)) + 58) / 42))
        HStack(spacing: 2) {
            ForEach(0..<5) { index in
                let amount = CGFloat(max(0, min(1, level * 5 - Float(index))))
                Capsule().frame(width: 2, height: 3 + amount * CGFloat(3 + index * 2))
                    .opacity(0.34 + amount * 0.66)
            }
        }
        .frame(width: 22, height: 16)
        .accessibilityHidden(true)
    }
}

struct VoiceReviewView: View {
    @ObservedObject var capture: VoiceCapture
    @Environment(\.rascPalette) private var palette
    @Environment(\.colorScheme) private var scheme
    @Environment(\.noteTextSize) private var textSize
    @FocusState private var editorFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let message = capture.reviewMessage {
                Label(message, systemImage: "exclamationmark.circle")
                    .font(.callout)
                    .foregroundStyle(palette.secondaryText(for: scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
            TextEditor(text: Binding(get: { capture.content }, set: { capture.edit($0) }))
                .accessibilityLabel("Transcript")
                .font(.system(size: textSize.points(RascSurfaceMetrics.noteFontSize)))
                .foregroundStyle(palette.noteText(for: scheme))
                .scrollContentBackground(.hidden)
                .focused($editorFocused)
                .disabled(capture.phase != .reviewing)
                .padding(6)
                .background(palette.canvas(for: scheme), in: .rect(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(editorFocused ? palette.focusedFieldBorder(for: scheme) : palette.border(for: scheme))
                        .allowsHitTesting(false)
                }

            HStack(spacing: 10) {
                Button("Discard", role: .destructive, action: { capture.cancel() })
                    .disabled(capture.phase != .reviewing)
                Spacer()
                Button("Keep", action: { capture.keep() })
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.bordered)
                    .tint(palette.keepAccent(for: scheme))
                    .foregroundStyle(palette.keepAccent(for: scheme))
                    .disabled(capture.phase != .reviewing || capture.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(RascSurfaceLayout.horizontalInset)
        .background(palette.raisedFill(for: scheme))
        .tint(palette.focus(for: scheme))
        .onAppear { editorFocused = true }
        .onChange(of: capture.phase) { _, phase in if phase == .reviewing { editorFocused = true } }
        .onExitCommand(perform: { capture.closeReview() })
    }
}

struct VoiceCaptureSettings: View {
    @ObservedObject var capture: VoiceCapture
    @Environment(\.rascPalette) private var palette
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Group {
            if VoiceCapture.isSupported {
                Toggle("Enable Voice Capture", isOn: Binding(get: { capture.enabled }, set: { capture.setEnabled($0) }))
                    .disabled(!capture.canChangeEnabled)
                if capture.enabled {
                    setupRows
                    KeyboardShortcuts.Recorder("Start or Finish Recording", name: .voiceCapture)
                        .shortcutValidation { GlobalShortcutPolicy.validation(proposed: $0, excluding: .voiceCapture) }
                        .accessibilityHint("Press once to start and again to finish")
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    if capture.phase == .reviewing {
                        Button("Resume Review", action: { capture.showReview() })
                    } else if capture.phase == .idle, capture.setup == .installed || capture.setup == .preparing {
                        Button("Start Recording") { capture.activate() }
                    }
                }
                detail("Speak a thought, then review it before keeping. Transcription stays on this Mac.")
            } else {
                detail("Voice Capture requires an Apple silicon Mac with macOS 26 or later.")
            }
        }
        .onAppear { if capture.setup == .unchecked { capture.checkSetup() } }
        .onChange(of: capture.enabled) { _, enabled in if enabled, capture.setup == .unchecked { capture.checkSetup() } }
    }

    @ViewBuilder private var setupRows: some View {
        switch capture.setup {
        case .unchecked:
            modelProgress("Checking…")
        case .missing:
            Button("Choose Model Folder…", action: { importModel() })
            detail("Choose the Fluid Speech Pro model folder for this version of Rasc.")
        case .importing:
            modelProgress("Verifying…")
        case .preparing:
            modelProgress("Preparing…")
            detail("The first preparation may take 20 seconds or more.")
        case .installed:
            LabeledContent("Speech Model", value: "Installed")
        case .failed:
            detail("Rasc couldn’t prepare the speech model.")
            Button("Check Model Again") { capture.checkSetup(prepare: true) }
            Button("Choose Model Folder…", action: { importModel() })
        }
    }

    private func modelProgress(_ text: String) -> some View {
        LabeledContent("Speech Model") {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small).accessibilityHidden(true)
                Text(text).foregroundStyle(palette.secondaryText(for: scheme))
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func detail(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(palette.secondaryText(for: scheme))
            .fixedSize(horizontal: false, vertical: true)
    }

    private func importModel() {
        let panel = NSOpenPanel()
        panel.title = "Choose Voice Capture Model"
        panel.prompt = "Use Model"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        let selected: (NSApplication.ModalResponse) -> Void = { response in
            if response == .OK, let folder = panel.url { capture.importModel(from: folder) }
        }
        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window, completionHandler: selected)
        } else {
            panel.begin(completionHandler: selected)
        }
    }
}

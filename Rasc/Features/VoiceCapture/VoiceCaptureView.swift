import AppKit
import KeyboardShortcuts
import SwiftUI

@MainActor
final class VoiceCaptureWindows {
    private unowned let capture: VoiceCapture
    private(set) var status: NSPanel?
    private var previousApp: NSRunningApplication?
    private var screenFrame: CGRect?
    init(capture: VoiceCapture) {
        self.capture = capture
    }

    var hasBlockingSheet: Bool { NSApp.modalWindow != nil || NSApp.keyWindow?.attachedSheet != nil }

    func showStatus() {
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
        if !panel.isVisible {
            previousApp = NSWorkspace.shared.frontmostApplication
            let target = NSApp.isActive ? NSApp.keyWindow?.screen : nil
            screenFrame = (target ?? WindowFramePlacement.targetPresentationScreen(
                excludingProcessID: NSRunningApplication.current.processIdentifier
            ))?.visibleFrame
        }
        let visibleFrames = NSScreen.screens.map(\.visibleFrame)
        if screenFrame == nil || !visibleFrames.contains(where: { $0 == screenFrame }) {
            screenFrame = NSScreen.main?.visibleFrame ?? visibleFrames.first
        }
        if let frame = screenFrame {
            panel.setFrameOrigin(CGPoint(x: frame.midX - panel.frame.width / 2, y: frame.minY + 18))
        }
        panel.orderFrontRegardless()
    }

    func restorePreviousApplicationAfterPermission() {
        if NSApp.isActive, let previousApp, previousApp != .current, !previousApp.isTerminated {
            previousApp.activate()
        }
    }

    func hideStatus() { status?.orderOut(nil) }

    func announce(_ phase: VoiceCapture.Phase) {
        guard let status, status.isVisible else { return }
        let message: String
        switch phase {
        case .listening: message = "Listening"
        case .waitingForModel: message = "Preparing speech"
        case .transcribing: message = "Transcribing"
        case .ready: message = "Thought saved. Open Scratchpad."
        case .issue(let issue): message = issue.message
        default: return
        }
        NSAccessibility.post(element: status, notification: .announcementRequested,
                             userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
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
    private let outline = RoundedRectangle(cornerRadius: 24)

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 26, height: 26)
                .foregroundStyle(palette.secondaryText(for: scheme))
                .background(palette.subtleFill(for: scheme), in: Circle())
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
        .background(palette.raisedFill(for: scheme), in: outline)
        .overlay {
            outline.strokeBorder(palette.border(for: scheme), lineWidth: contrast == .increased ? 2 : 1)
                .allowsHitTesting(false)
        }
        .shadow(color: .black.opacity(scheme == .dark ? 0.28 : 0.14), radius: 8, y: 4)
        .frame(width: 304, height: 70)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Voice Capture")
    }

    @ViewBuilder private var actions: some View {
        switch capture.phase {
        case .ready:
            action("Open", accessibilityLabel: "Open Captured Thought in Scratchpad") { capture.activate() }
            action("Dismiss", icon: "xmark") { capture.cancel() }
        case .listening:
            VoiceLevelMeter(input: capture.inputLevel)
            action("Finish recording", icon: "stop.fill") { capture.finish() }
            action("Cancel recording", icon: "xmark", call: { capture.cancel() })
        case .issue(let issue):
            if issue == .permission {
                action("Settings", accessibilityLabel: "Open Microphone Settings") { capture.openMicrophoneSettings() }
            } else if capture.canRetryAudio {
                action("Retry", accessibilityLabel: "Retry transcription") { capture.recover() }
            } else {
                action("Try again") { capture.recover() }
            }
            action(issue == .persistence ? "Discard capture" : "Dismiss", icon: "xmark") { capture.cancel() }
        case .checking, .starting, .finishing, .waitingForModel, .transcribing:
            action("Cancel recording", icon: "xmark", call: { capture.cancel() })
        default: EmptyView()
        }
    }

    private var title: String {
        switch capture.phase {
        case .checking where capture.awaitingMicrophonePermission: "Allow microphone access"
        case .idle, .checking, .starting: "Getting ready…"
        case .listening: "Listening"
        case .finishing: "Finishing…"
        case .waitingForModel: "Preparing speech…"
        case .transcribing: "Transcribing…"
        case .stopping: "Cancelling…"
        case .ready: "Thought saved"
        case .saving: "Saving thought…"
        case .opening: "Opening Scratchpad…"
        case .issue(.permission): "Microphone access needed"
        case .issue(.microphone): "Microphone unavailable"
        case .issue(.noSpeech): "No speech heard"
        case .issue(.modelUnavailable): "Speech model unavailable"
        case .issue(.modelTimeout): "Speech is taking too long"
        case .issue(.lowDiskSpace): "Free up disk space"
        case .issue(.transcription): "Couldn’t transcribe"
        case .issue(.persistence): "Couldn’t save thought"
        case .issue(.blocked): "Close the open dialog"
        }
    }

    private var icon: String {
        switch capture.phase {
        case .ready: "checkmark"
        case .listening, .finishing: "mic.fill"
        case .waitingForModel, .transcribing, .saving, .opening: "ellipsis"
        case .issue(.noSpeech): "waveform.slash"
        case .issue: "exclamationmark"
        default: "mic"
        }
    }

    private func action(
        _ title: String,
        icon: String? = nil,
        accessibilityLabel: String? = nil,
        call: @escaping () -> Void
    ) -> some View {
        Button(action: call) {
            Group {
                if let icon { Image(systemName: icon).font(.system(size: 11, weight: .semibold)) }
                else { Text(title).font(.caption.weight(.medium)) }
            }
            .padding(.horizontal, icon == nil ? 5 : 0)
            .frame(minWidth: 40, minHeight: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(VoiceStatusButton(fill: palette.subtleFill(for: scheme), reduceMotion: reduceMotion))
        .accessibilityLabel(accessibilityLabel ?? title)
        .help(accessibilityLabel ?? title)
    }
}

private struct VoiceStatusButton: ButtonStyle {
    let fill: Color
    let reduceMotion: Bool
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed || isHovered ? fill : .clear, in: Capsule())
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .onHover { isHovered = $0 }
    }
}

@MainActor
final class VoiceInputLevel: ObservableObject {
    @Published private(set) var rms: Float = 0

    func update(_ level: Float) {
        if rms != level { rms = level }
    }
}

private struct VoiceLevelMeter: View {
    @ObservedObject var input: VoiceInputLevel

    var body: some View {
        let level = min(1, max(0, (20 * log10(max(input.rms, 0.00001)) + 58) / 42))
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
                    KeyboardShortcuts.Recorder("Start or Finish Recording", name: .voiceCapture) { _ in
                        capture.refreshShortcut()
                    }
                        .shortcutValidation { GlobalShortcutPolicy.validation(proposed: $0, excluding: .voiceCapture) }
                        .accessibilityHint("Press once to start and again to finish")
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    if KeyboardShortcuts.getShortcut(for: .voiceCapture) != nil, !capture.shortcutIsActive {
                        detail("This shortcut is unavailable. Choose a different shortcut or start recording here.")
                    }
                    recordingActions
                }
                detail("Speak a thought and continue in Scratchpad. Transcription stays on this Mac.")
            } else {
                detail("Voice Capture requires an Apple silicon Mac with macOS 26 or later.")
            }
        }
        .onAppear {
            capture.refreshShortcut()
            if capture.setup == .unchecked { capture.checkSetup() }
        }
        .onChange(of: capture.enabled) { _, enabled in if enabled, capture.setup == .unchecked { capture.checkSetup() } }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            capture.refreshShortcut()
        }
    }

    @ViewBuilder private var recordingActions: some View {
        switch capture.phase {
        case .idle:
            if capture.setup == .installed || capture.setup == .preparing {
                captureButton("Start Recording")
            }
        case .listening:
            captureButton("Finish Recording")
            Button("Cancel Recording", role: .cancel) { capture.cancel() }
        case .ready:
            captureButton("Open Scratchpad")
        case .saving, .opening:
            detail("Opening your thought in Scratchpad…")
        case .checking, .starting:
            detail(capture.awaitingMicrophonePermission
                ? "Allow microphone access in the macOS prompt."
                : "Getting the microphone ready…")
            Button("Cancel Recording") { capture.cancel() }
        case .finishing, .waitingForModel, .transcribing:
            detail("Preparing your transcript…")
            Button("Cancel Recording") { capture.cancel() }
        case .issue(let issue):
            detail(issue.message)
            Button(capture.needsMicrophoneAccess ? "Open Microphone Settings…" : capture.canRetryAudio ? "Retry Transcription" : "Try Again") {
                capture.recover()
            }
        default:
            EmptyView()
        }
    }

    @ViewBuilder private func captureButton(_ title: String) -> some View {
        if capture.shortcutIsActive {
            Button(title) { capture.activate(fromShortcut: true) }
                .globalKeyboardShortcut(.voiceCapture)
        } else {
            Button(title) { capture.activate() }
        }
    }

    @ViewBuilder private var setupRows: some View {
        switch capture.setup {
        case .unchecked:
            modelProgress("Checking…")
        case .missing:
            Button("Download Speech Model (\(formattedSize(capture.modelDownloadSizeBytes)))") {
                capture.downloadModel()
            }
            detail("Downloads once for offline, on-device transcription. Nothing leaves this Mac.")
            Button("Choose Model Folder…", action: { importModel() })
        case .downloading(let downloaded, let total):
            VStack(alignment: .leading, spacing: 6) {
                LabeledContent("Speech Model") {
                    Text("\(formattedSize(downloaded)) of \(formattedSize(total))")
                        .foregroundStyle(palette.secondaryText(for: scheme))
                        .monospacedDigit()
                }
                ProgressView(value: Double(min(downloaded, max(total, 1))), total: Double(max(total, 1)))
                    .accessibilityLabel("Downloading speech model")
                    .accessibilityValue("\(formattedSize(downloaded)) of \(formattedSize(total))")
            }
            Button("Cancel Download") { capture.cancelModelDownload() }
        case .importing:
            modelProgress("Verifying…")
        case .preparing:
            modelProgress("Preparing…")
            detail("The first preparation may take 20 seconds or more.")
        case .installed:
            LabeledContent("Speech Model", value: capture.canRemoveInstalledModel
                ? "Installed (\(formattedSize(capture.modelDownloadSizeBytes)))"
                : "Installed")
            if capture.canRemoveInstalledModel {
                Button("Remove Speech Model", role: .destructive) {
                    capture.removeInstalledModel()
                }
                .disabled(capture.phase != .idle)
            }
        case .downloadFailed:
            detail("Rasc couldn’t finish downloading the speech model. Check your connection and try again.")
            Button("Retry Download") { capture.downloadModel() }
            Button("Choose Model Folder…", action: { importModel() })
        case .failed:
            detail("Rasc couldn’t prepare the speech model.")
            Button("Check Model Again") { capture.checkSetup(prepare: true) }
            Button("Choose Model Folder…", action: { importModel() })
        case .lowDiskSpace:
            detail("Free up disk space to install and prepare the speech model.")
            Button("Check Model Again") { capture.checkSetup(prepare: true) }
        }
    }

    private func formattedSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
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

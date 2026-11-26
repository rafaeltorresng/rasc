import AppKit
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
            let rect = CGRect(origin: .zero, size: CGSize(width: 344, height: 74))
            panel = VoiceStatusPanel(
                contentRect: rect,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: true
            )
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

    func hideStatus() {
        status?.orderOut(nil)
        previousApp = nil
    }

    func announce(_ phase: VoiceCapture.Phase) {
        guard let status, status.isVisible else { return }
        let message: String
        switch phase {
        case .listening:
            message = capture.activeIntent == .dictate ? "Dictating" : "Listening"
        case .waitingForModel:
            message = "Preparing speech"
        case .transcribing:
            message = "Transcribing"
        case .ready:
            message = "Thought saved. Open Scratchpad."
        case .copied:
            message = "Transcript copied."
        case .inserted:
            message = "Inserted at cursor."
        case .insertedAndCopied:
            message = "Inserted at cursor and copied."
        case .copiedFallback:
            message = "Insertion unavailable. Transcript copied. Paste with Command V."
        case .issue(let issue):
            message = issue.message
        default:
            return
        }
        NSAccessibility.post(
            element: status,
            notification: .announcementRequested,
            userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.medium.rawValue]
        )
    }

    func announceCancelConfirmation(seconds: Int) {
        guard let status, status.isVisible else { return }
        NSAccessibility.post(
            element: status,
            notification: .announcementRequested,
            userInfo: [
                .announcement: "Discard \(seconds) second recording? Choose Keep or Discard.",
                .priority: NSAccessibilityPriorityLevel.high.rawValue
            ]
        )
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
    private let outline = Capsule(style: .continuous)

    private var showsConfirmation: Bool {
        guard capture.isConfirmingCancel else { return false }
        switch capture.phase {
        case .listening, .finishing, .waitingForModel, .transcribing:
            return true
        default:
            return false
        }
    }

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
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.9)

            Spacer(minLength: 4)

            actions
        }
        .padding(.leading, 10)
        .padding(.trailing, 8)
        .frame(width: 308, height: 48)
        .foregroundStyle(palette.noteText(for: scheme))
        .background {
            outline
                .fill(palette.raisedFill(for: scheme))
                .shadow(color: .black.opacity(scheme == .dark ? 0.28 : 0.14), radius: 8, y: 4)
        }
        .overlay {
            outline.strokeBorder(
                showsConfirmation ? palette.focus(for: scheme) : palette.border(for: scheme),
                lineWidth: contrast == .increased ? 2 : 1
            )
            .allowsHitTesting(false)
        }
        .frame(width: 344, height: 74)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(capture.activeIntent == .dictate ? "Dictation" : "Voice Capture")
    }

    @ViewBuilder private var actions: some View {
        if showsConfirmation {
            action("Keep", accessibilityLabel: "Keep recording") {
                capture.keepRecording()
            }
            action(
                "Discard",
                accessibilityLabel: "Discard recording",
                foreground: palette.destructiveText(for: scheme)
            ) {
                capture.confirmDiscard()
            }
        } else {
            switch capture.phase {
            case .ready:
                action("Open", accessibilityLabel: "Open Captured Thought in Scratchpad") {
                    capture.activate()
                }
                action("Dismiss", icon: "xmark") { capture.cancel() }
            case .listening:
                Text(formattedDuration(capture.recordingElapsedSeconds))
                    .font(.caption2.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(palette.secondaryText(for: scheme))
                    .accessibilityLabel("Recording duration \(capture.recordingElapsedSeconds) seconds")
                VoiceLevelMeter(input: capture.inputLevel)
                action("Finish recording", icon: "stop.fill") { capture.finish() }
                action("Cancel recording", icon: "xmark") { capture.requestCancel(fromEscape: false) }
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
                action("Cancel recording", icon: "xmark") { capture.requestCancel(fromEscape: false) }
            case .copied, .inserted, .insertedAndCopied, .copiedFallback:
                action("Dismiss", icon: "xmark") { capture.cancel() }
            default:
                EmptyView()
            }
        }
    }

    private var title: String {
        if showsConfirmation {
            return "Discard \(formattedDuration(capture.confirmCancelDurationSeconds))?"
        }
        switch capture.phase {
        case .checking where capture.awaitingMicrophonePermission:
            return "Allow microphone access"
        case .idle, .checking, .starting:
            return "Getting ready…"
        case .listening:
            return capture.activeIntent == .dictate ? "Dictating" : "Listening"
        case .finishing:
            return "Finishing…"
        case .waitingForModel:
            return "Preparing speech…"
        case .transcribing:
            return "Transcribing…"
        case .stopping:
            return "Cancelling…"
        case .ready:
            return "Thought saved"
        case .copied:
            return "Copied"
        case .inserted:
            return "Inserted"
        case .insertedAndCopied:
            return "Inserted & copied"
        case .copiedFallback:
            return "Copied — press ⌘V"
        case .saving:
            return "Saving thought…"
        case .opening:
            return "Opening Scratchpad…"
        case .issue(.permission):
            return "Microphone access needed"
        case .issue(.microphone):
            return "Microphone unavailable"
        case .issue(.noSpeech):
            return "No speech heard"
        case .issue(.modelUnavailable):
            return "Speech model unavailable"
        case .issue(.modelTimeout):
            return "Speech is taking too long"
        case .issue(.lowDiskSpace):
            return "Free up disk space"
        case .issue(.transcription):
            return "Couldn’t transcribe"
        case .issue(.persistence):
            return "Couldn’t save thought"
        case .issue(.blocked):
            return "Close the open dialog"
        }
    }

    private var icon: String {
        if showsConfirmation {
            return "exclamationmark"
        }
        switch capture.phase {
        case .ready, .copied, .inserted, .insertedAndCopied:
            return "checkmark"
        case .copiedFallback:
            return "doc.on.clipboard"
        case .listening, .finishing:
            return capture.activeIntent == .dictate ? "waveform" : "mic.fill"
        case .waitingForModel, .transcribing, .saving, .opening:
            return "ellipsis"
        case .issue(.noSpeech):
            return "waveform.slash"
        case .issue:
            return "exclamationmark"
        default:
            return "mic"
        }
    }

    private func formattedDuration(_ seconds: Int) -> String {
        let clamped = max(0, seconds)
        return "\(clamped / 60):\(String(format: "%02d", clamped % 60))"
    }

    private func action(
        _ title: String,
        icon: String? = nil,
        accessibilityLabel: String? = nil,
        foreground: Color? = nil,
        call: @escaping () -> Void
    ) -> some View {
        Button(action: call) {
            Group {
                if let icon {
                    Image(systemName: icon).font(.system(size: 11, weight: .semibold))
                } else {
                    Text(title).font(.caption.weight(.medium))
                }
            }
            .foregroundStyle(foreground ?? palette.noteText(for: scheme))
            .padding(.horizontal, icon == nil ? 8 : 0)
            .frame(minWidth: icon == nil ? 44 : 36, minHeight: 36)
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
                Capsule()
                    .frame(width: 2, height: 3 + amount * CGFloat(3 + index * 2))
                    .opacity(0.34 + amount * 0.66)
            }
        }
        .frame(width: 20, height: 16)
        .accessibilityHidden(true)
    }
}

struct VoiceCaptureSettings: View {
    @ObservedObject var capture: VoiceCapture
    @ObservedObject private var shortcutStore = GlobalShortcutStore.shared
    @Environment(\.rascPalette) private var palette
    @Environment(\.colorScheme) private var scheme
    @State private var modelDisclosureExpanded = false

    var body: some View {
        Group {
            if VoiceCapture.isSupported {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle("Enable Voice", isOn: Binding(
                            get: { capture.enabled },
                            set: { capture.setEnabled($0) }
                        ))
                        .disabled(!capture.canChangeEnabled)

                        detail("On-device speech recognition. Audio stays in memory and is never sent off this Mac.")
                    }
                    .padding(.vertical, 2)
                }

                if capture.enabled {
                    Section("Voice to Scratchpad") {
                        UnifiedShortcutRow(
                            action: .voiceScratchpad,
                            title: "Shortcut",
                            subtitle: "Record directly into a new thought in Scratchpad.",
                            showsRestoreDefault: false
                        )
                    }

                    Section("Dictate") {
                        UnifiedShortcutRow(
                            action: .voiceDictate,
                            title: "Shortcut",
                            subtitle: "Dictate where you’re typing without opening Rasc.",
                            showsRestoreDefault: false
                        )

                        VStack(alignment: .leading, spacing: 4) {
                            Picker("After dictating", selection: Binding(
                                get: { capture.dictationDelivery },
                                set: { capture.setDictationDelivery($0) }
                            )) {
                                ForEach(VoiceDictationDelivery.allCases) { delivery in
                                    Text(delivery.title).tag(delivery)
                                }
                            }
                            .pickerStyle(.menu)
                            .accessibilityLabel("After dictating")
                            .accessibilityHint(capture.dictationDelivery.detail)

                            detail(capture.dictationDelivery.detail)
                        }
                        .padding(.vertical, 2)

                        if capture.dictationDelivery == .insertAtCursor {
                            VStack(alignment: .leading, spacing: 4) {
                                Toggle("Also keep on clipboard", isOn: Binding(
                                    get: { capture.dictationAlsoCopiesToClipboard },
                                    set: { capture.setDictationAlsoCopiesToClipboard($0) }
                                ))
                                detail("Keep the dictated text on the clipboard after inserting so you can paste again with ⌘V.")
                            }
                            .padding(.vertical, 2)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Toggle("Save a copy in Rasc", isOn: Binding(
                                get: { capture.standaloneKeepsHistory },
                                set: { capture.setStandaloneKeepsHistory($0) }
                            ))
                            detail("Keep dictated transcripts as unfinished thoughts inside Rasc.")
                        }
                        .padding(.vertical, 2)
                    }

                    if needsContextualAccessibilityPrompt {
                        Section("Permissions") {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Accessibility access required")
                                    .font(.callout.weight(.medium))
                                detail(accessibilityPromptReason)
                                HStack(spacing: 8) {
                                    Button("Allow Rasc…") {
                                        capture.requestAccessibilityForInsertion()
                                    }
                                    Button("Open System Settings…") {
                                        capture.openAccessibilitySettings()
                                    }
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }

                    if showsStatusSection {
                        Section("Session") {
                            recordingActions
                        }
                    }

                    Section("Speech Model") {
                        setupRows
                    }
                }
            } else {
                Section {
                    detail("Voice requires an Apple silicon Mac with macOS 26 or later.")
                }
            }
        }
        .onAppear {
            capture.refreshShortcut()
            if capture.setup == .unchecked { capture.checkSetup() }
        }
        .onChange(of: capture.enabled) { _, enabled in
            if enabled, capture.setup == .unchecked { capture.checkSetup() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            capture.refreshShortcut()
        }
    }

    private var needsContextualAccessibilityPrompt: Bool {
        guard !capture.hasAccessibilityAccess else { return false }
        let dictateHasShortcut = shortcutStore.trigger(for: .voiceDictate) != nil
        let usesInsert = capture.dictationDelivery == .insertAtCursor && dictateHasShortcut
        let usesModifier =
            shortcutStore.trigger(for: .voiceScratchpad)?.needsAccessibilityPermission == true
            || shortcutStore.trigger(for: .voiceDictate)?.needsAccessibilityPermission == true
        return usesInsert || usesModifier
    }

    private var accessibilityPromptReason: String {
        let usesInsert = capture.dictationDelivery == .insertAtCursor
            && shortcutStore.trigger(for: .voiceDictate) != nil
        let usesModifier =
            shortcutStore.trigger(for: .voiceScratchpad)?.needsAccessibilityPermission == true
            || shortcutStore.trigger(for: .voiceDictate)?.needsAccessibilityPermission == true

        switch (usesInsert, usesModifier) {
        case (true, true):
            return "Needed to insert text at your cursor and detect single-modifier shortcuts outside Rasc."
        case (true, false):
            return "Needed to insert dictated text directly into other apps. Without it, Rasc copies to the clipboard instead."
        case (false, true):
            return "Single-modifier triggers work inside Rasc now. Allow Accessibility to use them globally across macOS."
        case (false, false):
            return ""
        }
    }

    private var showsStatusSection: Bool {
        capture.phase != .idle
    }

    @ViewBuilder private var recordingActions: some View {
        switch capture.phase {
        case .listening:
            HStack {
                detail(capture.activeIntent == .dictate ? "Dictating…" : "Listening…")
                Spacer()
                Button("Finish") { capture.finish() }
                Button("Cancel", role: .cancel) { capture.requestCancel() }
            }
        case .ready:
            Button("Open Scratchpad") { capture.activate() }
        case .copied:
            detail("Copied to clipboard.")
        case .inserted:
            detail("Inserted at cursor.")
        case .insertedAndCopied:
            detail("Inserted at cursor and copied to clipboard.")
        case .copiedFallback:
            detail("Insertion unavailable; copied to clipboard. Press Command V.")
        case .saving, .opening:
            detail("Opening your thought in Scratchpad…")
        case .checking, .starting:
            detail(capture.awaitingMicrophonePermission
                ? "Allow microphone access in the macOS prompt."
                : "Getting the microphone ready…")
            Button("Cancel") { capture.requestCancel() }
        case .finishing, .waitingForModel, .transcribing:
            detail("Preparing your transcript…")
            Button("Cancel") { capture.requestCancel() }
        case .issue(let issue):
            detail(issue.message)
            Button(capture.needsMicrophoneAccess ? "Open Microphone Settings…" : capture.canRetryAudio ? "Retry Transcription" : "Try Again") {
                capture.recover()
            }
        default:
            EmptyView()
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
            Button("Choose Model Folder…") { importModel() }
        case .downloading(let downloaded, let total):
            VStack(alignment: .leading, spacing: 6) {
                LabeledContent("Downloading") {
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
            DisclosureGroup(isExpanded: $modelDisclosureExpanded) {
                if capture.canRemoveInstalledModel {
                    LabeledContent("Disk Space", value: formattedSize(capture.modelDownloadSizeBytes))
                    Button("Remove Speech Model", role: .destructive) {
                        capture.removeInstalledModel()
                    }
                    .disabled(capture.phase != .idle)
                } else {
                    detail("Managed locally inside Application Support.")
                }
            } label: {
                LabeledContent("On-device Model") {
                    Text(capture.canRemoveInstalledModel
                        ? "Ready (\(formattedSize(capture.modelDownloadSizeBytes)))"
                        : "Ready")
                        .foregroundStyle(palette.secondaryText(for: scheme))
                }
            }
        case .downloadFailed:
            detail("Rasc couldn’t finish downloading the speech model. Check your connection and try again.")
            Button("Retry Download") { capture.downloadModel() }
            Button("Choose Model Folder…") { importModel() }
        case .failed:
            detail("Rasc couldn’t prepare the speech model.")
            Button("Check Model Again") { capture.checkSetup(prepare: true) }
            Button("Choose Model Folder…") { importModel() }
        case .lowDiskSpace:
            detail("Free up disk space to install and prepare the speech model.")
            Button("Check Model Again") { capture.checkSetup(prepare: true) }
        }
    }

    private func formattedSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func modelProgress(_ text: String) -> some View {
        LabeledContent("Status") {
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

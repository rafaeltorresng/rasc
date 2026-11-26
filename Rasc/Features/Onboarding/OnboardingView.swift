import AppKit
import SwiftUI

private enum OnboardingLayout {
    static let contentMaxWidth: CGFloat = 540
    static let welcomeMaxWidth: CGFloat = 460
    static let completionMaxWidth: CGFloat = 500
    static let ctaMinWidth: CGFloat = 168
    static let commandTitleWidth: CGFloat = 122
}

struct OnboardingView: View {
    @Bindable var coordinator: OnboardingCoordinator

    @ObservedObject private var voiceCapture: VoiceCapture
    @ObservedObject private var globalShortcuts: GlobalShortcutStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.rascPalette) private var palette
    @Environment(\.colorScheme) private var colorScheme
    private enum FocusTarget: Hashable {
        case welcomePrimary
        case shortcutContinue
        case resumeOpen
        case voiceContinue
        case completionFinish
    }
    @FocusState private var focusedTarget: FocusTarget?
    @State private var dictationPracticeDraft = ""
    @State private var shortcutRevision = 0

    init(coordinator: OnboardingCoordinator) {
        self.coordinator = coordinator
        _voiceCapture = ObservedObject(wrappedValue: coordinator.voiceCaptureSession)
        _globalShortcuts = ObservedObject(wrappedValue: coordinator.shortcutStoreInstance)
    }

    var body: some View {
        let _ = shortcutRevision
        let _ = voiceCapture.enabled
        let _ = voiceCapture.setup
        let _ = globalShortcuts.trigger(for: .toggleScratchpad)

        ZStack {
            OnboardingBackground()

            VStack(spacing: 0) {
                topChrome
                    .padding(.horizontal, 20)
                    .padding(.top, 14)

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        stepBody
                            .frame(maxWidth: OnboardingLayout.contentMaxWidth)
                            .padding(.horizontal, 32)
                            .padding(.vertical, 26)
                    }
                    .frame(maxWidth: .infinity, minHeight: 440)
                }
            }
            .transition(RascMotion.stageTransition(reduceMotion: reduceMotion))
            .id(stageTransitionKey)
        }
        .frame(
            minWidth: 520,
            idealWidth: RascWindowMetrics.onboarding.width,
            maxWidth: .infinity,
            minHeight: 460,
            idealHeight: RascWindowMetrics.onboarding.height,
            maxHeight: .infinity
        )
        .tint(Color.primary)
        .animation(RascMotion.surface(reduceMotion: reduceMotion), value: stageTransitionKey)
        .onAppear {
            focusCurrentStep()
            coordinator.refreshEnvironmentSync()
        }
        .onChange(of: stageTransitionKey) {
            focusCurrentStep()
            announceCurrentStep()
        }
        .onGlobalShortcutChange {
            shortcutRevision += 1
            coordinator.refreshEnvironmentSync()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            coordinator.refreshEnvironmentSync()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            coordinator.refreshEnvironmentSync()
        }
    }

    private var stageTransitionKey: String {
        "\(coordinator.presentedStep.rawValue)-\(coordinator.captureSubstep.rawValue)"
    }

    @ViewBuilder
    private var topChrome: some View {
        HStack {
            Spacer(minLength: 48)

            if let progress = onboardingProgress {
                onboardingProgressIndicator(progress)
            }

            Spacer(minLength: 0)

            Group {
                if showsOnboardingSkip {
                    Button("Skip") {
                        coordinator.skipSetup()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(secondaryText)
                    .accessibilityLabel("Skip setup")
                    .help("Skip setup and open normal Rasc behavior")
                } else {
                    Color.clear
                        .frame(width: 36, height: 16)
                }
            }
            .frame(minWidth: 48, alignment: .trailing)
        }
    }

    @ViewBuilder
    private var stepBody: some View {
        switch coordinator.presentedStep {
        case .welcome:
            welcomeContent
        case .shortcut:
            shortcutContent
        case .capturePractice, .refinePractice:
            if coordinator.captureSubstep == .waitingToResume {
                waitingToResumeContent
            } else if coordinator.captureSubstep == .waitingForShortcut {
                waitingForShortcutContent
            } else {
                Color.clear
            }
        case .voiceSetup:
            voiceSetupContent
        case .completion:
            completionContent
        case .finished:
            Color.clear
        }
    }

    private var showsOnboardingSkip: Bool {
        switch coordinator.presentedStep {
        case .welcome, .shortcut, .capturePractice, .refinePractice, .voiceSetup:
            true
        case .completion, .finished:
            false
        }
    }

    private var onboardingProgress: (current: Int, total: Int)? {
        let total = coordinator.progressStepCount
        switch coordinator.presentedStep {
        case .welcome, .finished:
            return nil
        case .shortcut:
            return (1, total)
        case .capturePractice, .refinePractice:
            return (2, total)
        case .voiceSetup:
            return (3, total)
        case .completion:
            return (total, total)
        }
    }

    private var secondaryText: Color {
        palette.secondaryText(for: colorScheme)
    }

    private var metadataText: Color {
        palette.metadataText(for: colorScheme)
    }

    // MARK: - Welcome

    private var welcomeContent: some View {
        VStack(spacing: 22) {
            VStack(spacing: 12) {
                RascLogo(size: 52)

                Text("Rasc")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.noteText(for: colorScheme))

                VStack(spacing: 6) {
                    Text("A scratchpad for unfinished thoughts.")
                        .font(.system(size: 24, weight: .medium))
                        .tracking(-0.35)
                        .foregroundStyle(palette.noteText(for: colorScheme))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Capture fast, return later, or speak anywhere on your Mac.")
                        .font(.system(size: 13.5))
                        .foregroundStyle(secondaryText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if coordinator.environment.isVoiceSupported {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(OnboardingFocus.allCases) { focus in
                        focusChoiceRow(focus)
                    }
                }
                .frame(maxWidth: OnboardingLayout.welcomeMaxWidth)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Choose how you plan to use Rasc")
            }

            VStack(spacing: 10) {
                Button("Get started") {
                    coordinator.continueFromWelcome()
                }
                .buttonStyle(OnboardingProminentButtonStyle(fullWidth: false))
                .frame(minWidth: OnboardingLayout.ctaMinWidth)
                .keyboardShortcut(.defaultAction)
                .focused($focusedTarget, equals: .welcomePrimary)
                .accessibilityLabel("Get started")

                HStack(spacing: 8) {
                    Text("No account")
                    Text("·")
                    Text("Local SQLite")
                    Text("·")
                    Text("Works without AI")
                }
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(metadataText)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("No account required. Local SQLite. Works without AI.")
            }
        }
        .frame(maxWidth: OnboardingLayout.welcomeMaxWidth)
        .accessibilityElement(children: .contain)
    }

    private func focusChoiceRow(_ focus: OnboardingFocus) -> some View {
        let isSelected = (coordinator.selectedFocus == focus)
        return Button {
            coordinator.selectFocus(focus)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: focus == .scratchpadAndVoice ? "waveform.and.mic" : "square.and.pencil")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isSelected ? palette.noteText(for: colorScheme) : secondaryText)
                    .frame(width: 24, height: 24)
                    .padding(.top, 1)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(focus.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.noteText(for: colorScheme))
                    Text(focus.subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 8)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15))
                    .foregroundStyle(isSelected ? palette.noteText(for: colorScheme) : metadataText)
                    .padding(.top, 2)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? palette.selectionFill(for: colorScheme) : palette.raisedFill(for: colorScheme))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(
                                isSelected ? palette.focus(for: colorScheme) : palette.border(for: colorScheme),
                                lineWidth: isSelected ? 1.5 : 1
                            )
                    }
            }
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(focus.title)
        .accessibilityValue(focus.subtitle)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    // MARK: - Shortcut

    private var shortcutContent: some View {
        VStack(spacing: 22) {
            VStack(spacing: 8) {
                Text("One shortcut away.")
                    .font(.system(size: 24, weight: .medium))
                    .tracking(-0.35)
                    .foregroundStyle(palette.noteText(for: colorScheme))

                Text("Summon your scratchpad without switching windows.")
                    .font(.body)
                    .foregroundStyle(secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 14) {
                Text("OPEN SCRATCHPAD")
                    .font(.caption2.weight(.medium))
                    .tracking(0.8)
                    .foregroundStyle(metadataText)

                UnifiedShortcutRecorder(
                    action: .toggleScratchpad,
                    store: globalShortcuts,
                    prominent: true,
                    showsValidationError: true,
                    showsClearButton: false
                )

                Text("Click to change. Supports chords (⌥\\) or a single modifier tap (⌥).")
                    .font(.caption)
                    .foregroundStyle(secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                if coordinator.needsAccessibilityForScratchpadShortcut {
                    contextualPermissionRow(
                        title: "Single-modifier triggers need Accessibility access outside Rasc.",
                        buttonTitle: "Allow Accessibility…",
                        secondaryTitle: "Settings…",
                        action: { coordinator.requestAccessibilityPermission() },
                        secondaryAction: { coordinator.openAccessibilitySettings() }
                    )
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .frame(maxWidth: 420)
            .onboardingFeatureSurface()

            VStack(spacing: 10) {
                Button("Continue") {
                    coordinator.continueFromShortcut()
                }
                .buttonStyle(OnboardingProminentButtonStyle(fullWidth: false))
                .frame(minWidth: OnboardingLayout.ctaMinWidth)
                .disabled(!GlobalShortcutFormatting.hasValidToggleShortcut())
                .keyboardShortcut(.defaultAction)
                .focused($focusedTarget, equals: .shortcutContinue)
                .accessibilityLabel("Continue")

                Text("You can change all shortcuts anytime in Settings.")
                    .font(.caption)
                    .foregroundStyle(secondaryText)
            }
        }
        .frame(maxWidth: 440)
    }

    // MARK: - Capture & Resume Practice

    private var waitingForShortcutContent: some View {
        let shortcutLabel = GlobalShortcutFormatting.currentToggleShortcutDisplay()
        return VStack(spacing: 22) {
            VStack(spacing: 8) {
                Text("Try opening Rasc.")
                    .font(.system(size: 24, weight: .medium))
                    .tracking(-0.35)
                    .foregroundStyle(palette.noteText(for: colorScheme))

                Text("Press \(shortcutLabel), type a quick fragment, then press Esc to park it.")
                    .font(.body)
                    .foregroundStyle(secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ShortcutKeycapView(
                label: shortcutLabel,
                style: .prominent,
                isPressed: coordinator.shortcutKeycapPressed
            )
            .padding(.horizontal, 28)
            .padding(.vertical, 22)
            .onboardingFeatureSurface()

            Button("Open Scratchpad here") {
                Task { await coordinator.openScratchpadForPracticeDirectly() }
            }
            .buttonStyle(.borderless)
            .font(.caption.weight(.medium))
            .foregroundStyle(secondaryText)
            .accessibilityLabel("Open Scratchpad without shortcut")
        }
        .frame(maxWidth: 420)
        .opacity(coordinator.isYieldingForShortcut ? 0.85 : 1)
        .scaleEffect(coordinator.isYieldingForShortcut && !reduceMotion ? 0.99 : 1)
        .animation(RascMotion.surface(reduceMotion: reduceMotion), value: coordinator.isYieldingForShortcut)
        .accessibilityElement(children: .contain)
    }

    private var waitingToResumeContent: some View {
        let shortcutLabel = GlobalShortcutFormatting.currentToggleShortcutDisplay()
        return VStack(spacing: 20) {
            VStack(spacing: 8) {
                Text("Parked — and still saved.")
                    .font(.system(size: 24, weight: .medium))
                    .tracking(-0.35)
                    .foregroundStyle(palette.noteText(for: colorScheme))

                Text("Your thought didn’t vanish when you closed it. Open Rasc once more to keep working or mark it Kept.")
                    .font(.body)
                    .foregroundStyle(secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ShortcutKeycapView(
                label: shortcutLabel,
                style: .prominent,
                isPressed: coordinator.shortcutKeycapPressed
            )
            .padding(.horizontal, 28)
            .padding(.vertical, 18)
            .onboardingFeatureSurface()

            VStack(spacing: 8) {
                Button("Open again") {
                    Task { await coordinator.openScratchpadForPracticeDirectly() }
                }
                .buttonStyle(OnboardingProminentButtonStyle(fullWidth: false))
                .frame(minWidth: OnboardingLayout.ctaMinWidth)
                .keyboardShortcut(.defaultAction)
                .focused($focusedTarget, equals: .resumeOpen)

                Button("Skip resume step") {
                    coordinator.continueFromResumeCard()
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .foregroundStyle(secondaryText)
            }
        }
        .frame(maxWidth: 440)
        .accessibilityElement(children: .contain)
    }

    // MARK: - Voice & Dictate

    private var voiceSetupContent: some View {
        VStack(spacing: 16) {
            VStack(spacing: 6) {
                Text("Capture or dictate by voice.")
                    .font(.system(size: 23, weight: .medium))
                    .tracking(-0.35)
                    .foregroundStyle(palette.noteText(for: colorScheme))

                Text("Same local model, two distinct workflows. Audio stays in memory on this Mac.")
                    .font(.callout)
                    .foregroundStyle(secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 12) {
                voiceActivationHeader

                Divider().overlay(palette.border(for: colorScheme).opacity(0.45))

                UnifiedShortcutRow(
                    action: .voiceScratchpad,
                    store: globalShortcuts,
                    title: "Voice to Scratchpad",
                    subtitle: "Speaks a thought and opens it inside Rasc.",
                    showsRestoreDefault: false
                )

                UnifiedShortcutRow(
                    action: .voiceDictate,
                    store: globalShortcuts,
                    title: "Dictate",
                    subtitle: "Types directly where your cursor is in any app.",
                    showsRestoreDefault: false
                )

                Text("Defaults for Dictate: inserts at your cursor, keeps a copy on the clipboard, and saves a local copy in Rasc. Change anytime in Settings → Voice.")
                    .font(.caption)
                    .foregroundStyle(metadataText)
                    .fixedSize(horizontal: false, vertical: true)

                if voiceCapture.enabled && !coordinator.environment.isMicrophoneAuthorized {
                    if coordinator.environment.isMicrophoneDenied {
                        contextualPermissionRow(
                            title: "Microphone access is turned off in System Settings. Allow Rasc under Privacy & Security → Microphone.",
                            buttonTitle: "Open Microphone Settings…",
                            action: { coordinator.openMicrophoneSettings() }
                        )
                    } else {
                        contextualPermissionRow(
                            title: "Microphone access is needed when you start recording.",
                            buttonTitle: coordinator.isRequestingMicrophone ? "Waiting…" : "Allow Microphone…",
                            secondaryTitle: "Settings…",
                            action: {
                                Task { await coordinator.requestMicrophonePermission() }
                            },
                            secondaryAction: { coordinator.openMicrophoneSettings() }
                        )
                    }
                }

                if coordinator.needsAccessibilityForVoiceSetup {
                    contextualPermissionRow(
                        title: "Allow Accessibility to type directly at your cursor or use single-modifier triggers.",
                        buttonTitle: "Allow Accessibility…",
                        secondaryTitle: "Settings…",
                        action: { coordinator.requestAccessibilityPermission() },
                        secondaryAction: { coordinator.openAccessibilitySettings() }
                    )
                }

                if voiceCapture.enabled
                    && voiceCapture.setup == .installed
                    && coordinator.environment.isMicrophoneAuthorized
                    && globalShortcuts.trigger(for: .voiceDictate) != nil {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Try Dictate here")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(secondaryText)
                        TextField("Focus this field and press \(globalShortcuts.displayString(for: .voiceDictate))…", text: $dictationPracticeDraft)
                            .textFieldStyle(.roundedBorder)
                            .font(.callout)
                    }
                    .padding(.top, 2)
                }
            }
            .padding(16)
            .frame(maxWidth: 480)
            .onboardingFeatureSurface()

            HStack(spacing: 12) {
                Button("Continue") {
                    coordinator.continueFromVoiceSetup()
                }
                .buttonStyle(OnboardingProminentButtonStyle(fullWidth: false))
                .frame(minWidth: 148)
                .keyboardShortcut(.defaultAction)
                .focused($focusedTarget, equals: .voiceContinue)

                Button("Set up later") {
                    coordinator.skipVoiceSetup()
                }
                .buttonStyle(.borderless)
                .font(.callout)
                .foregroundStyle(secondaryText)
            }
        }
        .frame(maxWidth: 500)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var voiceActivationHeader: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("On-device Voice")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(palette.noteText(for: colorScheme))
                Text(voiceModelStatusSubtitle)
                    .font(.caption)
                    .foregroundStyle(secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            switch voiceCapture.setup {
            case .downloading(let downloaded, let total):
                VStack(alignment: .trailing, spacing: 3) {
                    Text("\(formattedSize(downloaded)) / \(formattedSize(total))")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(secondaryText)
                    ProgressView(value: Double(min(downloaded, max(total, 1))), total: Double(max(total, 1)))
                        .frame(width: 96)
                }
            case .preparing, .importing:
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Preparing…")
                        .font(.caption)
                        .foregroundStyle(secondaryText)
                }
            case .installed:
                Text(voiceCapture.enabled ? "Ready" : "Installed")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(secondaryText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(palette.subtleFill(for: colorScheme), in: Capsule())
            case .missing, .downloadFailed, .unchecked, .failed, .lowDiskSpace:
                if !voiceCapture.enabled {
                    Button("Enable Voice") {
                        coordinator.enableVoiceSetup()
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button("Download (\(formattedSize(coordinator.voiceDownloadSizeBytes)))") {
                        coordinator.downloadVoiceModel()
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private var voiceModelStatusSubtitle: String {
        switch voiceCapture.setup {
        case .installed:
            return voiceCapture.enabled
                ? "Speech model ready on this Mac."
                : "Speech model installed."
        case .downloading:
            return "Downloading in the background — you can continue setup right now."
        case .preparing, .importing:
            return "Preparing the on-device speech model — you don’t have to wait here."
        case .missing, .unchecked:
            return "One-time \(formattedSize(coordinator.voiceDownloadSizeBytes)) download. Never blocks typing capture."
        case .downloadFailed, .failed, .lowDiskSpace:
            return "You can finish onboarding now and set up the model in Settings → Voice."
        }
    }

    private func contextualPermissionRow(
        title: String,
        buttonTitle: String,
        secondaryTitle: String? = nil,
        action: @escaping () -> Void,
        secondaryAction: (() -> Void)? = nil
    ) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Text(title)
                .font(.caption)
                .foregroundStyle(secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                Button(buttonTitle, action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                if let secondaryTitle, let secondaryAction {
                    Button(secondaryTitle, action: secondaryAction)
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                        .foregroundStyle(secondaryText)
                }
            }
        }
        .padding(10)
        .background(palette.subtleFill(for: colorScheme), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: - Completion

    private var completionContent: some View {
        VStack(spacing: 16) {
            VStack(spacing: 6) {
                Text("You're ready.")
                    .font(.system(size: 24, weight: .medium))
                    .tracking(-0.35)
                    .foregroundStyle(palette.noteText(for: colorScheme))

                Text(completionSubtitle)
                    .font(.body)
                    .foregroundStyle(secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if showsBackgroundDownloadNotice {
                Text("Speech model is finishing setup in the background — Rasc works right now while it completes.")
                    .font(.caption)
                    .foregroundStyle(secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(palette.subtleFill(for: colorScheme), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            VStack(spacing: 8) {
                completionCommandRow(
                    title: "Open Scratchpad",
                    detail: "Capture anywhere and Esc to park",
                    shortcut: GlobalShortcutFormatting.currentToggleShortcutDisplay()
                )
                completionCommandRow(
                    title: "Open Home",
                    detail: "Browse Kept & unfinished drafts",
                    shortcut: GlobalShortcutFormatting.currentHomeShortcutDisplay()
                )
                completionCommandRow(
                    title: "Command Palette",
                    detail: "Search, Keep, Voice, and Settings",
                    shortcut: InternalShortcutStore.shared.displayString(for: .commandPalette)
                )
            }
            .padding(14)
            .frame(maxWidth: OnboardingLayout.completionMaxWidth)
            .onboardingFeatureSurface()

            VStack(spacing: 8) {
                if coordinator.loginItemState == .requiresApproval {
                    Text("Launch at Login needs approval in System Settings.")
                        .font(.caption)
                        .foregroundStyle(secondaryText)
                }

                if let loginError = coordinator.loginItemError {
                    Text(loginError)
                        .font(.caption)
                        .foregroundStyle(palette.destructiveText(for: colorScheme))
                }

                Button(coordinator.loginItemState.isEnabled ? "Launch at Login enabled" : "Enable Launch at Login") {
                    coordinator.enableLaunchAtLogin()
                }
                .buttonStyle(.bordered)
                .disabled(coordinator.loginItemState.isEnabled || coordinator.isUpdatingLoginItem)
                .controlSize(.small)
            }

            VStack(spacing: 8) {
                Button("Finish") {
                    coordinator.finish()
                }
                .buttonStyle(OnboardingProminentButtonStyle(fullWidth: false))
                .frame(minWidth: OnboardingLayout.ctaMinWidth)
                .keyboardShortcut(.defaultAction)
                .focused($focusedTarget, equals: .completionFinish)
                .accessibilityLabel("Finish onboarding")

                Text("You can reopen this guide anytime from Settings → General.")
                    .font(.caption)
                    .foregroundStyle(metadataText)
            }
        }
        .frame(maxWidth: OnboardingLayout.completionMaxWidth)
    }

    private var completionSubtitle: String {
        if coordinator.practiceWasKept {
            return "Your first thought is Kept in Home."
        }
        let keepShortcut = InternalShortcutStore.shared.displayString(for: .keep)
        return "Your draft stays saved whenever you summon Rasc. Press \(keepShortcut) anytime to Keep a thought."
    }

    private var showsBackgroundDownloadNotice: Bool {
        guard voiceCapture.enabled else { return false }
        switch voiceCapture.setup {
        case .downloading, .importing, .preparing:
            return true
        default:
            return false
        }
    }

    private func completionCommandRow(
        title: String,
        detail: String,
        shortcut: String
    ) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(palette.noteText(for: colorScheme))
                .frame(width: OnboardingLayout.commandTitleWidth, alignment: .leading)
                .lineLimit(1)

            Text(detail)
                .font(.system(size: 12))
                .foregroundStyle(secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            ShortcutKeycapView(label: shortcut, style: .compact)
        }
        .accessibilityElement(children: .combine)
    }

    private func onboardingProgressIndicator(_ progress: (current: Int, total: Int)) -> some View {
        HStack(spacing: 6) {
            ForEach(1...progress.total, id: \.self) { step in
                Circle()
                    .fill(
                        step <= progress.current
                            ? palette.homeSectionLabel(for: colorScheme)
                            : palette.homeSectionLabel(for: colorScheme).opacity(0.26)
                    )
                    .frame(width: 5, height: 5)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(progress.current) of \(progress.total)")
    }

    private func formattedSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func focusCurrentStep() {
        switch coordinator.presentedStep {
        case .welcome:
            focusedTarget = .welcomePrimary
        case .shortcut:
            focusedTarget = .shortcutContinue
        case .capturePractice, .refinePractice:
            if coordinator.captureSubstep == .waitingToResume {
                focusedTarget = .resumeOpen
            } else {
                focusedTarget = nil
            }
        case .voiceSetup:
            focusedTarget = .voiceContinue
        case .completion:
            focusedTarget = .completionFinish
        case .finished:
            focusedTarget = nil
        }
    }

    private func announceCurrentStep() {
        let message: String
        switch coordinator.presentedStep {
        case .welcome:
            message = "Welcome to Rasc. Choose how you plan to use Rasc."
        case .shortcut:
            message = "Open Scratchpad shortcut. Press Continue when ready."
        case .capturePractice, .refinePractice:
            if coordinator.captureSubstep == .waitingToResume {
                message = "Draft parked and saved. Open Rasc once more to continue or keep your thought."
            } else if coordinator.captureSubstep == .waitingForShortcut {
                message = "Try opening Rasc with \(GlobalShortcutFormatting.currentToggleShortcutDisplay())."
            } else {
                return
            }
        case .voiceSetup:
            message = "Capture or dictate by voice."
        case .completion:
            message = "You're ready."
        case .finished:
            return
        }
        RascAccessibility.announce(message)
    }
}

private struct OnboardingBackground: View {
    @Environment(\.rascPalette) private var palette
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            palette.canvas(for: colorScheme)

            RadialGradient(
                colors: [
                    palette.focus(for: colorScheme)
                        .opacity(colorScheme == .dark ? 0.07 : 0.04),
                    .clear,
                ],
                center: .center,
                startRadius: 24,
                endRadius: 320
            )
        }
        .ignoresSafeArea()
    }
}

private struct OnboardingProminentButtonStyle: ButtonStyle {
    var fullWidth = true

    @Environment(\.rascPalette) private var palette
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(palette.actionPrimaryLabel(for: colorScheme))
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .padding(.horizontal, fullWidth ? 0 : 24)
            .padding(.vertical, 9)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(palette.actionPrimaryFill(for: colorScheme))
                    .opacity(isEnabled ? 1 : 0.45)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        palette.actionPrimaryLabel(for: colorScheme).opacity(0.18),
                        lineWidth: 1
                    )
            }
            .opacity(configuration.isPressed ? 0.9 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
    }
}

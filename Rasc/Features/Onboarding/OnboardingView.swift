import KeyboardShortcuts
import SwiftUI

private enum OnboardingLayout {
    static let welcomeMaxWidth: CGFloat = 400
    static let lockupSpacing: CGFloat = 3
    static let identityClusterSpacing: CGFloat = 12
    static let headlineToSupportSpacing: CGFloat = 8
    static let identityToActionsSpacing: CGFloat = 30
    static let actionClusterSpacing: CGFloat = 10
    static let ctaMinWidth: CGFloat = 168
    static let progressStepCount = 3
}

struct OnboardingView: View {
    @Bindable var coordinator: OnboardingCoordinator

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var welcomeFocused: Bool
    @FocusState private var completionFocused: Bool
    @State private var globalShortcutRevision = 0

    var body: some View {
        let _ = globalShortcutRevision
        ZStack {
            OnboardingBackground()

            Group {
                switch coordinator.presentedStep {
                case .welcome:
                    welcomeContent
                case .shortcut:
                    shortcutContent
                case .capturePractice, .refinePractice:
                    if coordinator.captureSubstep == .waitingForShortcut {
                        waitingForShortcutContent
                    } else {
                        Color.clear
                    }
                case .completion:
                    completionContent
                case .finished:
                    Color.clear
                }
            }
            .padding(.horizontal, 48)
            .padding(.vertical, 40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(RascMotion.stageTransition(reduceMotion: reduceMotion))
            .id(coordinator.presentedStep)

            if showsOnboardingSkip {
                onboardingSkipControl
                    .padding(.top, 12)
                    .padding(.trailing, 14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }

            if let progress = onboardingProgress {
                onboardingProgressIndicator(progress)
                    .padding(.top, 14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .frame(
            width: RascWindowMetrics.onboarding.width,
            height: RascWindowMetrics.onboarding.height
        )
        .tint(RascSurfacePalette.actionAccent(for: colorScheme))
        .animation(RascMotion.surface(reduceMotion: reduceMotion), value: coordinator.presentedStep)
        .onAppear {
            focusCurrentStep()
        }
        .onChange(of: coordinator.presentedStep) {
            focusCurrentStep()
        }
        .onChange(of: coordinator.captureSubstep) {
            focusCurrentStep()
        }
        .onGlobalShortcutChange { globalShortcutRevision += 1 }
    }

    private var showsOnboardingSkip: Bool {
        switch coordinator.presentedStep {
        case .welcome, .completion, .finished:
            false
        case .shortcut, .capturePractice, .refinePractice:
            true
        }
    }

    private var onboardingProgress: (current: Int, total: Int)? {
        switch coordinator.presentedStep {
        case .shortcut:
            (1, OnboardingLayout.progressStepCount)
        case .capturePractice, .refinePractice:
            (2, OnboardingLayout.progressStepCount)
        case .completion:
            (3, OnboardingLayout.progressStepCount)
        case .welcome, .finished:
            nil
        }
    }

    private var onboardingSecondaryText: Color {
        colorScheme == .dark
            ? Color.secondary.opacity(0.94)
            : Color.primary.opacity(0.58)
    }

    private var onboardingProductLoopText: Color {
        colorScheme == .dark
            ? Color.secondary.opacity(0.98)
            : Color.primary.opacity(0.64)
    }

    private var welcomeContent: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 16)

            VStack(spacing: OnboardingLayout.identityToActionsSpacing) {
                VStack(spacing: OnboardingLayout.identityClusterSpacing) {
                    welcomeIdentityLockup

                    VStack(spacing: OnboardingLayout.headlineToSupportSpacing) {
                        Text("A scratchpad for unfinished thoughts.")
                            .font(.system(size: 22, weight: .medium))
                            .tracking(-0.35)
                            .foregroundStyle(.primary.opacity(0.94))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)

                        welcomeProductLoopCopy
                    }
                }

                VStack(spacing: OnboardingLayout.actionClusterSpacing) {
                    Button("Get started") {
                        coordinator.continueFromWelcome()
                    }
                    .buttonStyle(OnboardingProminentButtonStyle(fullWidth: false))
                    .frame(minWidth: OnboardingLayout.ctaMinWidth)
                    .keyboardShortcut(.defaultAction)
                    .focused($welcomeFocused)
                    .accessibilityLabel("Get started")

                    welcomeTrustFooter
                }
            }

            Spacer(minLength: 16)
        }
        .frame(maxWidth: OnboardingLayout.welcomeMaxWidth)
        .accessibilityElement(children: .contain)
    }

    private var welcomeIdentityLockup: some View {
        VStack(spacing: OnboardingLayout.lockupSpacing) {
            RascLogo(size: 56)
                .padding(.bottom, 8)

            Text("Rasc")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary.opacity(0.9))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Rasc")
    }

    private var welcomeProductLoopCopy: some View {
        VStack(spacing: 3) {
            Text("Capture without thinking.")
            Text("Refine without prompting.")
            Text("Keep what matters.")
        }
        .font(.system(size: 14))
        .foregroundStyle(onboardingProductLoopText)
        .multilineTextAlignment(.center)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Capture without thinking. Refine without prompting. Keep what matters."
        )
    }

    private var welcomeTrustFooter: some View {
        HStack(spacing: 8) {
            Text("No account required")
            Text("·")
            Text("On-device")
        }
        .font(.system(size: 11.5, weight: .medium))
        .foregroundStyle(onboardingSecondaryText)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No account required. On-device.")
    }

    private var onboardingSkipControl: some View {
        Button("Skip") {
            coordinator.skipSetup()
        }
        .buttonStyle(.plain)
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(onboardingSecondaryText)
        .accessibilityLabel("Skip setup")
        .help("Skip setup")
    }

    private func onboardingProgressIndicator(_ progress: (current: Int, total: Int)) -> some View {
        HStack(spacing: 6) {
            ForEach(1...progress.total, id: \.self) { step in
                Circle()
                    .fill(
                        step <= progress.current
                            ? RascSurfacePalette.homeSectionLabel(for: colorScheme)
                            : RascSurfacePalette.homeSectionLabel(for: colorScheme).opacity(0.26)
                    )
                    .frame(width: 5, height: 5)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(progress.current) of \(progress.total)")
    }

    private var shortcutContent: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            VStack(spacing: 10) {
                Text("One shortcut away.")
                    .font(.system(size: 28, weight: .medium))
                    .tracking(-0.2)

                Text("Rasc appears wherever you're working.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.bottom, 28)

            VStack(spacing: 14) {
                Text("YOUR SHORTCUT")
                    .font(.caption2.weight(.medium))
                    .tracking(0.8)
                    .foregroundStyle(.tertiary)

                ShortcutKeycapView(
                    label: GlobalShortcutFormatting.currentToggleShortcutDisplay(),
                    style: .prominent,
                    isPressed: coordinator.shortcutKeycapPressed
                )

                KeyboardShortcuts.Recorder("Press to change", name: .toggleScratchpad)
                    .accessibilityLabel("Shortcut recorder")
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 22)
            .onboardingFeatureSurface()
            .padding(.bottom, 28)

            Button("Continue") {
                coordinator.continueFromShortcut()
            }
            .buttonStyle(OnboardingProminentButtonStyle(fullWidth: false))
            .frame(minWidth: OnboardingLayout.ctaMinWidth)
            .disabled(!GlobalShortcutFormatting.hasValidToggleShortcut())
            .keyboardShortcut(.defaultAction)
            .accessibilityLabel("Continue")

            Text("You can change this anytime in Settings.")
                .font(.caption)
                .foregroundStyle(onboardingSecondaryText)
                .padding(.top, 16)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: 420)
    }

    private var waitingForShortcutContent: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                Text("Try it.")
                    .font(.system(size: 28, weight: .medium))
                    .tracking(-0.2)

                Text("Press your shortcut to open Rasc.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.bottom, 28)

            VStack {
                ShortcutKeycapView(
                    label: GlobalShortcutFormatting.currentToggleShortcutDisplay(),
                    style: .prominent,
                    isPressed: coordinator.shortcutKeycapPressed
                )
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 22)
            .onboardingFeatureSurface()
        }
        .frame(maxWidth: 400)
        .opacity(coordinator.isYieldingForShortcut ? 0.72 : 1)
        .scaleEffect(coordinator.isYieldingForShortcut && !reduceMotion ? 0.985 : 1)
        .animation(RascMotion.surface(reduceMotion: reduceMotion), value: coordinator.isYieldingForShortcut)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Try it. Press \(GlobalShortcutFormatting.currentToggleShortcutDisplay())")
    }

    private var completionContent: some View {
        VStack(spacing: 0) {
            Text("You're ready.")
                .font(.title2.weight(.medium))
                .padding(.bottom, 8)

            Text("Rasc is always one shortcut away.")
                .font(.body)
                .foregroundStyle(.secondary)
                .padding(.bottom, 24)

            ShortcutKeycapView(
                label: GlobalShortcutFormatting.currentToggleShortcutDisplay(),
                style: .prominent
            )
            .padding(.bottom, 32)

            HStack(spacing: 8) {
                Text("Open Rasc Home with")
                    .font(.caption)
                    .foregroundStyle(onboardingSecondaryText)

                ShortcutKeycapView(
                    label: GlobalShortcutFormatting.currentHomeShortcutDisplay(),
                    style: .compact
                )
            }
            .padding(.bottom, 20)

            VStack(spacing: 12) {
                Text("Keep Rasc ready after login")
                    .font(.subheadline.weight(.medium))

                if coordinator.loginItemState == .requiresApproval {
                    Text("Launch at Login needs approval in System Settings.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                if let loginError = coordinator.loginItemError {
                    Text(loginError)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }

                Button(coordinator.loginItemState.isEnabled ? "Enabled at Login" : "Enable at Login") {
                    coordinator.enableLaunchAtLogin()
                }
                .buttonStyle(.bordered)
                .disabled(coordinator.loginItemState.isEnabled || coordinator.isUpdatingLoginItem)
                .accessibilityLabel(
                    coordinator.loginItemState.isEnabled
                        ? "Launch at Login enabled"
                        : "Enable Launch at Login"
                )

                Text("Recommended if you want Rasc available whenever you need it.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
            .padding(.bottom, 24)

            Button("Finish") {
                coordinator.finish()
            }
            .buttonStyle(OnboardingProminentButtonStyle(fullWidth: false))
            .frame(minWidth: OnboardingLayout.ctaMinWidth)
            .keyboardShortcut(.defaultAction)
            .focused($completionFocused)
            .accessibilityLabel("Finish onboarding")
        }
        .frame(maxWidth: 400)
    }

    private func focusCurrentStep() {
        switch coordinator.presentedStep {
        case .welcome:
            welcomeFocused = true
        case .completion:
            completionFocused = true
        default:
            break
        }
    }
}

private struct OnboardingBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            RascSurfacePalette.canvas(for: colorScheme)

            RadialGradient(
                colors: [
                    RascSurfacePalette.violet(for: colorScheme)
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

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .padding(.horizontal, fullWidth ? 0 : 24)
            .padding(.vertical, 9)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(RascSurfacePalette.actionAccentFill(for: colorScheme))
                    .opacity(isEnabled ? 1 : 0.45)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.08 : 0.18), lineWidth: 1)
            }
            .opacity(configuration.isPressed ? 0.9 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
    }
}

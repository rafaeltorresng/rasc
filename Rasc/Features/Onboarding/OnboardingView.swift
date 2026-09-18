import KeyboardShortcuts
import SwiftUI

struct OnboardingView: View {
    @Bindable var coordinator: OnboardingCoordinator

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var welcomeFocused: Bool
    @FocusState private var completionFocused: Bool

    var body: some View {
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
        }
        .frame(width: 720, height: 520)
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
    }

    private var welcomeContent: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            RascOrb(state: .idle, size: .hero, decorative: true)
                .padding(.bottom, 40)

            Text("Rasc")
                .font(.system(size: 34, weight: .regular))
                .tracking(-0.3)
                .padding(.bottom, 20)

            VStack(spacing: 10) {
                Text("A scratchpad for unfinished thoughts.")
                    .font(.title3)
                    .fontWeight(.regular)
                    .multilineTextAlignment(.center)

                Text("Capture without thinking.\nRefine without prompting.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.bottom, 40)

            VStack(spacing: 12) {
                Button("Get started") {
                    coordinator.continueFromWelcome()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .focused($welcomeFocused)
                .accessibilityLabel("Get started")

                Button("Skip setup") {
                    coordinator.skipSetup()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Skip setup")
            }

            Text("No account · On-device")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.top, 28)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: 400)
    }

    private var shortcutContent: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Text("One shortcut away.")
                    .font(.title2.weight(.medium))

                Text("Rasc appears wherever you're working.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.bottom, 32)

            VStack(spacing: 16) {
                ShortcutKeycapView(
                    label: GlobalShortcutFormatting.currentToggleShortcutDisplay(),
                    style: .prominent,
                    isPressed: coordinator.shortcutKeycapPressed
                )

                KeyboardShortcuts.Recorder("Press to change", name: .toggleScratchpad)
                    .accessibilityLabel("Shortcut recorder")
            }
            .padding(.bottom, 32)

            Button("Continue") {
                coordinator.continueFromShortcut()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!GlobalShortcutFormatting.hasValidToggleShortcut())
            .keyboardShortcut(.defaultAction)
            .accessibilityLabel("Continue")

            Text("You can change this anytime in Settings.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.top, 16)

            Button("Skip setup") {
                coordinator.skipSetup()
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .padding(.top, 8)
            .accessibilityLabel("Skip setup")
        }
        .frame(maxWidth: 400)
    }

    private var waitingForShortcutContent: some View {
        VStack(spacing: 24) {
            Text("Try it.")
                .font(.title2.weight(.medium))

            ShortcutKeycapView(
                label: GlobalShortcutFormatting.currentToggleShortcutDisplay(),
                style: .prominent,
                isPressed: coordinator.shortcutKeycapPressed
            )
        }
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
            .buttonStyle(.borderedProminent)
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
    var body: some View {
        Color(nsColor: .windowBackgroundColor)
            .ignoresSafeArea()
    }
}

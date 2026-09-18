import KeyboardShortcuts
import SwiftUI

struct OnboardingView: View {
    @Bindable var coordinator: OnboardingCoordinator

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var welcomeFocused: Bool
    @FocusState private var completionFocused: Bool

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
                .ignoresSafeArea()

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
            .padding(40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 720, height: 520)
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
        VStack(spacing: 20) {
            ShapingBrandMark()
                .padding(.bottom, 4)

            Text("Rasc")
                .font(.system(size: 28, weight: .semibold))

            VStack(spacing: 8) {
                Text("A scratchpad for unfinished thoughts.")
                    .font(.title3)
                    .multilineTextAlignment(.center)

                Text("Capture without thinking.\nRefine without prompting.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

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
            .padding(.top, 8)

            Text("No account · On-device")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.top, 4)
        }
        .frame(maxWidth: 420)
    }

    private var shortcutContent: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Text("One shortcut away.")
                    .font(.title2.weight(.semibold))
                Text("Rasc appears wherever you're working.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 12) {
                ShortcutKeycapView(
                    label: GlobalShortcutFormatting.currentToggleShortcutDisplay(),
                    reduceMotion: reduceMotion
                )
                .accessibilityLabel("Global shortcut \(GlobalShortcutFormatting.currentToggleShortcutDisplay())")

                KeyboardShortcuts.Recorder("Press to change", name: .toggleScratchpad)
                    .accessibilityLabel("Shortcut recorder")
            }

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

            Button("Skip setup") {
                coordinator.skipSetup()
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Skip setup")
        }
        .frame(maxWidth: 420)
    }

    private var waitingForShortcutContent: some View {
        VStack(spacing: 16) {
            Text("Try it.")
                .font(.title2.weight(.semibold))
            Text("Press \(GlobalShortcutFormatting.currentToggleShortcutDisplay())")
                .font(.title3.monospaced())
                .accessibilityLabel("Press configured global shortcut")
        }
        .opacity(coordinator.isYieldingForShortcut ? 0.55 : 1)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: coordinator.isYieldingForShortcut)
    }

    private var completionContent: some View {
        VStack(spacing: 20) {
            Text("You're ready.")
                .font(.title2.weight(.semibold))

            Text("Rasc is always one shortcut away.")
                .font(.body)
                .foregroundStyle(.secondary)

            ShortcutKeycapView(
                label: GlobalShortcutFormatting.currentToggleShortcutDisplay(),
                reduceMotion: reduceMotion
            )
            .padding(.vertical, 4)

            VStack(spacing: 10) {
                Text("Keep Rasc ready after login")
                    .font(.headline)

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
            .padding(.top, 8)

            Button("Finish") {
                coordinator.finish()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .focused($completionFocused)
            .accessibilityLabel("Finish onboarding")
        }
        .frame(maxWidth: 420)
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

private struct ShortcutKeycapView: View {
    let label: String
    let reduceMotion: Bool

    @State private var isPressed = false

    var body: some View {
        Text(label)
            .font(.title3.monospaced())
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .shadow(
                        color: .black.opacity(isPressed ? 0.04 : 0.12),
                        radius: isPressed ? 1 : 4,
                        y: isPressed ? 0 : 2
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            }
            .scaleEffect(reduceMotion || !isPressed ? 1 : 0.98)
            .offset(y: isPressed ? 1 : 0)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    isPressed = true
                }
            }
    }
}

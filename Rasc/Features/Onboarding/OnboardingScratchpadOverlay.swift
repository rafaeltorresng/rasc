import SwiftUI

struct OnboardingScratchpadActions: @unchecked Sendable {
    var dismissRefineUnavailable: @Sendable () -> Void = {}
    var openRefineSystemSettings: @Sendable () -> Void = {}
}

private struct OnboardingScratchpadActionsKey: EnvironmentKey {
    static let defaultValue = OnboardingScratchpadActions()
}

extension EnvironmentValues {
    var onboardingScratchpadActions: OnboardingScratchpadActions {
        get { self[OnboardingScratchpadActionsKey.self] }
        set { self[OnboardingScratchpadActionsKey.self] = newValue }
    }
}

struct OnboardingScratchpadOverlay: View {
    let guidance: OnboardingScratchpadGuidance
    let editorText: String

    @Environment(\.onboardingScratchpadActions) private var actions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showDelayedEmptyHint = false
    @State private var emptyHintTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
                if let unavailable = guidance.unavailablePresentation {
                    unavailableView(unavailable)
                        .transition(.opacity)
                } else if guidance.showEscapeHint {
                    HStack(spacing: 18) {
                        hintRow(symbol: RascShortcutCatalog.keep.shortcut, text: "Keep and return to work")
                        hintRow(symbol: RascShortcutCatalog.hideScratchpad.shortcut, text: "Hide and continue later")
                    }
                        .transition(hintTransition)
                } else if guidance.showRefineHint {
                    hintRow(symbol: RascShortcutCatalog.refine.shortcut, text: "Refine")
                        .transition(hintTransition)
                } else if guidance.showEmptyHint && editorText.isEmpty && showDelayedEmptyHint {
                    emptyHint
                        .transition(hintTransition)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        .allowsHitTesting(guidance.unavailablePresentation != nil)
        .animation(RascMotion.surface(reduceMotion: reduceMotion), value: guidance)
        .onAppear {
            scheduleEmptyHintIfNeeded()
        }
        .onChange(of: guidance.showEmptyHint) {
            scheduleEmptyHintIfNeeded()
        }
        .onChange(of: editorText) {
            if editorText.isEmpty {
                scheduleEmptyHintIfNeeded()
            } else {
                showDelayedEmptyHint = false
            }
        }
    }

    private var hintTransition: AnyTransition {
        if reduceMotion {
            return .opacity
        }
        return .opacity.combined(with: .offset(y: 5))
    }

    private var emptyHint: some View {
        HStack(spacing: 7) {
            Image(systemName: "text.cursor")
                .font(.caption2)
                .accessibilityHidden(true)

            Text("Anything unfinished is enough.")
                .font(.caption)
        }
        .foregroundStyle(.tertiary)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Anything unfinished is enough.")
    }

    @ViewBuilder
    private func unavailableView(_ presentation: OnboardingRefineUnavailablePresentation) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            switch presentation {
            case .appleIntelligenceDisabled:
                Text("Refine needs Apple Intelligence.")
                    .font(.caption.weight(.semibold))
                Text("Rasc still works without it.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    Button("Open System Settings") {
                        actions.openRefineSystemSettings()
                    }
                    .buttonStyle(.plain)
                    .font(.caption.weight(.medium))
                    Button("Not now") {
                        actions.dismissRefineUnavailable()
                    }
                    .buttonStyle(.plain)
                    .font(.caption.weight(.medium))
                }
            case .modelPreparing:
                Text("Refine is getting ready on your Mac.")
                    .font(.caption.weight(.semibold))
                Text("You can start using Rasc now.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Button("Continue") {
                    actions.dismissRefineUnavailable()
                }
                .buttonStyle(.plain)
                .font(.caption.weight(.medium))
            case .unsupported:
                Text("Refine isn't available on this Mac.")
                    .font(.caption.weight(.semibold))
                Text("Refine needs macOS 26 and Apple Intelligence. Capture and Keep still work.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Button("Continue") {
                    actions.dismissRefineUnavailable()
                }
                .buttonStyle(.plain)
                .font(.caption.weight(.medium))
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func hintRow(symbol: String, text: String) -> some View {
        HStack(spacing: 8) {
            ShortcutKeycapView(label: symbol, style: .compact)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(text), \(symbol)")
    }

    private func scheduleEmptyHintIfNeeded() {
        emptyHintTask?.cancel()

        guard guidance.showEmptyHint, editorText.isEmpty else {
            showDelayedEmptyHint = false
            return
        }

        if reduceMotion {
            showDelayedEmptyHint = true
            return
        }

        guard !showDelayedEmptyHint else { return }

        emptyHintTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, guidance.showEmptyHint, editorText.isEmpty else { return }
            withAnimation(RascMotion.surface(reduceMotion: false)) {
                showDelayedEmptyHint = true
            }
        }
    }

}

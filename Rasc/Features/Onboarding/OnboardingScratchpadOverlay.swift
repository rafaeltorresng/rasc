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
        VStack {
            Spacer()
            VStack(alignment: .leading, spacing: 8) {
                if let unavailable = guidance.unavailablePresentation {
                    unavailableView(unavailable)
                        .transition(.opacity)
                } else if guidance.showEscapeHint {
                    hintRow(symbol: "Esc", text: "Hide Rasc")
                        .transition(hintTransition)
                } else if guidance.showRefineHint {
                    hintRow(symbol: "⌘J", text: "Refine")
                        .transition(hintTransition)
                } else if guidance.showEmptyHint && editorText.isEmpty && showDelayedEmptyHint {
                    emptyHint
                        .transition(hintTransition)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
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
        VStack(alignment: .leading, spacing: 4) {
            Text("Write something unfinished…")
                .font(.callout)
                .foregroundStyle(.tertiary)
            Text("A thought, task, message, idea — anything.")
                .font(.caption)
                .foregroundStyle(.quaternary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Write something unfinished. A thought, task, message, idea — anything.")
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
                    .font(.caption.monospaced())
                    Button("Not now") {
                        actions.dismissRefineUnavailable()
                    }
                    .buttonStyle(.plain)
                    .font(.caption.monospaced())
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
                .font(.caption.monospaced())
            case .unsupported:
                Text("Refine isn't available on this Mac.")
                    .font(.caption.weight(.semibold))
                Text("Capture, search, and history still work normally.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Button("Continue") {
                    actions.dismissRefineUnavailable()
                }
                .buttonStyle(.plain)
                .font(.caption.monospaced())
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(unavailableAccessibilityLabel(presentation))
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

    private func unavailableAccessibilityLabel(
        _ presentation: OnboardingRefineUnavailablePresentation
    ) -> String {
        switch presentation {
        case .appleIntelligenceDisabled:
            "Refine needs Apple Intelligence. Rasc still works without it."
        case .modelPreparing:
            "Refine is getting ready on your Mac."
        case .unsupported:
            "Refine isn't available on this Mac."
        }
    }
}

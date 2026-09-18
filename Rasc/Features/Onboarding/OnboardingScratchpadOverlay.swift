import SwiftUI

struct OnboardingScratchpadActions: @unchecked Sendable {
    var dismissRefineUnavailable: @Sendable () -> Void = {}
    var openRefineSystemSettings: @Sendable () -> Void = {}
}

private struct OnboardingScratchpadActionsKey: EnvironmentKey {
    nonisolated(unsafe) static let defaultValue = OnboardingScratchpadActions()
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

    var body: some View {
        VStack {
            Spacer()
            VStack(alignment: .leading, spacing: 10) {
                if let unavailable = guidance.unavailablePresentation {
                    unavailableView(unavailable)
                } else if guidance.showEscapeHint {
                    hintRow(symbol: "Esc", text: "Hide Rasc")
                } else if guidance.showRefineHint {
                    hintRow(symbol: "⌘J", text: "Refine")
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 4)))
                } else if guidance.showEmptyHint && editorText.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Write something unfinished…")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                        Text("A thought, task, message, idea — anything.")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
        }
        .allowsHitTesting(guidance.unavailablePresentation != nil)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: guidance)
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
            Text(symbol)
                .font(.caption.monospaced().weight(.semibold))
            Text(text)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(text), \(symbol)")
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

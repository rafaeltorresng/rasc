import AppKit
import SwiftUI

final class CapturePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

struct CaptureSurface: View {
    static let windowSize = CGSize(width: 280, height: 72)

    let session: StudySession
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var palette: RascSurfacePalette { .init(preset: session.theme) }
    private var keeps: Bool { session.phase == .kept }
    private var listening: Bool { session.phase == .listening }

    var body: some View {
        HStack(spacing: 8) {
            stateIcon
            Text(session.phase.text)
                .font(.callout.weight(.semibold))
                .lineLimit(1)
                .accessibilityAddTraits(.updatesFrequently)
            Spacer(minLength: 0)
            if keeps {
                capsuleAction("Open", action: session.openReceipt)
                capsuleAction("Undo", action: session.undo)
            } else if listening {
                InputMeter(rms: session.level)
                capsuleAction("Finish recording", symbol: "stop.fill") { session.finish() }
                capsuleAction("Cancel recording", symbol: "xmark", action: session.cancel)
            } else if session.canCancel {
                capsuleAction("Cancel recording", symbol: "xmark", action: session.cancel)
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .frame(width: 256, height: 48)
        .foregroundStyle(palette.noteText(for: scheme))
        .background(palette.raisedFill(for: scheme), in: Capsule())
        .overlay {
            Capsule().strokeBorder(palette.border(for: scheme), lineWidth: contrast == .increased ? 2 : 1)
        }
        .shadow(color: .black.opacity(scheme == .dark ? 0.30 : 0.16), radius: 8, y: 4)
        .frame(width: Self.windowSize.width, height: Self.windowSize.height)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Voice Capture status")
    }

    private var stateIcon: some View {
        Image(systemName: icon)
            .font(.system(size: 12, weight: .semibold))
            .frame(width: 26, height: 26)
            .foregroundStyle(keeps ? palette.keepAccent(for: scheme) : palette.secondaryText(for: scheme))
            .background(keeps ? palette.keepFill(for: scheme) : palette.subtleFill(for: scheme), in: Circle())
            .accessibilityHidden(true)
    }

    private var icon: String {
        switch session.phase {
        case .kept: "checkmark"
        case .listening, .ending: "mic.fill"
        case .preparingTranscript, .finishing, .saving, .discarding: "ellipsis"
        case .silent: "waveform.slash"
        default: "mic"
        }
    }

    private func capsuleAction(_ title: String, symbol: String? = nil,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if let symbol { Image(systemName: symbol).font(.system(size: 10, weight: .semibold)) }
                else { Text(title).font(.caption.weight(.medium)) }
            }
            .frame(minWidth: 40, minHeight: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(CapsuleActionStyle(palette: palette, scheme: scheme, reduceMotion: reduceMotion))
        .accessibilityLabel(title)
        .help(title)
    }
}

private struct CapsuleActionStyle: ButtonStyle {
    let palette: RascSurfacePalette
    let scheme: ColorScheme
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? palette.subtleFill(for: scheme) : .clear, in: Capsule())
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
    }
}

private struct InputMeter: View {
    let rms: Float

    var body: some View {
        let level = min(1, max(0, (20 * log10(max(rms, 0.00001)) + 58) / 42))
        HStack(spacing: 2) {
            ForEach(0..<5) { index in
                let threshold = Float(index) / 5
                let amount = CGFloat(max(0, min(1, (level - threshold) * 5)))
                Capsule()
                    .frame(width: 2, height: 3 + amount * CGFloat(3 + index * 2))
                    .opacity(0.34 + amount * 0.66)
            }
        }
        .frame(width: 22, height: 16)
        .accessibilityHidden(true)
    }
}

struct KeepStyle: ButtonStyle {
    let palette: RascSurfacePalette
    let scheme: ColorScheme
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .padding(.horizontal, 16)
            .frame(minHeight: 32)
            .foregroundStyle(palette.keepAccent(for: scheme))
            .background(palette.keepFill(for: scheme), in: Capsule())
            .opacity(!enabled ? 0.45 : configuration.isPressed ? 0.75 : 1)
    }
}

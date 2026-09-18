import SwiftUI

enum ShortcutKeycapStyle {
    case compact
    case standard
    case prominent
}

struct ShortcutKeycapView: View {
    let label: String
    var style: ShortcutKeycapStyle = .standard
    var isPressed: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: keySpacing) {
            ForEach(Array(tokens.enumerated()), id: \.offset) { _, token in
                singleKeycap(token)
            }
        }
        .animation(RascMotion.keycapPress, value: isPressed)
        .animation(RascMotion.micro(reduceMotion: reduceMotion), value: isHovered)
        .onHover { isHovered = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Shortcut \(label)")
    }

    private var tokens: [String] {
        label
            .split(separator: " ")
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    private var keySpacing: CGFloat {
        switch style {
        case .compact: 4
        case .standard: 6
        case .prominent: 8
        }
    }

    @ViewBuilder
    private func singleKeycap(_ token: String) -> some View {
        let pressed = isPressed
        let elevated = isHovered && !pressed

        Text(token)
            .font(font)
            .foregroundStyle(.primary)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .shadow(
                        color: .black.opacity(shadowOpacity(pressed: pressed, elevated: elevated)),
                        radius: shadowRadius(pressed: pressed, elevated: elevated),
                        y: shadowOffset(pressed: pressed, elevated: elevated)
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(borderOpacity), lineWidth: 1)
            }
            .scaleEffect(scale(pressed: pressed))
            .offset(y: pressed ? 1.5 : (elevated ? -0.5 : 0))
    }

    private var font: Font {
        switch style {
        case .compact:
            .caption.monospaced().weight(.semibold)
        case .standard:
            .callout.monospaced().weight(.medium)
        case .prominent:
            .title3.monospaced().weight(.medium)
        }
    }

    private var horizontalPadding: CGFloat {
        switch style {
        case .compact: 6
        case .standard: 10
        case .prominent: 16
        }
    }

    private var verticalPadding: CGFloat {
        switch style {
        case .compact: 3
        case .standard: 7
        case .prominent: 10
        }
    }

    private var cornerRadius: CGFloat {
        switch style {
        case .compact: 5
        case .standard: 8
        case .prominent: 10
        }
    }

    private var borderOpacity: Double {
        switch style {
        case .compact: 0.1
        case .standard: 0.1
        case .prominent: 0.12
        }
    }

    private func scale(pressed: Bool) -> CGFloat {
        guard !reduceMotion else { return 1 }
        if pressed { return 0.975 }
        return 1
    }

    private func shadowOpacity(pressed: Bool, elevated: Bool) -> Double {
        if pressed { return 0.04 }
        if elevated { return 0.14 }
        return 0.1
    }

    private func shadowRadius(pressed: Bool, elevated: Bool) -> CGFloat {
        if pressed { return 0.5 }
        if elevated { return 5 }
        return 3
    }

    private func shadowOffset(pressed: Bool, elevated: Bool) -> CGFloat {
        if pressed { return 0 }
        if elevated { return 2.5 }
        return 1.5
    }
}

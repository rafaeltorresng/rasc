import SwiftUI

struct ShapingIndicator: View {
    var size: CGFloat = 20
    var label: String? = "refining…"

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPulsing = false

    var body: some View {
        HStack(spacing: 8) {
            indicator
            if let label {
                Text(label)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label ?? "Processing")
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        }
    }

    @ViewBuilder
    private var indicator: some View {
        ZStack {
            Circle()
                .strokeBorder(Color.primary.opacity(0.18), lineWidth: 1)
            Circle()
                .fill(Color.primary.opacity(reduceMotion ? 0.22 : (isPulsing ? 0.28 : 0.14)))
                .scaleEffect(reduceMotion ? 1 : (isPulsing ? 0.92 : 0.78))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct ShapingBrandMark: View {
    var size: CGFloat = 44

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var didSettle = false

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
            Circle()
                .fill(Color.primary.opacity(0.08))
                .scaleEffect(reduceMotion || didSettle ? 1 : 0.88)
                .opacity(reduceMotion || didSettle ? 1 : 0.6)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion else {
                didSettle = true
                return
            }
            withAnimation(.easeOut(duration: 0.5)) {
                didSettle = true
            }
        }
    }
}

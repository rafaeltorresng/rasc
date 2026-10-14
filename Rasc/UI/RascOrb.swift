import AppKit
import SwiftUI
import ThinkingOrbsKit

enum RascOrbState: Equatable {
    case note
    case searching
    case refining
    case connecting
    case composing

    static func resolve(isRefining: Bool, isSearching: Bool = false) -> Self {
        if isRefining {
            return .refining
        }
        if isSearching {
            return .searching
        }
        return .note
    }

    var thinkingOrbState: OrbState {
        switch self {
        case .note:
            .solving
        case .searching:
            .searching
        case .refining:
            .shaping
        case .connecting:
            .connecting
        case .composing:
            .composing
        }
    }

    var speed: Double {
        switch self {
        case .note:
            0.5
        case .searching:
            0.68
        case .refining:
            1
        case .connecting:
            0.58
        case .composing:
            0.48
        }
    }

    var opacity: Double {
        1
    }

    var isPaused: Bool {
        false
    }
}

enum RascOrbSize {
    case hero
    case inline
}

// Violet-led diagonal tint with a warm trailing accent. Values align with
// RascSurfacePalette; appearance-specific stops keep the orb legible on graphite.
private enum RascOrbPalette {
    // Brand anchors (light appearance): 117/100/216 → 199/74/20
    private static let brandViolet = Color(.sRGB, red: 117 / 255, green: 100 / 255, blue: 216 / 255, opacity: 1)
    private static let brandOrange = Color(.sRGB, red: 199 / 255, green: 74 / 255, blue: 20 / 255, opacity: 1)

    static func gradient(for colorScheme: ColorScheme) -> Gradient {
        switch colorScheme {
        case .dark:
            Gradient(stops: [
                .init(
                    color: Color(.sRGB, red: 0.72, green: 0.64, blue: 1.0, opacity: 1),
                    location: 0
                ),
                .init(
                    color: Color(.sRGB, red: 0.604, green: 0.537, blue: 0.933, opacity: 1),
                    location: 0.38
                ),
                .init(color: brandViolet.opacity(0.92), location: 0.68),
                .init(
                    color: Color(.sRGB, red: 0.965, green: 0.482, blue: 0.208, opacity: 1),
                    location: 1
                ),
            ])
        default:
            // Saturated stops read clearly on the warm near-white canvas; pale
            // highlights wash out because the engine lowers tint opacity on bright geometry.
            Gradient(stops: [
                .init(
                    color: Color(.sRGB, red: 0.404, green: 0.318, blue: 0.804, opacity: 1),
                    location: 0
                ),
                .init(
                    color: Color(.sRGB, red: 0.361, green: 0.278, blue: 0.741, opacity: 1),
                    location: 0.34
                ),
                .init(color: brandViolet, location: 0.58),
                .init(
                    color: Color(.sRGB, red: 0.278, green: 0.196, blue: 0.588, opacity: 1),
                    location: 0.80
                ),
                .init(
                    color: Color(.sRGB, red: 0.700, green: 0.235, blue: 0.065, opacity: 1),
                    location: 1
                ),
            ])
        }
    }

    static func presenceShadow(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(.sRGB, red: 0.604, green: 0.537, blue: 0.933, opacity: 0.30)
            : Color(.sRGB, red: 0.361, green: 0.278, blue: 0.741, opacity: 0.26)
    }
}

struct RascOrb: View {
    let state: RascOrbState
    let size: RascOrbSize
    var decorative: Bool = false

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var windowIsVisible = false

    var body: some View {
        orbCanvas
            .frame(width: pointSize, height: pointSize)
            .opacity(state.opacity)
            .animation(
                reduceMotion ? nil : .easeOut(duration: RascMotion.orbTransitionDuration),
                value: state
            )
            .accessibilityHidden(decorative)
            .background {
                OrbWindowVisibilityReader(isVisible: $windowIsVisible)
                    .frame(width: 0, height: 0)
                    .allowsHitTesting(false)
            }
    }

    @ViewBuilder
    private var orbCanvas: some View {
        let orb = ThinkingOrb(
            state: state.thinkingOrbState,
            size: thinkingOrbSize,
            theme: .auto,
            speed: state.speed,
            paused: state.isPaused || !windowIsVisible,
            gradient: RascOrbPalette.gradient(for: colorScheme)
        )
        if reduceTransparency {
            orb
        } else {
            orb.shadow(
                color: RascOrbPalette.presenceShadow(for: colorScheme),
                radius: presenceShadowRadius,
                x: 0,
                y: 0
            )
        }
    }

    private var presenceShadowRadius: CGFloat {
        size == .hero ? 6 : 3
    }

    private var thinkingOrbSize: OrbSize {
        switch size {
        case .hero:
            .px64
        case .inline:
            .px20
        }
    }

    private var pointSize: CGFloat {
        switch size {
        case .hero:
            64
        case .inline:
            RascSurfaceLayout.orbSize
        }
    }
}

// Retained NSHostingViews can keep servicing TimelineView after orderOut.
// Observe the actual AppKit window instead of assuming SwiftUI pauses it.
private struct OrbWindowVisibilityReader: NSViewRepresentable {
    @Binding var isVisible: Bool

    func makeNSView(context: Context) -> OrbWindowVisibilityView {
        let view = OrbWindowVisibilityView()
        view.onVisibilityChange = { isVisible = $0 }
        return view
    }

    func updateNSView(_ view: OrbWindowVisibilityView, context: Context) {
        view.onVisibilityChange = { isVisible = $0 }
    }
}

final class OrbWindowVisibilityView: NSView {
    var onVisibilityChange: ((Bool) -> Void)?
    private var visibilityObservation: NSKeyValueObservation?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(self)
        visibilityObservation?.invalidate()
        visibilityObservation = nil
        if let window {
            visibilityObservation = window.observe(\.isVisible, options: [.new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in self?.reportVisibility() }
            }
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(windowVisibilityChanged),
                name: NSWindow.didChangeOcclusionStateNotification,
                object: window
            )
        }
        reportVisibility()
    }

    @objc private func windowVisibilityChanged(_ notification: Notification) {
        reportVisibility()
    }

    private func reportVisibility() {
        // Avoid mutating SwiftUI state during NSViewRepresentable attachment.
        Task { @MainActor [weak self] in
            guard let self else { return }
            onVisibilityChange?(window?.isVisible == true && window?.occlusionState.contains(.visible) == true)
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

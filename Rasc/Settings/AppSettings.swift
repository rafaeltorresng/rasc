import AppKit
import SwiftUI

@MainActor
final class SettingsOpenActionRegistrar {
    static let shared = SettingsOpenActionRegistrar()

    private var window: NSWindow?

    func install() {
        guard window == nil else { return }

        let hostingController = NSHostingController(
            rootView: SettingsOpenActionRegistrationView()
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = hostingController
        window.isReleasedWhenClosed = false
        window.alphaValue = 0
        window.orderBack(nil)
        self.window = window
    }
}

private struct SettingsOpenActionRegistrationView: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                SettingsWindowPresentation.register(openSettings)
            }
    }
}

struct RascSettingsLink<Label: View>: View {
    @ViewBuilder let label: () -> Label

    var body: some View {
        SettingsLink {
            label()
        }
    }
}

extension View {
    func presentsSettings(on request: Int) -> some View {
        modifier(SettingsPresentationModifier(request: request))
    }

    func registersSettingsOpenAction() -> some View {
        modifier(RegisterSettingsOpenActionModifier())
    }
}

private struct RegisterSettingsOpenActionModifier: ViewModifier {
    @Environment(\.openSettings) private var openSettings

    func body(content: Content) -> some View {
        content
            .onAppear {
                SettingsWindowPresentation.register(openSettings)
            }
    }
}

private struct SettingsPresentationModifier: ViewModifier {
    let request: Int

    @Environment(\.openSettings) private var openSettings

    func body(content: Content) -> some View {
        content
            .onChange(of: request) { _, request in
                guard request > 0 else { return }
                SettingsWindowPresentation.present(using: openSettings)
            }
    }
}

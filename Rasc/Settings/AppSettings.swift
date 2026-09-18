import SwiftUI

extension View {
    func presentsSettings(on request: Int) -> some View {
        modifier(SettingsPresentationModifier(request: request))
    }
}

private struct SettingsPresentationModifier: ViewModifier {
    let request: Int

    @Environment(\.openSettings) private var openSettings

    func body(content: Content) -> some View {
        content.onChange(of: request) { _, request in
            guard request > 0 else { return }
            openSettings()
        }
    }
}

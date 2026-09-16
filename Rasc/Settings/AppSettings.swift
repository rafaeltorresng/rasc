import AppKit

/// Presents the SwiftUI `Settings` scene registered in `RascApp`.
///
/// SwiftUI wires a `showSettingsWindow:` action for `Settings` scenes. This is the
/// documented AppKit bridge for opening settings programmatically.
/// See: https://developer.apple.com/documentation/swiftui/settings
enum AppSettings {
    @MainActor
    static func present() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}

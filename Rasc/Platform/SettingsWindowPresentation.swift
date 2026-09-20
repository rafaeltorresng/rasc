import AppKit
import SwiftUI

@MainActor
enum SettingsWindowPresentation {
    private static let settingsFrameAutosaveName = "com.apple.SwiftUI.Settings"
    private static var didInstallObservers = false
    private static var registeredOpenSettings: OpenSettingsAction?
    static var onSettingsWindowWillPresent: (() async -> Void)?

    static func register(_ openSettings: OpenSettingsAction) {
        registeredOpenSettings = openSettings
    }

    static func installIfNeeded() {
        SettingsOpenActionRegistrar.shared.install()

        guard !didInstallObservers else { return }
        didInstallObservers = true

        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let window = notification.object as? NSWindow else { return }
            Task { @MainActor in
                configureIfNeeded(window)
            }
        }
    }

    static func present(attempt: Int = 0) {
        if let registeredOpenSettings {
            present(using: registeredOpenSettings)
            return
        }

        guard attempt < 8 else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            Task { @MainActor in
                present(attempt: attempt + 1)
            }
        }
    }

    static func present(using openSettings: OpenSettingsAction) {
        installIfNeeded()
        Task { @MainActor in
            await onSettingsWindowWillPresent?()
            NSApp.activate(ignoringOtherApps: true)
            openSettings()
            configureVisibleSettingsWindowsWithRetry()
        }
    }

    static func configureIfNeeded(_ window: NSWindow) {
        guard isSettingsWindow(window) else { return }
        applyPresentationPolicy(to: window)
    }

    private static func configureVisibleSettingsWindowsWithRetry(attempt: Int = 0) {
        let configured = configureVisibleSettingsWindows()
        guard !configured, attempt < 6 else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            Task { @MainActor in
                configureVisibleSettingsWindowsWithRetry(attempt: attempt + 1)
            }
        }
    }

    @discardableResult
    private static func configureVisibleSettingsWindows() -> Bool {
        var configured = false

        for window in NSApp.windows where isSettingsWindow(window) {
            applyPresentationPolicy(to: window)
            window.makeKeyAndOrderFront(nil)
            configured = true
        }

        return configured
    }

    private static func applyPresentationPolicy(to window: NSWindow) {
        window.collectionBehavior.formUnion([.moveToActiveSpace, .fullScreenAuxiliary])
    }

    private static func isSettingsWindow(_ window: NSWindow) -> Bool {
        window.frameAutosaveName == settingsFrameAutosaveName
    }
}

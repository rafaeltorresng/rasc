import AppKit
import SwiftUI

@MainActor
enum SettingsNavigation {
    static let keyboardShortcutsID = "keyboard-shortcuts"
    static let revealNotification = Notification.Name("RascSettingsRevealKeyboardShortcuts")
    private static var pendingKeyboardShortcuts = false

    static func revealKeyboardShortcuts() {
        prepareKeyboardShortcutsReveal()
        SettingsWindowPresentation.present()
    }

    static func prepareKeyboardShortcutsReveal() {
        pendingKeyboardShortcuts = true
        NotificationCenter.default.post(name: revealNotification, object: nil)
    }

    static func consumeKeyboardShortcutsRequest() -> Bool {
        let pending = pendingKeyboardShortcuts
        pendingKeyboardShortcuts = false
        return pending
    }
}

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

    static func configureIfNeeded(_ window: NSWindow, reposition: Bool = false) {
        guard isSettingsWindow(window) else { return }
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        if reposition {
            positionOnPresentationScreen(window)
        }
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
        configureIfNeeded(window, reposition: true)
    }

    private static func positionOnPresentationScreen(_ window: NSWindow) {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }
        if WindowFramePlacement.screenContaining(frame: window.frame, in: screens) != nil {
            return
        }

        guard let screen = WindowFramePlacement.targetPresentationScreen(
            excludingProcessID: NSRunningApplication.current.processIdentifier
        ) else {
            return
        }

        window.setFrameOrigin(
            WindowFramePlacement.centeredOrigin(
                for: window.frame.size,
                in: screen.visibleFrame
            )
        )
    }

    private static func isSettingsWindow(_ window: NSWindow) -> Bool {
        window.frameAutosaveName == settingsFrameAutosaveName
    }
}

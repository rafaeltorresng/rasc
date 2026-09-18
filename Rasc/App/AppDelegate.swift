import AppKit
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let toggleScratchpad = Self(
        "toggleScratchpad",
        initial: .init(.backslash, modifiers: [.option])
    )
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, MenuBarControllerDelegate {
    private let bootstrap = AppBootstrap()
    private let onboardingCoordinator = OnboardingCoordinator()
    private var menuBarController: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        GlobalShortcutMigration.migrateFromPreviousDefaultIfNeeded()
        menuBarController = MenuBarController(delegate: self)
        bootstrap.start()

        let forceResetOnboarding = ProcessInfo.processInfo.arguments.contains("-resetOnboarding")
        Task { @MainActor in
            await onboardingCoordinator.prepare(
                bootstrap: bootstrap,
                forceReset: forceResetOnboarding
            )
        }

        KeyboardShortcuts.onKeyUp(for: .toggleScratchpad) { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                if self.onboardingCoordinator.shouldFlashShortcutKeycap() {
                    self.onboardingCoordinator.flashShortcutKeycap()
                }
                if await self.onboardingCoordinator.handleGlobalShortcut() {
                    return
                }
                guard let panel = await self.bootstrap.awaitPanel() else { return }
                await panel.toggle()
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func startNewScratch() {
        Task { @MainActor in
            await bootstrap.awaitPanel()?.startNewScratch()
        }
    }

    func openSearch() {
        Task { @MainActor in
            await bootstrap.awaitPanel()?.openSearch()
        }
    }

    func openCommandPalette() {
        Task { @MainActor in
            await bootstrap.awaitPanel()?.openCommandPalette()
        }
    }

    func refine() {
        bootstrap.panelIfReady()?.startRefinement()
    }

    func openSettings() {
        Task { @MainActor in
            if let panel = await bootstrap.awaitPanel() {
                panel.openSettings()
            } else {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Task { @MainActor [weak self] in
            let didFlush = await self?.bootstrap.panelIfReady()?.flushForTermination() ?? true
            if didFlush {
                sender.reply(toApplicationShouldTerminate: true)
            } else {
                let alert = NSAlert()
                alert.messageText = "Rasc couldn't save your latest changes."
                alert.informativeText = "The app will remain open so you can retry."
                alert.alertStyle = .critical
                alert.runModal()
                sender.reply(toApplicationShouldTerminate: false)
            }
        }
        return .terminateLater
    }

    func menuBarOpenRasc() {
        Task { @MainActor in
            await bootstrap.awaitPanel()?.show()
        }
    }

    func menuBarNewScratch() {
        startNewScratch()
    }

    func menuBarOpenSearch() {
        openSearch()
    }

    func menuBarOpenSettings() {
        openSettings()
    }

    func menuBarQuit() {
        NSApp.terminate(nil)
    }

    #if DEBUG
    func menuBarResetOnboarding() {
        onboardingCoordinator.resetOnboardingStateOnly()
    }
    #endif
}

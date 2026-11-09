import AppKit
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let toggleScratchpad = Self(
        "toggleScratchpad",
        initial: .init(.backslash, modifiers: [.option])
    )
    static let toggleHome = Self(
        "toggleHome",
        initial: .init(.backslash, modifiers: [.command, .option])
    )
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, MenuBarControllerDelegate {
    private let bootstrap = AppBootstrap()
    private let onboardingCoordinator = OnboardingCoordinator()
    private var menuBarController: MenuBarController?

    override init() {
        #if DEBUG
        TestHostIsolation.installIfNeeded()
        #endif
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        if TestHostIsolation.isAppTestHost {
            if !TestHostIsolation.isInstalled {
                fatalError("Rasc test host launched without isolated storage")
            }
            return
        }
        if RefineReviewCommandLine.runIfRequested() { return }
        if RefineEvalLanguageResolverCommandLine.runIfRequested() { return }
        if RefineEvalCommandLine.runIfRequested() { return }
        #endif

        GlobalShortcutMigration.migrateFromPreviousDefaultIfNeeded()
        AppThemeApplicator.applyStoredTheme()
        SettingsWindowPresentation.installIfNeeded()
        SettingsWindowPresentation.onSettingsWindowWillPresent = { [weak self] in
            await self?.bootstrap.prepareForSettingsPresentation()
        }
        menuBarController = MenuBarController(delegate: self)
        InternalShortcutStore.shared.applyToMainMenu()
        bootstrap.start()

        let forceResetOnboarding = ProcessInfo.processInfo.arguments.contains("-resetOnboarding")
        #if DEBUG
        let showScratchpad = ProcessInfo.processInfo.arguments.contains("-showScratchpad")
        #endif
        Task { @MainActor in
            await onboardingCoordinator.prepare(
                bootstrap: bootstrap,
                forceReset: forceResetOnboarding
            )
            #if DEBUG
            if showScratchpad {
                await bootstrap.awaitPanel()?.show()
            }
            #endif
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

        KeyboardShortcuts.onKeyUp(for: .toggleHome) { [weak self] in
            Task { @MainActor in
                await self?.bootstrap.toggleHome()
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

    func keepActiveNote() {
        Task { @MainActor in
            await bootstrap.awaitPanel()?.keepActiveNote()
        }
    }

    func unkeepActiveNote() {
        Task { @MainActor in
            await bootstrap.awaitPanel()?.unkeepActiveNote()
        }
    }

    func copyActiveNote() {
        Task { @MainActor in
            await bootstrap.awaitPanel()?.copyActiveNote()
        }
    }

    func shareActiveNote() {
        bootstrap.panelIfReady()?.shareActiveNote()
    }

    func discardActiveNote() {
        Task { @MainActor in
            await bootstrap.awaitPanel()?.discardActiveNote()
        }
    }

    func openSettings() {
        Task { @MainActor in
            await bootstrap.openSettings()
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

    func openHome() {
        Task { @MainActor in
            await bootstrap.openHome()
        }
    }

    func toggleHome() {
        Task { @MainActor in
            await bootstrap.toggleHome()
        }
    }

    func menuBarOpenScratch() {
        Task { @MainActor in
            await bootstrap.awaitPanel()?.show()
        }
    }

    func menuBarOpenHome() {
        openHome()
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

    func menuBarSendFeedback() {
        BetaFeedback.open()
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

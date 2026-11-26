import AppKit
import KeyboardShortcuts
#if RASC_SPARKLE
import Sparkle
#endif

struct SparkleUpdaterConfiguration: Equatable {
    static let placeholderPublicKey = "REPLACE_WITH_ED25519_PUBLIC_KEY"

    let feedURL: URL
    let publicKey: String

    static func validate(feedURLString: String?, publicKey: String?) -> SparkleUpdaterConfiguration? {
        guard
            let feedURLString,
            let publicKey,
            !publicKey.isEmpty,
            publicKey != placeholderPublicKey,
            let keyData = Data(base64Encoded: publicKey),
            keyData.count == 32,
            let feedURL = URL(string: feedURLString),
            feedURL.scheme == "https",
            feedURL.host?.isEmpty == false
        else {
            return nil
        }

        return SparkleUpdaterConfiguration(feedURL: feedURL, publicKey: publicKey)
    }

    static func current(bundle: Bundle = .main) -> SparkleUpdaterConfiguration? {
        validate(
            feedURLString: bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String,
            publicKey: bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String
        )
    }
}

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
    private nonisolated(unsafe) var globalShortcutObserver: (any NSObjectProtocol)?
    private nonisolated(unsafe) var appActiveObserver: (any NSObjectProtocol)?
#if RASC_SPARKLE
    private var updaterController: SPUStandardUpdaterController?
#endif

    deinit {
        if let globalShortcutObserver { NotificationCenter.default.removeObserver(globalShortcutObserver) }
        if let appActiveObserver { NotificationCenter.default.removeObserver(appActiveObserver) }
    }

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
        if VoiceEvalCommandLine.runIfRequested() { return }
        #endif

        GlobalShortcutMigration.migrateFromPreviousDefaultIfNeeded()
        GlobalShortcutStore.shared.migrateLegacyPreferencesIfNeeded()
        AppThemeApplicator.applyStoredTheme()
        SettingsWindowPresentation.installIfNeeded()
        SettingsWindowPresentation.onSettingsWindowWillPresent = { [weak self] in
            await self?.bootstrap.prepareForSettingsPresentation()
        }
        menuBarController = MenuBarController(delegate: self)
        #if RASC_SPARKLE
        if SparkleUpdaterConfiguration.current() != nil,
           NSClassFromString("SPUStandardUpdaterController") != nil {
            updaterController = SPUStandardUpdaterController(
                startingUpdater: true,
                updaterDelegate: nil,
                userDriverDelegate: nil
            )
        }
        #endif
        InternalShortcutStore.shared.applyToMainMenu()
        VoiceCapture.shared.onRefreshGlobalModifiers = { [weak self] in
            self?.refreshGlobalModifierDispatcher()
        }
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

        KeyboardShortcuts.onKeyDown(for: .toggleScratchpad) {
            VoiceCapture.shared.noteExternalChordInput()
        }
        KeyboardShortcuts.onKeyUp(for: .toggleScratchpad) { [weak self] in
            self?.triggerScratchpadShortcut()
        }

        KeyboardShortcuts.onKeyDown(for: .toggleHome) {
            VoiceCapture.shared.noteExternalChordInput()
        }
        KeyboardShortcuts.onKeyUp(for: .toggleHome) { [weak self] in
            self?.triggerHomeShortcut()
        }

        globalShortcutObserver = NotificationCenter.default.addObserver(
            forName: GlobalShortcutStore.didChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshGlobalModifierDispatcher()
                VoiceCapture.shared.refreshShortcut()
            }
        }
        appActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                VoiceCapture.shared.refreshAccessibilityStatus()
                self?.refreshGlobalModifierDispatcher()
            }
        }
        refreshGlobalModifierDispatcher()
    }

    private func triggerScratchpadShortcut() {
        Task { @MainActor [weak self] in
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

    private func triggerHomeShortcut() {
        Task { @MainActor [weak self] in
            await self?.bootstrap.toggleHome()
        }
    }

    private func refreshGlobalModifierDispatcher() {
        let bindings = GlobalShortcutStore.shared.activeModifierBindings { action in
            switch action {
            case .toggleScratchpad, .toggleHome:
                return true
            case .voiceScratchpad, .voiceDictate:
                return VoiceCapture.shared.enabled
            }
        }
        GlobalModifierDispatcher.shared.sync(bindings: bindings) { [weak self] action in
            switch action {
            case .toggleScratchpad:
                self?.triggerScratchpadShortcut()
            case .toggleHome:
                self?.triggerHomeShortcut()
            case .voiceScratchpad:
                VoiceCapture.shared.activate(intent: .scratchpad, fromShortcut: true)
            case .voiceDictate:
                VoiceCapture.shared.activate(intent: .dictate, fromShortcut: true)
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

    func exportThought() {
        Task { await bootstrap.exportThought() }
    }

    func exportThoughts() {
        Task { await bootstrap.exportThoughts() }
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
        if VoiceCapture.shared.hasUnsavedAudio {
            let alert = NSAlert()
            alert.messageText = "Voice Capture is still in progress"
            alert.informativeText = "Finish or cancel the capture before quitting Rasc."
            alert.runModal()
            return .terminateCancel
        }
        Task { @MainActor [weak self] in
            let voiceFlushed = await VoiceCapture.shared.flushForTermination()
            let didFlush = await self?.bootstrap.panelIfReady()?.flushForTermination() ?? true
            if didFlush && voiceFlushed {
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

    func menuBarExportThoughts() {
        exportThoughts()
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

    func menuBarCheckForUpdates() {
        checkForUpdates()
    }

    func checkForUpdates() {
        #if RASC_SPARKLE
        if let updaterController {
            updaterController.checkForUpdates(nil)
            return
        }
        #endif
        let alert = NSAlert()
        alert.messageText = "Updates are not available in this build."
        alert.informativeText = "This build was not packaged with the Sparkle updater. Download the latest version from rasc.app."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
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

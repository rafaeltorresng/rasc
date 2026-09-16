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
    private var panelController: PanelController?
    private var menuBarController: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        GlobalShortcutMigration.migrateFromPreviousDefaultIfNeeded()
        menuBarController = MenuBarController(delegate: self)

        Task { [weak self] in
            do {
                let repository = try await Task.detached {
                    try NoteRepository.openDefault()
                }.value
                let panelController = PanelController(repository: repository)
                self?.panelController = panelController

                KeyboardShortcuts.onKeyUp(for: .toggleScratchpad) { [weak panelController] in
                    Task {
                        await panelController?.toggle()
                    }
                }
            } catch {
                let alert = NSAlert()
                alert.messageText = "Couldn't open Rasc's local notes."
                alert.informativeText = "Your existing notes were not changed."
                alert.alertStyle = .critical
                alert.runModal()
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func startNewScratch() {
        Task { [weak self] in
            await self?.panelController?.startNewScratch()
        }
    }

    func openSearch() {
        Task { [weak self] in
            await self?.panelController?.openSearch()
        }
    }

    func openCommandPalette() {
        Task { [weak self] in
            await self?.panelController?.openCommandPalette()
        }
    }

    func refine() {
        panelController?.startRefinement()
    }

    func openSettings() {
        AppSettings.present()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Task { [weak self] in
            let didFlush = await self?.panelController?.flushForTermination() ?? true
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
        Task { [weak self] in
            await self?.panelController?.show()
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
}

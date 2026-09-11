import AppKit
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let toggleScratchpad = Self(
        "toggleScratchpad",
        initial: .init(.space, modifiers: [.option])
    )
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panelController: PanelController?

    func applicationDidFinishLaunching(_ notification: Notification) {
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
}

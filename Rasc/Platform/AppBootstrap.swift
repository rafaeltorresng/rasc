import AppKit
import Foundation

@MainActor
final class AppBootstrap {
    private var panelController: PanelController?
    private var homeWindowController: HomeWindowController?
    private var loadTask: Task<PanelController?, Never>?
    private let startedAt = ContinuousClock.now

    func start() {
        guard loadTask == nil else { return }
        AppDiagnostics.bootstrapStarted()

        loadTask = Task { @MainActor in
            do {
                let repository = try await Task.detached {
                    try NoteRepository.openDefault()
                }.value
                let controller = PanelController(repository: repository)
                controller.onOpenHome = { [weak self] in
                    Task { @MainActor in
                        await self?.openHome()
                    }
                }
                controller.onOpenSettings = { [weak self] in
                    Task { @MainActor in
                        await self?.openSettings()
                    }
                }
                controller.onDidHide = { [weak self] in
                    self?.reloadHomeIfVisible()
                }
                panelController = controller
                let durationMs = Int((ContinuousClock.now - startedAt).components.attoseconds / 1_000_000_000_000_000)
                AppDiagnostics.bootstrapReady(durationMs: max(durationMs, 0))
                return controller
            } catch {
                AppDiagnostics.bootstrapFailed()
                let alert = NSAlert()
                alert.messageText = "Couldn't open Rasc's local notes."
                alert.informativeText = "Your existing notes were not changed."
                alert.alertStyle = .critical
                alert.runModal()
                return nil
            }
        }
    }

    func panelIfReady() -> PanelController? {
        panelController
    }

    func awaitPanel() async -> PanelController? {
        if let panelController {
            return panelController
        }
        return await loadTask?.value
    }

    func openHome() async {
        guard let panel = await awaitPanel() else { return }

        if panel.panel.isVisible {
            await panel.hide()
        }

        let home = homeWindowController ?? HomeWindowController()
        homeWindowController = home
        home.show(
            repository: panel.repository,
            onOpenNote: { noteID in
                Task { @MainActor in
                    await panel.openNote(id: noteID)
                }
            },
            onNewScratch: {
                Task { @MainActor in
                    await panel.startNewScratch()
                }
            }
        )
    }

    func openSettings() async {
        presentSettings()
    }

    func prepareForSettingsPresentation() async {
        if let panel = await awaitPanel(), panel.panel.isVisible {
            await panel.hide()
        }
    }

    var homeIsVisible: Bool {
        homeWindowController?.isVisible == true
    }

    func reloadHomeIfVisible() {
        homeWindowController?.reloadIfVisible()
    }

    private func presentSettings() {
        SettingsWindowPresentation.present()
    }
}

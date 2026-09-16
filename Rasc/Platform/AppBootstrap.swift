import AppKit
import Foundation

@MainActor
final class AppBootstrap {
    private var panelController: PanelController?
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
}

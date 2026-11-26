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
                controller.onVoiceCapture = { VoiceCapture.shared.activate(intent: .scratchpad) }
                controller.onVoiceDictate = { VoiceCapture.shared.activate(intent: .dictate) }
                controller.onVoiceCaptureShortcut = { VoiceCapture.shared.handleScratchpadShortcut($0) }
                controller.onDidHide = { [weak self] in
                    self?.reloadHomeIfVisible()
                }
                panelController = controller
                VoiceCapture.shared.connect(repository: repository)
                VoiceCapture.shared.onNotesChanged = { [weak self, weak controller] in
                    self?.reloadHomeIfVisible()
                    controller?.refreshSearchAfterVoiceCapture()
                }
                VoiceCapture.shared.onOpenScratch = { [weak controller] id, interrupted in
                    await controller?.openCapturedScratch(id: id, interrupted: interrupted) == true
                }
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
        home.onVisibilityChange = { [weak self] isVisible in
            self?.panelController?.noteHomeVisibility(isVisible)
        }
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
            },
            prepareForDuplicate: { [weak panel] noteID in
                guard let panel else { throw NoteRepository.PersistenceError.staleContent }
                try await panel.flushActiveNoteIfMatching(id: noteID)
            },
            onNoteDiscarded: { noteID in
                Task { @MainActor in
                    await panel.abandonActiveNoteIfMatching(id: noteID)
                }
            },
            onNoteUnkept: { noteID in
                Task { @MainActor in
                    await panel.refreshActiveNoteIfMatching(id: noteID)
                }
            },
            onExportThought: { [weak self] id in
                Task { @MainActor in await self?.exportHomeThought(id) }
            },
            onExportSelected: { [weak self] ids in
                Task { @MainActor in await self?.exportSelectedHomeThoughts(ids) }
            }
        )
    }

    func exportThought() async {
        guard let panel = await awaitPanel() else { return }
        if homeWindowController?.isKeyWindow == true {
            if let id = homeWindowController?.selectedNoteID { await exportHomeThought(id) }
        } else if panel.panel.isKeyWindow {
            await panel.exportActiveThought()
        }
    }

    private func exportSelectedHomeThoughts(_ ids: Set<UUID>) async {
        guard let panel = await awaitPanel(), let window = homeWindowController?.exportWindow else { return }
        await panel.noteExport.exportSelectedThoughts(from: window, ids: ids, prepare: panel.prepareThoughtsForExport)
    }

    private func exportHomeThought(_ id: UUID) async {
        guard let panel = await awaitPanel(), let window = homeWindowController?.exportWindow else { return }
        await panel.noteExport.exportThought(from: window) {
            try await panel.prepareThoughtsForExport(.selected([id]))
            return id
        }
    }

    func exportThoughts() async {
        guard let panel = await awaitPanel() else { return }
        if let window = NSApp.keyWindow, window === homeWindowController?.exportWindow || window === panel.panel {
            await panel.noteExport.exportThoughts(from: window, prepare: panel.prepareThoughtsForExport)
        } else {
            await openHome()
            guard let window = homeWindowController?.exportWindow else { return }
            await panel.noteExport.exportThoughts(from: window, prepare: panel.prepareThoughtsForExport)
        }
    }

    func toggleHome() async {
        if homeIsVisible {
            homeWindowController?.close()
            return
        }
        await openHome()
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

    #if RASC_EFFICIENCY_BENCHMARK
    var benchmarkHomeController: HomeWindowController? {
        homeWindowController
    }
    #endif

    func reloadHomeIfVisible() {
        homeWindowController?.reloadIfVisible()
    }

    private func presentSettings() {
        SettingsWindowPresentation.present()
    }
}

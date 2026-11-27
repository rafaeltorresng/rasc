import AppKit
import Foundation

@MainActor
final class DatabaseBackupBridge {
    static let shared = DatabaseBackupBridge()
    var backupHandler: (@MainActor (URL) async throws -> Void)?
}

@MainActor
final class AppBootstrap {
    private var panelController: PanelController?
    private var homeWindowController: HomeWindowController?
    private var loadTask: Task<PanelController?, Never>?
    private(set) var hasLoadFailure = false
    private let startedAt = ContinuousClock.now

    func start() {
        guard loadTask == nil else { return }
        hasLoadFailure = false
        AppDiagnostics.bootstrapStarted()

        loadTask = Task { @MainActor in
            do {
                let repository = try await Task.detached {
                    try NoteRepository.openDefault()
                }.value
                DatabaseBackupBridge.shared.backupHandler = { destinationURL in
                    try await repository.backup(to: destinationURL)
                }
                Task.detached(priority: .utility) {
                    _ = try? await repository.purgeExpiredSoftDeletedNotes()
                }
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
                hasLoadFailure = false
                VoiceCapture.shared.connect(repository: repository)
                VoiceCapture.shared.onNotesChanged = { [weak self, weak controller] in
                    self?.reloadHomeIfVisible()
                    controller?.refreshSearchAfterVoiceCapture()
                }
                VoiceCapture.shared.onOpenScratch = { [weak controller] id, interrupted in
                    await controller?.openCapturedScratch(id: id, interrupted: interrupted) == true
                }
                let elapsed = ContinuousClock.now - startedAt
                let durationMs = Int(elapsed.components.seconds * 1_000 + elapsed.components.attoseconds / 1_000_000_000_000_000)
                AppDiagnostics.bootstrapReady(durationMs: max(durationMs, 0))
                return controller
            } catch {
                loadTask = nil
                hasLoadFailure = true
                AppDiagnostics.bootstrapFailed()
                presentRecoveryAlert(for: error)
                return nil
            }
        }
    }

    private func presentRecoveryAlert(for error: Error) {
        let alert = NSAlert()
        alert.messageText = "Couldn't open Rasc's local notes."
        if case .newerSchemaVersion = error as? AppDatabaseError {
            alert.informativeText = "This database was created by a newer version of Rasc. Update Rasc before opening it. Your existing notes were not changed."
        } else {
            alert.informativeText = "Your existing notes were not changed."
        }
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Retry")
        alert.addButton(withTitle: "Reveal Data Folder")
        alert.addButton(withTitle: "Quit Rasc")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            start()
        case .alertSecondButtonReturn:
            revealDataFolder()
        default:
            NSApp.terminate(nil)
        }
    }

    private func revealDataFolder() {
        if let databaseURL = try? NoteRepository.defaultDatabaseURL {
            if FileManager.default.fileExists(atPath: databaseURL.path) {
                NSWorkspace.shared.activateFileViewerSelecting([databaseURL])
            } else {
                NSWorkspace.shared.open(databaseURL.deletingLastPathComponent())
            }
        }
    }

    func panelIfReady() -> PanelController? {
        panelController
    }

    func checkpointForTermination() async {
        await panelController?.repository.checkpointForTermination()
    }

    func awaitPanel() async -> PanelController? {
        if let panelController {
            return panelController
        }
        if loadTask == nil {
            start()
        }
        return await loadTask?.value
    }

    func openHome() async {
        guard let panel = await awaitPanel() else { return }

        if panel.panel.isVisible {
            await panel.hide(restorePreviousApplication: false)
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
            await panel.hide(restorePreviousApplication: false)
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

import AppKit
import AVFoundation
import Combine
import Foundation
import GRDB
import KeyboardShortcuts
import SwiftUI
import Testing
@testable import Rasc

@MainActor
@Suite(.serialized)
struct VoiceCaptureTests {
    @Test func outputPreferenceDefaultsToScratchpadAndPersists() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let capture = fixture.capture(enabled: false)
        #expect(capture.output == .scratchpad)
        #expect(!capture.standaloneKeepsHistory)
        capture.setOutput(.insertAtCursor)
        #expect(capture.output == .insertAtCursor)
        capture.setOutput(.clipboard)
        #expect(capture.output == .clipboard)
        #expect(fixture.defaults.string(forKey: VoiceCapture.outputPreferenceKey) == "clipboard")
        capture.setStandaloneKeepsHistory(true)
        #expect(capture.standaloneKeepsHistory)
        #expect(fixture.defaults.bool(forKey: VoiceCapture.standaloneHistoryPreferenceKey))
    }

    @Test func clipboardModeCopiesTranscriptWithoutSavingNoteOrOpeningScratch() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let capture = fixture.capture(presentWindows: false, pasteboard: pasteboard)
        capture.setOutput(.clipboard)
        var openedScratch = false
        capture.onOpenScratch = { _, _ in openedScratch = true; return true }
        capture.activate()
        try await wait { capture.phase == .listening }
        capture.finish()
        try await wait { capture.phase == .copied }
        #expect(pasteboard.string(forType: .string) == "Talvez não fazer o deploy ainda.")
        #expect(!openedScratch)
        #expect(try await fixture.repository.fetchAllNonDeleted().isEmpty)
    }

    @Test func clipboardModeSavesStandaloneHistoryOnlyWhenEnabled() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let capture = fixture.capture(presentWindows: false, pasteboard: pasteboard)
        capture.setOutput(.clipboard)
        capture.setStandaloneKeepsHistory(true)
        capture.activate()
        try await wait { capture.phase == .listening }
        capture.finish()
        try await wait { capture.phase == .copied }
        let notes = try await fixture.repository.fetchAllNonDeleted()
        #expect(notes.map(\.content) == ["Talvez não fazer o deploy ainda."])
        #expect(!notes[0].isKept)
    }

    @Test func insertModeFallsBackToClipboardWhenInsertionUnavailable() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let capture = fixture.capture(presentWindows: false, pasteboard: pasteboard)
        capture.setOutput(.insertAtCursor)
        capture.activate()
        try await wait { capture.phase == .listening }
        capture.finish()
        // No accessible target application in tests; must fall back cleanly.
        try await wait { capture.phase == .copiedFallback }
        #expect(pasteboard.string(forType: .string) == "Talvez não fazer o deploy ainda.")
        #expect(try await fixture.repository.fetchAllNonDeleted().isEmpty)
    }

    @Test func assignedShortcutRegistersOnlyWhileVoiceCaptureIsEnabled() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let previous = KeyboardShortcuts.getShortcut(for: .voiceCapture)
        let capture = fixture.capture(enabled: false, presentWindows: true)
        defer {
            capture.setEnabled(false)
            KeyboardShortcuts.removeHandler(for: .voiceCapture)
            KeyboardShortcuts.setShortcut(previous, for: .voiceCapture)
            KeyboardShortcuts.enable(.voiceCapture)
        }

        KeyboardShortcuts.setShortcut(nil, for: .voiceCapture)
        capture.setEnabled(true)
        #expect(!capture.shortcutIsActive)

        let chord = KeyboardShortcuts.Shortcut(.f18, modifiers: [.control, .option, .shift, .command])
        KeyboardShortcuts.setShortcut(chord, for: .voiceCapture)
        capture.refreshShortcut()
        #expect(capture.shortcutIsActive)
        #expect(KeyboardShortcuts.isEnabled(for: .voiceCapture))

        capture.setEnabled(false)
        #expect(!capture.shortcutIsActive)
        #expect(!KeyboardShortcuts.isEnabled(for: .voiceCapture))
        #expect(KeyboardShortcuts.getShortcut(for: .voiceCapture) == chord)

        capture.setEnabled(true)
        #expect(capture.shortcutIsActive)
    }

    @Test func disabledCaptureLeavesMicrophoneIdle() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let capture = fixture.capture(enabled: false)
        capture.activate(fromShortcut: true)
        #expect(capture.phase == .idle)
        #expect(await fixture.input.starts == 0)
        #expect(await fixture.input.requests == 0)
    }

    @Test func enabledLaunchPreparesSpeechAndDefersMemoryReleaseUntilAfterCapture() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let model = ModelReadinessProbe()
        let capture = fixture.capture(speech: .init(
            assetsAvailable: { true }, prepare: { try await model.prepare() },
            transcribe: { _, ready in
                try await model.waitUntilReady()
                await ready()
                return "Prepared during capture."
            }, release: { await model.release() }
        ))
        try await wait { capture.setup == .preparing }
        await model.waitUntilPrepared()
        #expect(await model.preparations == 1)
        #expect(await fixture.input.starts == 0)
        capture.activate()
        try await wait { capture.phase == .listening }
        capture.releaseModelWhenSafe()
        capture.finish()
        try await wait { capture.phase == .waitingForModel }
        #expect(await model.releases == 0)
        #expect(await fixture.input.active == nil)
        await model.makeReady()
        try await wait { capture.phase == .idle }
        #expect(await model.preparations == 1)
        #expect(await model.releases == 1)
        #expect(try await fixture.repository.fetchAllNonDeleted().map(\.content) == ["Prepared during capture."])
    }

    @Test func modelTimeoutRetainsAudioForRetryAndIgnoresLateResults() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let stale = DecodeGate()
        let attempts = ModelReadinessProbe()
        let capture = fixture.capture(speech: .init(
            assetsAvailable: { true }, prepare: {}, transcribe: { _, ready in
                if await attempts.nextAttempt() == 1 { return await stale.wait() }
                await ready()
                return "Recovered from the same recording."
            }, release: {}
        ), modelTimeout: .milliseconds(110))
        capture.activate()
        try await wait { capture.phase == .listening }
        capture.finish()
        await stale.waitUntilEntered()
        try await wait { capture.phase == .issue(.modelTimeout) }
        #expect(capture.canRetryAudio)
        capture.recover()
        try await wait { capture.phase == .idle }
        await stale.release()
        #expect(await fixture.input.starts == 1)
        #expect(try await fixture.repository.fetchAllNonDeleted().map(\.content) == ["Recovered from the same recording."])
    }

    @Test func lowDiskFailureKeepsTheRecordingReadyToRetry() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let attempts = ModelReadinessProbe()
        let capture = fixture.capture(speech: .init(
            assetsAvailable: { true }, prepare: {}, transcribe: { _, ready in
                if await attempts.nextAttempt() == 1 { throw VoiceModel.PreparationError.lowDiskSpace }
                await ready()
                return "Saved after freeing space."
            }, release: {}
        ))
        capture.activate()
        try await wait { capture.phase == .listening }
        capture.finish()
        try await wait { capture.phase == .issue(.lowDiskSpace) }
        #expect(capture.canRetryAudio)
        capture.recover()
        try await wait { capture.phase == .idle }
        #expect(await fixture.input.starts == 1)
        #expect(try await fixture.repository.fetchAllNonDeleted().map(\.content) == ["Saved after freeing space."])
    }

    @Test func downloadModelReportsProgressInstallsPreparesAndAllowsRemoval() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let store = DownloadStateProbe()
        let gate = DecodeGate()
        let capture = fixture.capture(speech: .init(
            assetsAvailable: { store.available },
            hasInstalledAssets: { store.installed },
            downloadSizeBytes: { 1000 },
            download: { progress in
                progress(400, 1000)
                _ = await gate.wait()
                progress(1000, 1000)
                store.markInstalled()
            },
            removeInstalled: { store.markRemoved() },
            prepare: { store.recordPrepare() },
            transcribe: { _, ready in await ready(); return "Downloaded." },
            release: { store.recordRelease() }
        ))
        try await wait { capture.setup == .missing }
        #expect(!capture.canRemoveInstalledModel)
        capture.downloadModel()
        await gate.waitUntilEntered()
        try await wait {
            if case .downloading(let downloaded, let total) = capture.setup {
                return downloaded >= 400 && total == 1000
            }
            return false
        }
        await gate.release()
        try await wait { capture.setup == .installed }
        #expect(capture.canRemoveInstalledModel)
        #expect(store.prepares == 1)

        capture.removeInstalledModel()
        try await wait { capture.setup == .missing }
        #expect(!capture.canRemoveInstalledModel)
        #expect(store.releases == 1)
        #expect(store.removals == 1)
    }

    @Test func cancellingModelDownloadRestoresMissingWithoutPreparing() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let store = DownloadStateProbe()
        let gate = DecodeGate()
        let capture = fixture.capture(speech: .init(
            assetsAvailable: { store.available },
            hasInstalledAssets: { store.installed },
            downloadSizeBytes: { 1000 },
            download: { progress in
                progress(250, 1000)
                _ = await gate.wait()
                try Task.checkCancellation()
            },
            removeInstalled: {},
            prepare: { store.recordPrepare() },
            transcribe: { _, ready in await ready(); return "" },
            release: {}
        ))
        try await wait { capture.setup == .missing }
        capture.downloadModel()
        await gate.waitUntilEntered()
        try await wait {
            if case .downloading = capture.setup { return true }
            return false
        }
        capture.cancelModelDownload()
        await gate.release()
        try await wait { capture.setup == .missing }
        #expect(store.prepares == 0)
    }

    @Test func interruptedDownloadRecoversOnRetryAndLowDiskMapsCorrectly() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let store = DownloadStateProbe()
        let attempts = ModelReadinessProbe()
        let capture = fixture.capture(speech: .init(
            assetsAvailable: { store.available },
            hasInstalledAssets: { store.installed },
            downloadSizeBytes: { 1000 },
            download: { _ in
                switch await attempts.nextAttempt() {
                case 1: throw VoiceModel.PreparationError.lowDiskSpace
                case 2: throw URLError(.networkConnectionLost)
                default: store.markInstalled()
                }
            },
            removeInstalled: {},
            prepare: { store.recordPrepare() },
            transcribe: { _, ready in await ready(); return "" },
            release: {}
        ))
        try await wait { capture.setup == .missing }
        capture.downloadModel()
        try await wait { capture.setup == .lowDiskSpace }

        capture.downloadModel()
        try await wait { capture.setup == .downloadFailed }

        capture.downloadModel()
        try await wait { capture.setup == .installed }
        #expect(capture.canRemoveInstalledModel)
        #expect(store.prepares == 1)
    }

    @Test func resourceConstraintReleasesAndRepreparesWhenPressureSubsides() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let store = DownloadStateProbe()
        store.markInstalled()
        let capture = fixture.capture(speech: .init(
            assetsAvailable: { store.available },
            hasInstalledAssets: { store.installed },
            prepare: { store.recordPrepare() },
            transcribe: { _, ready in await ready(); return "" },
            release: { store.recordRelease() }
        ))
        try await wait { capture.setup == .installed }
        #expect(store.prepares == 1)

        capture.handleResourceConstraint()
        try await wait { store.releases == 1 }

        // A second constraint before reprepare completes cancels the pending reprepare.
        capture.scheduleReprepareAfterConstraint(delay: .milliseconds(80))
        capture.handleResourceConstraint()
        try await wait { store.releases == 2 }
        try await Task.sleep(for: .milliseconds(100))
        #expect(store.prepares == 1)

        // Once normal/wake arrives without another constraint, the model re-prepares.
        capture.scheduleReprepareAfterConstraint(delay: .milliseconds(20))
        try await wait { store.prepares == 2 }
    }

    @Test func repeatedSleepWakeAndFluctuatingMemoryPressureAvoidsReloadLoops() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let store = DownloadStateProbe()
        store.markInstalled()
        let capture = fixture.capture(speech: .init(
            assetsAvailable: { store.available },
            hasInstalledAssets: { store.installed },
            prepare: { store.recordPrepare() },
            transcribe: { _, ready in await ready(); return "" },
            release: { store.recordRelease() }
        ))
        try await wait { capture.setup == .installed }
        #expect(store.prepares == 1)

        // Spurious .normal memory pressure while already prepared must be a no-op.
        capture.scheduleReprepareAfterConstraint(delay: .milliseconds(15))
        try await Task.sleep(for: .milliseconds(40))
        #expect(store.prepares == 1)

        // Repeated sleep/wake cycles stay 1:1 with zero extra reloads.
        for cycle in 1...10 {
            capture.handleResourceConstraint()
            try await wait { store.releases == cycle }
            capture.scheduleReprepareAfterConstraint(delay: .milliseconds(15))
            try await wait { store.prepares == cycle + 1 }
        }

        // Rapidly fluctuating pressure bursts coalesce into a single re-prepare after settling.
        let baseReleases = store.releases
        let basePrepares = store.prepares
        for _ in 0..<5 {
            capture.handleResourceConstraint()
            capture.scheduleReprepareAfterConstraint(delay: .milliseconds(150))
        }
        try await wait { store.releases == baseReleases + 5 }
        try await wait { store.prepares == basePrepares + 1 }
        try await Task.sleep(for: .milliseconds(80))
        #expect(store.prepares == basePrepares + 1)
    }

    @Test func repeatedPreparationFailuresDoNotLoopOnWakeOrNormalPressure() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let store = DownloadStateProbe()
        store.markInstalled()
        let attempts = ModelReadinessProbe()
        let capture = fixture.capture(speech: .init(
            assetsAvailable: { store.available },
            hasInstalledAssets: { store.installed },
            prepare: {
                store.recordPrepare()
                switch await attempts.nextAttempt() {
                case 1: throw VoiceModel.PreparationError.unavailable
                case 2: throw VoiceModel.PreparationError.lowDiskSpace
                default: break
                }
            },
            transcribe: { _, ready in await ready(); return "" },
            release: { store.recordRelease() }
        ))
        try await wait { capture.setup == .failed }
        #expect(store.prepares == 1)

        // Wake / .normal pressure must not re-trigger failed preparation.
        capture.handleResourceConstraint()
        capture.scheduleReprepareAfterConstraint(delay: .milliseconds(15))
        try await Task.sleep(for: .milliseconds(40))
        #expect(store.prepares == 1)
        #expect(capture.setup == .failed)

        // Explicit retry hitting lowDiskSpace also does not loop on subsequent wake.
        capture.prepareModel()
        try await wait { capture.setup == .lowDiskSpace }
        #expect(store.prepares == 2)
        capture.handleResourceConstraint()
        capture.scheduleReprepareAfterConstraint(delay: .milliseconds(15))
        try await Task.sleep(for: .milliseconds(40))
        #expect(store.prepares == 2)
        #expect(capture.setup == .lowDiskSpace)

        // Explicit recovery succeeds and restores adaptive lifecycle.
        capture.prepareModel()
        try await wait { capture.setup == .installed }
        #expect(store.prepares == 3)
        capture.handleResourceConstraint()
        capture.scheduleReprepareAfterConstraint(delay: .milliseconds(15))
        try await wait { store.prepares == 4 }
    }

    @Test func voiceModelRepeatedFailuresLeaveNoStuckLoadingState() async throws {
        let model = VoiceModel()
        for _ in 1...3 {
            await #expect(throws: VoiceModel.PreparationError.unavailable) {
                try await model.prepare()
            }
        }
        await model.releaseForMemoryPressure()
        await #expect(throws: VoiceModel.PreparationError.unavailable) {
            try await model.prepare()
        }
    }

    @Test func meterUpdatesStayLocalToTheRecordingMeter() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let capture = fixture.capture()
        var coordinatorChanges = 0
        var meterChanges = 0
        let coordinator = capture.objectWillChange.sink { coordinatorChanges += 1 }
        let meter = capture.inputLevel.objectWillChange.sink { meterChanges += 1 }
        withExtendedLifetime((coordinator, meter)) {
            capture.inputLevel.update(0.2)
            capture.inputLevel.update(0.2)
            capture.inputLevel.update(0.4)
            #expect(meterChanges == 2)
            #expect(coordinatorChanges == 0)
        }
    }

    @Test func opensAnOrdinaryScratchThatCanBeEditedRefinedAndKept() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let provider = VoiceHandoffRefinementProvider()
        let session = ScratchpadSession(repository: fixture.repository, refinementProvider: provider,
                                        userDefaults: fixture.defaults)
        session.text = "An unfinished typed thought"
        let capture = fixture.capture()
        capture.onOpenScratch = { id, _ in (try? await session.openNote(id: id)) == true }
        capture.activate()
        try await wait { capture.phase == .listening }
        #expect(capture.hasUnsavedAudio)
        capture.finish()
        capture.finish()
        try await wait { capture.phase == .idle }

        let transcript = "Talvez não fazer o deploy ainda."
        #expect(session.text == transcript)
        #expect(session.surface == .editor)
        #expect(session.editorSelection == nil)
        #expect(!session.isActiveNoteKept)
        #expect(await provider.requests.isEmpty)
        let saved = try await fixture.repository.fetchAllNonDeleted()
        #expect(saved.count == 2)
        let typed = try #require(saved.first { $0.content == "An unfinished typed thought" })
        let voice = try #require(saved.first { $0.content == transcript })
        #expect(!voice.isKept)
        #expect(!capture.hasUnsavedAudio)
        #expect(await fixture.input.active == nil)

        session.text = "Talvez não fazer o deploy hoje."
        session.scheduleAutosave()
        try await session.flush()
        #expect(try await fixture.repository.fetch(id: voice.id)?.content == session.text)
        session.startRefinement()
        try await wait { session.surface == .refinementPreview }
        #expect(await provider.requests.first?.snapshot.text == session.text)
        try await session.acceptRefinement()
        let outcome = try await session.keepActiveNote()
        #expect(outcome == .keptShouldHide)
        #expect(try await fixture.repository.fetch(id: voice.id)?.content == VoiceHandoffRefinementProvider.suggestion)
        #expect(try await fixture.repository.fetch(id: voice.id)?.isKept == true)
        #expect(try await fixture.repository.fetch(id: typed.id) == typed)
    }

    @Test func repeatedCancellationStopsInputWithoutKeepingAnything() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let capture = fixture.capture()
        for _ in 0..<40 {
            capture.activate()
            try await wait { capture.phase == .listening }
            capture.cancel()
            capture.cancel()
            try await wait { capture.phase == .idle }
        }
        #expect(await fixture.input.starts == 40)
        #expect(await fixture.input.stops == 40)
        #expect(await fixture.input.active == nil)
        #expect(try await fixture.repository.fetchAllNonDeleted().isEmpty)
    }

    @Test func lateDecodeCannotReplaceANewSession() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let gate = DecodeGate()
        let capture = fixture.capture { _ in await gate.wait() }
        capture.activate()
        try await wait { capture.phase == .listening }
        capture.finish()
        await gate.waitUntilEntered()
        capture.cancel()
        try await wait { capture.phase == .idle }
        capture.activate()
        try await wait { capture.phase == .listening }
        await gate.release()
        try await Task.sleep(for: .milliseconds(40))
        #expect(capture.phase == .listening)
        #expect(try await fixture.repository.fetchAllNonDeleted().isEmpty)
        capture.cancel()
        try await wait { capture.phase == .idle }
    }

    @Test func routesDenialAndSilenceWithoutWriting() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let denied = fixture.capture(authorization: .denied)
        denied.activate()
        try await wait { denied.phase == .issue(.permission) }
        #expect(await fixture.input.starts == 0)
        #expect(await fixture.input.requests == 0)
        let silence = fixture.capture(audible: false)
        silence.activate()
        try await wait { silence.phase == .listening }
        silence.finish()
        try await wait { silence.phase == .issue(.noSpeech) }
        #expect(try await fixture.repository.fetchAllNonDeleted().isEmpty)
        #expect(await fixture.input.active == nil)
    }

    @Test func systemPermissionIsRequestedOnlyOnExplicitStart() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let capture = fixture.capture(authorization: .notDetermined)
        #expect(await fixture.input.requests == 0)
        capture.activate()
        try await wait { capture.phase == .listening }
        #expect(await fixture.input.requests == 1)
        capture.cancel()
        try await wait { capture.phase == .idle }
    }

    @Test func interruptionOpensRecoverableTextAndDiscardUsesTheScratchpad() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let session = ScratchpadSession(repository: fixture.repository, userDefaults: fixture.defaults)
        var interrupted = false
        let capture = fixture.capture()
        capture.onOpenScratch = { id, endedEarly in
            interrupted = endedEarly
            return (try? await session.openNote(id: id)) == true
        }
        capture.activate()
        try await wait { capture.phase == .listening }
        await fixture.input.interrupt()
        try await wait { capture.phase == .idle }
        #expect(interrupted)
        #expect(session.text == "Talvez não fazer o deploy ainda.")

        session.text = "Ainda não."
        try await session.flush()
        let restarted = ScratchpadSession(repository: fixture.repository, userDefaults: fixture.defaults)
        try await restarted.restore()
        #expect(restarted.text == "Ainda não.")
        #expect(await fixture.input.starts == 1)
        try await restarted.discardActiveNote()
        #expect(try await fixture.repository.fetchAllNonDeleted().isEmpty)
    }

    @Test func disableCancelsCaptureAndPreventsRestart() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let capture = fixture.capture()
        capture.activate()
        try await wait { capture.phase == .listening }
        capture.setEnabled(false)
        try await wait { capture.phase == .idle }
        capture.activate(fromShortcut: true)
        #expect(await fixture.input.active == nil)
        #expect(await fixture.input.starts == 1)
    }

    @Test func blockedHandoffPersistsTheThoughtAndRetriesOpeningTheSameNote() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let session = ScratchpadSession(repository: fixture.repository, userDefaults: fixture.defaults)
        session.text = "Typed text stays in front"
        var canOpen = false
        let capture = fixture.capture()
        capture.onOpenScratch = { id, _ in
            (try? await session.openNote(id: id, canOpen: { canOpen })) == true
        }

        capture.activate()
        try await wait { capture.phase == .listening }
        capture.finish()
        try await wait { capture.phase == .ready }
        #expect(session.text == "Typed text stays in front")
        let saved = try await fixture.repository.search("deploy", limit: 10)
        #expect(saved.count == 1)
        #expect(saved.first?.isKept == false)

        canOpen = true
        capture.activate()
        capture.activate()
        try await wait { capture.phase == .idle }
        #expect(session.text == saved.first?.content)
        #expect(try await fixture.repository.search("deploy", limit: 10).map(\.id) == saved.map(\.id))
        #expect(await fixture.input.starts == 1)
    }

    @Test func failedTranscriptSaveCanBeRetriedWithoutReopeningTheMicrophone() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let queue = try DatabaseQueue(path: fixture.database.path)
        defer { try? queue.close() }
        try await queue.write { db in
            try db.execute(sql: """
                CREATE TRIGGER fail_note_insert BEFORE INSERT ON notes
                BEGIN SELECT RAISE(ABORT, 'injected'); END
                """)
        }
        let capture = fixture.capture()
        capture.activate()
        try await wait { capture.phase == .listening }
        capture.finish()
        try await wait { capture.phase == .issue(.persistence) }
        #expect(!capture.canChangeEnabled)
        #expect(!capture.hasUnsavedAudio)
        #expect(try await fixture.repository.fetchAllNonDeleted().isEmpty)

        try await queue.write { db in try db.execute(sql: "DROP TRIGGER fail_note_insert") }
        capture.recover()
        try await wait { capture.phase == .idle }
        let notes = try await fixture.repository.fetchAllNonDeleted()
        #expect(notes.map(\.content) == ["Talvez não fazer o deploy ainda."])
        #expect(notes.first?.isKept == false)
        #expect(await fixture.input.starts == 1)
    }

    @Test func typingDuringHandoffKeepsTheCurrentEditorAndBothThoughts() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let session = ScratchpadSession(repository: fixture.repository, userDefaults: fixture.defaults)
        session.text = "Typed draft"
        let gate = NoteRepositoryTestGate()
        let capture = fixture.capture()
        capture.onOpenScratch = { id, _ in
            await fixture.repository.installTestGate(gate)
            return (try? await session.openNote(id: id)) == true
        }

        capture.activate()
        try await wait { capture.phase == .listening }
        capture.finish()
        try await wait { capture.phase == .opening }
        await gate.waitForFirstEntry()
        session.text = "Typed draft with a new edit"
        gate.release()
        try await wait { capture.phase == .ready }

        #expect(session.text == "Typed draft with a new edit")
        try await session.flush()
        let notes = try await fixture.repository.fetchAllNonDeleted()
        #expect(Set(notes.map(\.content)) == ["Typed draft with a new edit", "Talvez não fazer o deploy ainda."])
    }

    @Test func migrationRecoversTheLegacyReviewAsAnUnfinishedSearchableThought() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "RascVoiceMigration-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "rasc.sqlite")
        let oldQueue = try DatabaseQueue(path: url.path)
        let pending = UUID()
        let typed = UUID()
        try AppDatabase.migrator.migrate(oldQueue, upTo: "v9_voice_review")
        try await oldQueue.write { db in
            let now = Date()
            try Note(id: typed, content: "Typed scratch", createdAt: now, updatedAt: now,
                     deletedAt: nil, keptAt: nil).insert(db)
            try db.execute(sql: "INSERT INTO voice_review (slot, id, content) VALUES (1, ?, ?)",
                           arguments: [pending, "Legacy voice draft"])
        }
        try oldQueue.close()

        let repository = try NoteRepository(databaseURL: url)
        defer { try? repository.closeForTesting() }
        let matches = try await repository.search("legacy", limit: 5)
        #expect(matches.map(\.id) == [pending])
        #expect(matches.first?.isKept == false)
        #expect(try await repository.fetch(id: typed)?.content == "Typed scratch")
    }

    @Test func shortBufferPreservesBoundarySamplesAndSealsAfterFinish() throws {
        let samples = [-0.2 as Float] + Array(repeating: 0.1 as Float, count: 1598) + [0.25]
        let buffer = MicBuffer(rate: 16_000)
        samples.withUnsafeBufferPointer { buffer.append($0) }
        let audio = buffer.audio()
        #expect(try audio.mono16k() == samples)
        #expect(audio.activitySeconds == 0.1)
        samples.withUnsafeBufferPointer { buffer.append($0) }
        #expect(buffer.status().count == 1600)
    }

    @Test func nativeRecordingStatusIsNonKeyAndRendersInBothAppearances() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let capture = fixture.capture()
        let windows = VoiceCaptureWindows(capture: capture)
        defer { windows.hideStatus() }
        capture.activate()
        try await wait { capture.phase == .listening }
        let app = NSApplication.shared
        let keyWindow = app.keyWindow
        windows.showStatus()
        let status = try #require(windows.status)
        #expect(status.isVisible)
        #expect(!status.canBecomeKey)
        #expect(app.keyWindow === keyWindow)
        #expect(status.collectionBehavior.contains(.fullScreenAuxiliary))
        windows.hideStatus()

        for scheme in [ColorScheme.light, .dark] {
            let renderer = HomeSnapshotTests()
            try renderer.renderPNG(VoiceStatusView(capture: capture), width: 304, height: 70,
                                   scheme: scheme, name: "voice-listening-\(scheme)")
        }
        capture.cancel()
        try await wait { capture.phase == .idle }
    }

    private func wait(until predicate: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while !predicate(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(8))
        }
        try #require(predicate())
    }

    private struct Fixture {
        let directory: URL
        let database: URL
        let repository: NoteRepository
        let input = FakeMicrophone()
        let suite = "VoiceCaptureTests.\(UUID())"
        var defaults: UserDefaults { UserDefaults(suiteName: suite)! }

        init() throws {
            directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            database = directory.appending(path: "rasc.sqlite")
            repository = try NoteRepository(databaseURL: database)
        }

        func cleanUp() {
            try? repository.closeForTesting()
            UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }

        @MainActor
        func capture(
            enabled: Bool = true,
            authorization: AVAuthorizationStatus = .authorized,
            audible: Bool = true,
            presentWindows: Bool = false,
            speech: VoiceCapture.Speech? = nil,
            modelTimeout: Duration = .seconds(35),
            pasteboard: NSPasteboard = .general,
            decode: @escaping @Sendable (VoiceAudio) async throws -> String = { _ in "Talvez não fazer o deploy ainda." }
        ) -> VoiceCapture {
            defaults.set(enabled, forKey: VoiceCapture.preferenceKey)
            let capture = VoiceCapture(
                preferences: defaults, supported: true,
                input: .init(
                    authorization: { authorization },
                    requestAccess: { await input.request() },
                    start: { id, route in await input.start(id, audible: audible, route: route) },
                    stop: { id in await input.stop(id) }
                ),
                presentWindows: presentWindows,
                speech: speech ?? .init(assetsAvailable: { true }, prepare: {}, transcribe: { audio, ready in
                    await ready()
                    return try await decode(audio)
                }, release: {}),
                modelTimeout: modelTimeout,
                pasteboard: pasteboard
            )
            capture.connect(repository: repository)
            return capture
        }
    }
}

private actor FakeMicrophone {
    var active: UUID?
    var starts = 0
    var stops = 0
    var requests = 0
    private var route: (@Sendable () -> Void)?

    func request() -> Bool {
        requests += 1
        return true
    }

    func start(_ id: UUID, audible: Bool, route: @escaping @Sendable () -> Void) -> MicBuffer {
        self.route = route
        active = id
        starts += 1
        let buffer = MicBuffer(rate: 16_000)
        let samples = Array(repeating: audible ? Float(0.05) : 0, count: 1600)
        samples.withUnsafeBufferPointer { buffer.append($0) }
        return buffer
    }

    func stop(_ id: UUID) {
        if active == id {
            active = nil
            route = nil
            stops += 1
        }
    }

    func interrupt() { route?() }
}

private actor DecodeGate {
    private var pending: CheckedContinuation<String, Never>?
    private var entered: CheckedContinuation<Void, Never>?

    func wait() async -> String {
        await withCheckedContinuation {
            pending = $0
            entered?.resume()
            entered = nil
        }
    }

    func waitUntilEntered() async {
        if pending == nil { await withCheckedContinuation { entered = $0 } }
    }

    func release() {
        pending?.resume(returning: "Stale text.")
        pending = nil
    }
}

private actor ModelReadinessProbe {
    private(set) var preparations = 0
    private(set) var releases = 0
    private var attempts = 0
    private var ready = false
    private var prepared: CheckedContinuation<Void, Never>?

    func nextAttempt() -> Int {
        attempts += 1
        return attempts
    }

    func prepare() async throws {
        preparations += 1
        prepared?.resume()
        prepared = nil
        try await waitUntilReady()
    }

    func waitUntilPrepared() async {
        if preparations == 0 {
            await withCheckedContinuation { prepared = $0 }
        }
    }

    func waitUntilReady() async throws {
        while !ready { try await Task.sleep(for: .milliseconds(8)) }
    }

    func makeReady() { ready = true }

    func release() { releases += 1 }
}

private final class DownloadStateProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var _available = false
    private var _installed = false
    private var _prepares = 0
    private var _releases = 0
    private var _removals = 0

    var available: Bool { lock.withLock { _available } }
    var installed: Bool { lock.withLock { _installed } }
    var prepares: Int { lock.withLock { _prepares } }
    var releases: Int { lock.withLock { _releases } }
    var removals: Int { lock.withLock { _removals } }

    func markInstalled() {
        lock.withLock {
            _available = true
            _installed = true
        }
    }

    func markRemoved() {
        lock.withLock {
            _available = false
            _installed = false
            _removals += 1
        }
    }

    func recordPrepare() { lock.withLock { _prepares += 1 } }
    func recordRelease() { lock.withLock { _releases += 1 } }
}

private actor VoiceHandoffRefinementProvider: RefinementProvider {
    static let suggestion = "Talvez seja melhor não fazer o deploy hoje."
    nonisolated let metadata = RefinementMetadata(provider: "fake", modelIdentifier: "fake", promptVersion: "test")
    private(set) var requests: [RefinementRequest] = []

    func availability(for _: RefinementRequest) async -> RefinementAvailability { .available }

    func refine(_ request: RefinementRequest) async throws -> RefinementResult {
        requests.append(request)
        return .init(decision: .changed, kind: .messyText, text: Self.suggestion)
    }
}

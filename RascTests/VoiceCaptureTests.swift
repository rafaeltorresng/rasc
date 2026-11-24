import AppKit
import AVFoundation
import Combine
import Foundation
import GRDB
import SwiftUI
import Testing
@testable import Rasc

@MainActor
struct VoiceCaptureTests {
    @Test func disabledCaptureLeavesMicrophoneIdle() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let capture = fixture.capture(enabled: false)
        capture.activate(fromShortcut: true)
        #expect(capture.phase == .idle)
        #expect(await fixture.input.starts == 0)
        #expect(await fixture.input.requests == 0)
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

    @Test func keepsOneOrdinaryThoughtAndPreservesTheScratch() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let created = try await fixture.repository.createScratch(content: "original")
        let scratch = try #require(await fixture.repository.fetch(id: created.id))
        let capture = fixture.capture()
        capture.activate()
        try await wait { capture.phase == .listening }
        #expect(capture.hasUnsavedAudio)
        capture.finish()
        capture.finish()
        try await wait { capture.phase == .reviewing }
        #expect(!capture.hasUnsavedAudio)
        #expect(capture.content == "Talvez não fazer o deploy ainda.")
        #expect(try await fixture.repository.fetchAllNonDeleted() == [scratch])
        capture.edit("Talvez não fazer o deploy hoje.")
        capture.keep()
        capture.keep()
        try await wait { capture.phase == .kept }
        let matches = try await fixture.repository.search("deploy", limit: 10)
        let kept = try #require(matches.first)
        #expect(matches.count == 1)
        #expect(kept.content == "Talvez não fazer o deploy hoje.")
        #expect(kept.isKept)
        #expect(try await fixture.repository.fetch(id: scratch.id) == scratch)
        #expect(try await fixture.repository.pendingVoiceDraft() == nil)
        capture.undo()
        try await wait { capture.phase == .idle }
        #expect(try await fixture.repository.fetchAllNonDeleted() == [scratch])
        #expect(try await fixture.repository.search("deploy", limit: 10).isEmpty)
        #expect(await fixture.input.active == nil)
    }

    @Test func repeatedCancellationStopsInputWithoutKeepingAnything() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let capture = fixture.capture()
        for _ in 0..<120 {
            capture.activate()
            try await wait { capture.phase == .listening }
            capture.cancel()
            capture.cancel()
            try await wait { capture.phase == .idle }
        }
        #expect(await fixture.input.starts == 120)
        #expect(await fixture.input.stops == 120)
        #expect(await fixture.input.active == nil)
        #expect(try await fixture.repository.fetchAllNonDeleted().isEmpty)
        #expect(try await fixture.repository.pendingVoiceDraft() == nil)
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
        #expect(capture.content.isEmpty)
        #expect(try await fixture.repository.pendingVoiceDraft() == nil)
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
        #expect(try await fixture.repository.pendingVoiceDraft() == nil)
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

    @Test func restoresStagedReviewOnRestartWithoutOpeningInput() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let capture = fixture.capture()
        capture.activate()
        try await wait { capture.phase == .listening }
        await fixture.input.interrupt()
        try await wait { capture.phase == .reviewing }
        #expect(capture.reviewMessage?.contains("ended early") == true)
        capture.edit("Ainda não.")
        #expect(await capture.flushReviewForTermination())
        let restarted = fixture.capture()
        restarted.activate()
        try await wait { restarted.phase == .reviewing }
        #expect(restarted.content == "Ainda não.")
        #expect(await fixture.input.starts == 1)
        restarted.cancel()
        try await wait { restarted.phase == .idle }
        #expect(try await fixture.repository.pendingVoiceDraft() == nil)
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

    @Test func closingReopenedReviewPersistsRestoredTextBehindAnEarlierWrite() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let capture = fixture.capture()
        capture.activate()
        try await wait { capture.phase == .listening }
        capture.finish()
        try await wait { capture.phase == .reviewing }
        let original = capture.content
        let gate = NoteRepositoryTestGate()
        await fixture.repository.installTestGate(gate)
        capture.edit("Temporary edit")
        capture.closeReview()
        await gate.waitForFirstEntry()
        capture.activate()
        capture.edit(original)
        capture.closeReview()
        gate.release()
        #expect(await capture.reviewWrite?.value == true)
        #expect(try await fixture.repository.pendingVoiceDraft()?.content == original)
    }

    @Test func failedKeepRollsBackAndLeavesReviewAvailableForRetry() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let capture = fixture.capture()
        capture.activate()
        try await wait { capture.phase == .listening }
        capture.finish()
        try await wait { capture.phase == .reviewing }
        let queue = try DatabaseQueue(path: fixture.database.path)
        defer { try? queue.close() }
        try await queue.write { db in
            try db.execute(sql: """
                CREATE TRIGGER fail_voice_delete BEFORE DELETE ON voice_review
                BEGIN SELECT RAISE(ABORT, 'injected'); END
                """)
        }
        capture.keep()
        try await wait { capture.phase == .reviewing }
        #expect(capture.reviewMessage?.contains("couldn’t keep") == true)
        #expect(try await fixture.repository.fetchAllNonDeleted().isEmpty)
        #expect(try await fixture.repository.pendingVoiceDraft()?.content == capture.content)
        capture.cancel()
        try await wait { capture.phase == .reviewing }
        #expect(capture.reviewMessage?.contains("couldn’t discard") == true)
        try await queue.write { db in try db.execute(sql: "DROP TRIGGER fail_voice_delete") }
        capture.keep()
        try await wait { capture.phase == .kept }
        #expect(try await fixture.repository.fetchAllNonDeleted().count == 1)
    }

    @Test func repositoryScopesRecoveryAndUndo() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let draft = VoiceDraft(id: UUID(), content: "No deploy today.")
        let other = VoiceDraft(id: UUID(), content: "Unrelated")
        let repository = fixture.repository
        try await repository.stageVoiceDraft(draft)
        await #expect(throws: NoteRepository.PersistenceError.staleContent) {
            try await repository.stageVoiceDraft(other)
        }
        try await repository.discardVoiceDraft(id: other.id)
        #expect(try await repository.pendingVoiceDraft() == draft)
        let kept = try await repository.keepVoiceDraft(draft)
        #expect(try await repository.keepVoiceDraft(draft) == kept)
        try await repository.update(id: kept.id, content: "Edited independently.")
        await #expect(throws: NoteRepository.PersistenceError.staleContent) {
            try await repository.undoVoiceKeep(kept)
        }
        #expect(try await repository.fetch(id: kept.id)?.content == "Edited independently.")
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

    @Test func nativeStatusIsNonKeyAndVoiceViewsRenderInBothAppearances() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let capture = fixture.capture()
        let windows = VoiceCaptureWindows(capture: capture)
        defer { windows.hide() }
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
        capture.finish()
        try await wait { capture.phase == .reviewing }
        windows.rememberFinishContext(.init(application: 100, keyWindow: nil))
        windows.showReviewAfterFinish(in: .init(application: 200, keyWindow: nil))
        #expect(status.isVisible)
        #expect(app.keyWindow === keyWindow)
        windows.hideStatus()
        for scheme in [ColorScheme.light, .dark] {
            try HomeSnapshotTests().renderPNG(VoiceReviewView(capture: capture), width: 454, height: 304,
                                              scheme: scheme, name: "voice-review-\(scheme)")
        }
        capture.keep()
        try await wait { capture.phase == .kept }
        for scheme in [ColorScheme.light, .dark] {
            try HomeSnapshotTests().renderPNG(VoiceStatusView(capture: capture), width: 304, height: 70,
                                              scheme: scheme, name: "voice-kept-\(scheme)")
        }
        capture.cancel()
    }

    private func wait(until predicate: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(4))
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
            decode: @escaping @Sendable (VoiceAudio) async throws -> String = { _ in "Talvez não fazer o deploy ainda." }
        ) -> VoiceCapture {
            let defaults = UserDefaults(suiteName: suite)!
            defaults.set(enabled, forKey: VoiceCapture.preferenceKey)
            let capture = VoiceCapture(
                preferences: defaults, supported: true,
                input: .init(
                    authorization: { authorization },
                    requestAccess: { await input.request() },
                    start: { id, route in await input.start(id, audible: audible, route: route) },
                    stop: { id in await input.stop(id) }
                ),
                presentWindows: false, decode: decode
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

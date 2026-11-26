import Foundation

@MainActor
enum StudyValidation {
    enum Failure: LocalizedError {
        case check(String)
        var errorDescription: String? {
            if case let .check(name) = self { return name }
            return nil
        }
    }

    static func require(_ condition: Bool, _ name: String) throws {
        guard condition else { throw Failure.check(name) }
    }

    static func wait(_ name: String, until condition: () async -> Bool) async throws {
        for _ in 0..<430 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw Failure.check("Timed out waiting for \(name)")
    }

    static func run() async {
        let folder = FileManager.default.temporaryDirectory.appending(path: "voice-validation-\(UUID())")
        let input = StudyFixture()
        let session = StudySession(folder: folder, fixture: input, timeout: .milliseconds(400))
        let signal = (0..<4300).map { Float(0.15 * sin(Double($0) * 0.05)) }
        var clockwork: [[String: Double]] = []
        var assertions: [String] = []
        func passed(_ name: String) { assertions.append(name); print("PASS \(name)") }

        func openedInput() async throws {
            try await wait("input opened") { await input.activity().active }
        }

        func startListening() async throws {
            session.start()
            try await openedInput()
            await input.send(signal)
            try await wait("Listening") { session.phase == .listening }
        }

        func finishToReview() async throws {
            session.finish()
            try await wait("Review") { session.phase == .review }
        }

        do {
            defer { try? FileManager.default.removeItem(at: folder) }
            await session.load()
            try require(session.storageReady && session.assetReady, "isolated DB and signed assets")
            session.showingOptions = true
            session.start()
            try require(await input.activity().starts == 0 && session.phase == .idle && session.optionsEnabled,
                        "capture allowed behind Options")
            session.showingOptions = false
            session.editingKeptThought = true
            session.start()
            try require(await input.activity().starts == 0 && session.phase == .idle, "capture allowed behind editor")
            session.editingKeptThought = false
            await input.setAuthorization(.notDetermined)
            session.start()
            try await wait("microphone denial") { session.phase == .recovery(.permissionDenied) }
            try require(await input.activity().starts == 0, "mic opened after denial")
            await input.setAuthorization(.notDetermined, response: true)
            session.start()
            try await wait("first grant returns to ready") { session.phase == .idle }
            try require(await input.activity().starts == 0, "mic opened during grant")
            await input.setAuthorization(.denied)
            session.start()
            try await wait("revoked authorization") { session.phase == .recovery(.permissionDenied) }
            await input.setAuthorization(.authorized)
            await session.checkModel()
            try require(session.phase == .idle && session.notice == "Microphone access restored.", "permission recovery")
            passed("modal keyboard containment, first grant, deny, revoke and restore open no unauthorized input")

            session.selectedEngine = .apple
            session.language = "qaa-ZZ"
            session.start()
            try await wait("unsupported speech setup") { session.phase == .recovery(.setup) }
            try require(await input.activity().starts == 0, "unavailable model opened the microphone")
            session.selectedEngine = .fluid
            session.language = "pt-BR"
            await session.checkModel()
            passed("unavailable language is routed to speech setup before microphone input")

            let sentinel = "Unfinished scratch retained."
            session.draft = sentinel
            session.saveDraft(sentinel)
            try await Task.sleep(for: .milliseconds(270))
            session.start()
            try await openedInput()
            try require(session.phase == .starting, "Listening before first frame")
            await input.send(signal)
            try await wait("Listening") { session.phase == .listening }
            session.finish()
            try require(session.phase == .ending, "explicit tail state")
            try await Task.sleep(for: .milliseconds(40))
            await input.send(signal)
            try await wait("Review") { session.phase == .review }
            let submitted = await input.submittedCount
            try require(submitted == 2 * signal.count, "post-Finish boundary tail")
            try require(await !input.activity().active, "review releases input")
            passed("readiness uses first frame, bounded Finish tail includes the ending, input released")

            session.edited = "Do not deploy yet."
            try await session.injectStoreFailure(true)
            session.keep()
            session.keep()
            try await wait("write failure") { session.phase == .recovery(.save) }
            try require(session.receipt == nil && session.notes.isEmpty && session.edited == "Do not deploy yet.",
                        "receipt before failed commit or text lost")
            try await session.injectStoreFailure(false)
            try await session.injectDiscardFailure(true)
            session.keep()
            try await wait("atomic Keep rolls back") { session.phase == .recovery(.save) }
            let rollbackCheck = StudySession(folder: folder)
            await rollbackCheck.load()
            try require(rollbackCheck.notes.isEmpty && rollbackCheck.phase == .review, "keep committed without journal cleanup")
            try await session.injectDiscardFailure(false)
            session.keep()
            session.keep()
            try await wait("Kept") { session.phase == .kept }
            try require(session.notes.count == 1 && session.draft == sentinel, "duplicate or scratch changed")
            clockwork.append(session.metrics)
            let first = try requireReceipt(session)
            try require(first.content == "Do not deploy yet.", "wrong saved text")
            passed("real SQLite failure preserves editable text, duplicate Keep is idempotent, success follows commit")

            let reopened = StudySession(folder: folder)
            await reopened.load()
            try require(reopened.notes.count == 1 && reopened.draft == sentinel, "kept result or scratch missing after reopening")
            session.openReceipt()
            try require(session.opened?.id == first.id, "open wrong thought")
            let editOK = await session.editThought(first, text: "Actually, deploy Monday.")
            try require(editOK && session.opened?.content == "Actually, deploy Monday.", "edit durable")
            session.undo()
            try await wait("protected Undo") { session.notice?.contains("can’t be undone") == true }
            try require(session.notes.count == 1, "undo overwrote later edit")
            passed("reopen durable note and unchanged scratch, edit commits, guarded Undo protects later edit")

            session.completion = .receipt
            try await startListening()
            session.finish()
            session.finish()
            try await wait("automatic Keep") { session.phase == .kept }
            clockwork.append(session.metrics)
            try require(session.notes.count == 2, "double Finish duplicated")
            let second = try requireReceipt(session)
            try require(second.id != first.id, "reused note")
            session.undo()
            try await wait("Undo") { session.notes.count == 1 && session.canStart }
            try require(session.notes.first?.id == first.id, "Undo affected another note")
            passed("automatic Keep commits once and Undo affects only the captured thought")

            try await session.injectStoreFailure(true)
            try await startListening()
            session.finish()
            try await wait("failed automatic Keep") { session.phase == .recovery(.save) }
            let automaticRecovery = StudySession(folder: folder)
            await automaticRecovery.load()
            try require(automaticRecovery.phase == .review && !automaticRecovery.edited.isEmpty
                        && automaticRecovery.notes.count == 1, "failed automatic Keep was not recoverable after relaunch")
            try await session.injectStoreFailure(false)
            session.cancel()
            try await wait("discard failed automatic Keep") { session.canStart }
            passed("failed automatic Keep stages recoverable text when the store permits")

            session.completion = .review
            try await startListening()
            try await finishToReview()
            try await session.injectDiscardFailure(true)
            session.cancel()
            try await wait("retryable discard failure") { session.phase == .review && session.notice?.contains("couldn’t be discarded") == true }
            try require(!session.raw.isEmpty && session.notes.count == 1, "text lost after failed discard")
            try await session.injectDiscardFailure(false)
            session.cancel()
            try await wait("durably discarded") { session.canStart }
            let afterFailedDiscard = StudySession(folder: folder)
            await afterFailedDiscard.load()
            try require(afterFailedDiscard.phase == .idle && afterFailedDiscard.notes.count == 1, "retry left stale recovery")
            session.completion = .receipt
            passed("discard failure preserves review, retry clears the recovery journal without affecting Kept data")

            session.start()
            try await openedInput()
            await input.send(Array(repeating: 0, count: 6000))
            try await wait("silent input ready") { session.phase == .listening }
            session.finish()
            try await wait("silence") { session.phase == .silent }
            try require(session.notes.count == 1, "silence created note")
            session.start()
            try await openedInput()
            var click = Array(repeating: Float.zero, count: 6000)
            click[80] = 1
            await input.send(click)
            try await wait("click input ready") { session.phase == .listening }
            session.finish()
            try await wait("click suppressed") { session.phase == .silent }
            try require(session.notes.count == 1, "click created note")
            passed("digital silence and click-only activation create no note")

            await input.setInputFailure(true)
            session.start()
            try await wait("input failure") { session.phase == .recovery(.microphone) }
            try require(session.canStart && session.notes.count == 1, "input failure blocks retry or changed note")
            await input.setInputFailure(false)
            try await startListening()
            await input.disconnect()
            try await wait("interruption recovery") { session.phase == .review }
            try require(session.notes.count == 1 && session.notice?.contains("ended early") == true,
                        "capture interruption kept without review")
            session.cancel()
            try await wait("cancel interruption") { session.canStart }
            try await startListening()
            session.interrupt()
            try await wait("sleep handler recovery") { session.phase == .review }
            session.cancel()
            try await wait("cancel sleep recovery") { session.canStart }
            passed("input error can retry, audio route loss and sleep handler send partial speech to review")

            try await startListening()
            try await wait("stalled input") { session.phase == .review }
            try require(await !input.activity().active, "stalled input remained open")
            session.cancel()
            try await wait("cancel stall recovery") { session.canStart }
            let blocked = MicBuffer(rate: 16000)
            (signal + [.nan, .infinity]).withUnsafeBufferPointer { blocked.append($0) }
            let sealed = blocked.audio()
            signal.withUnsafeBufferPointer { blocked.append($0) }
            let clean = try sealed.mono16k()
            try require(blocked.status().count == signal.count + 2 && clean.allSatisfy(\.isFinite),
                        "audio snapshot accepted late packets or invalid frames")
            passed("stalled input preserves partial speech, stop seals buffers and normalizes invalid samples")

            await input.setRecognition(.fail)
            try await startListening()
            session.finish()
            try await wait("recognition failure") { session.canRetry }
            await input.setRecognition(.result("Don’t deploy yet."))
            session.retryTranscription()
            session.retryTranscription()
            try await wait("kept on retry") { session.phase == .kept }
            try require(session.notes.count == 2, "recognition retry failed")
            session.undo()
            try await wait("undo retried capture") { session.canStart && session.notes.count == 1 }
            passed("transcription failure holds audio for retry and retries do not duplicate")

            session.completion = .review
            await input.setRecognition(.suspended)
            try await startListening()
            session.finish()
            try await wait("suspended recognizer") { await input.activity().pending == 1 }
            session.cancel()
            try await wait("can capture after cancel") { session.canStart }
            await input.setRecognition(.result("Use a new branch."))
            try await startListening()
            try await finishToReview()
            await input.deliverLate("Superseded transcript.")
            try await Task.sleep(for: .milliseconds(25))
            try require(session.raw == "Use a new branch.", "late result replaced new transcript")
            session.cancel()
            try await wait("cancel review") { session.canStart }
            passed("cancellation remains responsive and late recognizer cannot mutate newer capture")

            await input.setRecognition(.suspended)
            try await startListening()
            session.finish()
            try await wait("recognition timeout") { session.phase == .recovery(.timeout) }
            await input.setRecognition(.result("Keep the current branch."))
            session.retryTranscription()
            try await wait("retried timeout") { session.phase == .review }
            await input.deliverLate("Ever-late transcript.")
            try require(session.raw == "Keep the current branch.", "timeout result won retry race")
            session.edited = "Keep the current branch for now."
            session.saveReviewEdit()
            try await Task.sleep(for: .milliseconds(270))
            let recovered = StudySession(folder: folder)
            await recovered.load()
            try require(recovered.phase == .review && recovered.raw == "Keep the current branch."
                        && recovered.edited == "Keep the current branch for now." && !recovered.hasAudio,
                        "relaunch recovery changed recognized or edited text")
            session.cancel()
            try await wait("discard recovered journal") { session.canStart }
            let afterDiscard = StudySession(folder: folder)
            await afterDiscard.load()
            try require(afterDiscard.phase == .idle, "discarded text present after relaunch")
            passed("recognition timeout, same-session retry race, crash-style transcript recovery, explicit discard")

            session.globalShortcut = true
            session.activation = .hold
            session.shortcutDown()
            session.shortcutDown()
            try await openedInput()
            session.shortcutUp()
            try await wait("early release") { session.phase == .silent }
            try require(session.notes.count == 1, "early release saved")
            session.activation = .toggle
            session.shortcutDown()
            session.shortcutDown()
            try await openedInput()
            await input.send(signal)
            try await wait("toggle listening") { session.phase == .listening }
            session.shortcutUp()
            try require(session.phase == .listening, "toggle finished on release")
            session.shortcutDown()
            session.shortcutDown()
            session.shortcutUp()
            try await wait("toggle finished") { session.phase == .review }
            session.cancel()
            try await wait("toggle reset") { session.canStart }
            passed("shortcut handler rejects repeated down events, hold early release and toggle edges behave")

            let prior = await input.activity()
            for _ in 0..<120 {
                try await startListening()
                session.cancel()
                try await wait("rapid cancel settled") { session.canStart }
            }
            let after = await input.activity()
            try require(after.starts - prior.starts == 120 && after.stops - prior.stops == 120
                        && !after.active && after.pending == 0 && session.notes.count == 1,
                        "orphaned resources or notes after 120 cancellation cycles")
            passed("120 repeated capture/cancel cycles leave no owned test input, task or extra note")

            session.completion = .receipt
            session.logTimings = true
            try await startListening()
            session.finish()
            try await wait("timed Keep") { session.phase == .kept }
            session.exportTranscriptComparison()
            session.saveDraft("Pending draft during reset.")
            session.resetStudyData()
            try await wait("study reset") { session.canStart && session.notes.isEmpty && session.draft.isEmpty }
            let reset = StudySession(folder: folder)
            await reset.load()
            try require(reset.notes.isEmpty && reset.draft.isEmpty &&
                        !FileManager.default.fileExists(atPath: folder.appending(path: "Evaluation").path),
                        "reset did not drain queued file writes")
            passed("reset drains queued recovery and export writes before clearing the isolated study data")

            let probeFolder = folder.appending(path: "real-recognition")
            let liveRecognition = StudySession(folder: probeFolder)
            await liveRecognition.load()
            if let file = Bundle.main.resourceURL?.appending(path: "en-clip.wav") {
                try await liveRecognition.exerciseSynthetic(try LocalBenchmark.loadFixture(file))
            }
            passed("signed sandbox actually decodes with Apple Speech, reviews, keeps and undoes")

            LocalBenchmark.output(["assertions": assertions.count, "fixture_latency": clockwork,
                                   "input_starts": after.starts, "input_stops": after.stops])
            exit(0)
        } catch {
            print("FAIL \(error.localizedDescription)")
            exit(1)
        }
    }

    private static func requireReceipt(_ session: StudySession) throws -> Note {
        guard let note = session.receipt else { throw Failure.check("missing receipt") }
        return note
    }
}

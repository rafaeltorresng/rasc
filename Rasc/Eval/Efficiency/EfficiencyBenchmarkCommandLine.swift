#if RASC_EFFICIENCY_BENCHMARK
import AppKit
import AVFoundation
import CoreGraphics
import Foundation
import OSLog

/// Opt-in Release workload harness for long-running resource & latency evaluation.
/// Compiled ONLY when `RASC_EFFICIENCY_BENCHMARK` is explicitly passed in `OTHER_SWIFT_FLAGS`.
/// Shipping Debug and Release builds exclude this file completely.
@MainActor
enum EfficiencyBenchmarkCommandLine {
    static let launchArgument = "--run-efficiency-bench"

    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains(launchArgument)
    }

    static func prepareBeforeOnboardingIfRequested() {
        guard isRequested else { return }
        OnboardingStore().markCompleted()
    }

    static func scheduleRun(bootstrap: AppBootstrap) {
        guard isRequested else { return }
        Task { @MainActor in
            let code = await execute(bootstrap: bootstrap)
            _ = await VoiceCapture.shared.flushForTermination()
            _ = await bootstrap.awaitPanel()?.flushForTermination()
            exit(code)
        }
    }

    private struct CorpusEntry: Decodable {
        let id: String
        let audio: String
        let language: String?
        let durationSeconds: Double?
    }

    private struct PhaseMarker: Encodable {
        let timestamp: String
        let elapsedS: Double
        let phase: String
        let detail: String?
    }

    private struct OpTiming: Encodable {
        let phase: String
        let op: String
        let iteration: Int
        let durationMs: Double
        let detail: String?
    }

    private struct BenchmarkSummary: Encodable {
        let bundleIdentifier: String
        let isSandboxed: Bool
        let homeRedacted: String
        let noteCountAtEnd: Int
        let refineAvailability: String
        let refineExecuted: Int
        let voiceColdPrepareMs: Double
        let voiceWarmPrepareMs: Double
        let voicePostSleepReprepareMs: Double
        let totalElapsedS: Double
        let ops: [String: OpSummary]
    }

    private struct OpSummary: Encodable {
        let count: Int
        let p50Ms: Double
        let p95Ms: Double
        let meanMs: Double
        let maxMs: Double
    }

    private static func benchRootURL() throws -> URL {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return appSupport.appending(path: "Rasc/EfficiencyBench", directoryHint: .isDirectory)
    }

    private static func execute(bootstrap: AppBootstrap) async -> Int32 {
        do {
            let root = try benchRootURL()
            let fixturesDir = root.appending(path: "fixtures", directoryHint: .isDirectory)
            let outputDir = root.appending(path: "output", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

            let phaseURL = outputDir.appending(path: "phases.jsonl")
            let opsURL = outputDir.appending(path: "ops.jsonl")
            FileManager.default.createFile(atPath: phaseURL.path, contents: nil)
            FileManager.default.createFile(atPath: opsURL.path, contents: nil)
            let phaseHandle = try FileHandle(forWritingTo: phaseURL)
            let opsHandle = try FileHandle(forWritingTo: opsURL)
            defer {
                try? phaseHandle.close()
                try? opsHandle.close()
            }

            let startedAt = ContinuousClock.now
            let encoder = JSONEncoder()

            func markPhase(_ phase: String, _ detail: String? = nil) {
                let marker = PhaseMarker(
                    timestamp: Date.ISO8601FormatStyle().format(Date()),
                    elapsedS: sec(startedAt.duration(to: .now)),
                    phase: phase,
                    detail: detail
                )
                if let data = try? encoder.encode(marker) {
                    phaseHandle.write(data)
                    phaseHandle.write(Data("\n".utf8))
                }
            }

            var recordedOps: [OpTiming] = []
            func recordOp(phase: String, op: String, iteration: Int, durationMs: Double, detail: String? = nil) {
                let row = OpTiming(phase: phase, op: op, iteration: iteration, durationMs: durationMs, detail: detail)
                recordedOps.append(row)
                if let data = try? encoder.encode(row) {
                    opsHandle.write(data)
                    opsHandle.write(Data("\n".utf8))
                }
            }

            guard let panel = await bootstrap.awaitPanel() else {
                markPhase("error", "bootstrap failed")
                return 1
            }

            // Phase 1: Seed 100 realistic notes & measure idle with Voice disabled (30s)
            markPhase("seed_and_idle_voice_off", "seeding 100 notes then 30s idle")
            VoiceCapture.shared.setEnabled(false)
            if bootstrap.homeIsVisible { await bootstrap.toggleHome() }
            if panel.panel.isVisible { await panel.hide() }

            let seedStart = ContinuousClock.now
            for idx in 0..<100 {
                let text = "Thought #\(idx): evaluate long-running standby footprint, FTS5 retrieval, and autosave durability on macOS (\(idx % 5 == 0 ? "kept candidate" : "draft"))."
                let note = try await panel.repository.createScratch(content: text)
                if idx % 5 == 0 {
                    _ = try? await panel.repository.keep(id: note.id)
                }
            }
            recordOp(phase: "seed_and_idle_voice_off", op: "seed_100_notes", iteration: 1, durationMs: ms(seedStart.duration(to: .now)))
            try await Task.sleep(for: .seconds(30))

            // Phase 2: Scratchpad Capture -> Edit -> Autosave -> Keep/Park loop (30 cycles)
            markPhase("scratchpad_capture_loop", "30 capture/edit/flush/keep-or-park cycles")
            for idx in 0..<30 {
                let t0 = ContinuousClock.now
                await panel.startNewScratch()
                panel.scratchpadSession.text = "Captured thought cycle \(idx): verify NSWindow level policy and TextKit autosave without retaining stale views."
                try? await panel.scratchpadSession.flush()
                if idx % 3 == 0 {
                    await panel.keepActiveNote()
                } else {
                    await panel.hide()
                }
                recordOp(phase: "scratchpad_capture_loop", op: "scratchpad_cycle", iteration: idx, durationMs: ms(t0.duration(to: .now)))
            }
            if panel.panel.isVisible { await panel.hide() }

            // Phase 3: Home Open + FTS5 Search + Close loop (20 cycles)
            markPhase("home_search_loop", "20 open Home + search + close cycles")
            let queries = ["footprint", "autosave", "kept candidate", "durability", "macOS"]
            for idx in 0..<20 {
                let tOpen = ContinuousClock.now
                await bootstrap.openHome()
                recordOp(phase: "home_search_loop", op: "home_open", iteration: idx, durationMs: ms(tOpen.duration(to: .now)))

                if let homeSession = bootstrap.benchmarkHomeController?.benchmarkSession {
                    let tSearch = ContinuousClock.now
                    homeSession.searchQuery = queries[idx % queries.count]
                    await homeSession.reloadImmediately()
                    recordOp(
                        phase: "home_search_loop",
                        op: "home_search",
                        iteration: idx,
                        durationMs: ms(tSearch.duration(to: .now)),
                        detail: "results=\(homeSession.searchResults.count)"
                    )
                    homeSession.searchQuery = ""
                    await homeSession.reloadImmediately()
                }

                let tClose = ContinuousClock.now
                if bootstrap.homeIsVisible {
                    await bootstrap.toggleHome()
                }
                recordOp(phase: "home_search_loop", op: "home_close", iteration: idx, durationMs: ms(tClose.duration(to: .now)))
            }

            // Phase 4: Home Batch Ops (multi-select copy + transactional discard + Undo) (10 cycles)
            markPhase("home_batch_ops", "10 batch select/copy/discard/undo cycles")
            let undoManager = UndoManager()
            await bootstrap.openHome()
            if let homeSession = bootstrap.benchmarkHomeController?.benchmarkSession {
                await homeSession.reloadImmediately()
                for idx in 0..<10 {
                    let t0 = ContinuousClock.now
                    let subset = Set(homeSession.displayedNotes.prefix(12).map(\.id))
                    for id in subset { homeSession.toggleSelection(id) }
                    _ = try? await homeSession.batchCopyPayload()
                    let receipts = try await homeSession.discardSelected(undoManager: undoManager)
                    await homeSession.undoDiscardBatch(receipts)
                    homeSession.clearSelection()
                    recordOp(
                        phase: "home_batch_ops",
                        op: "home_batch_copy_discard_undo",
                        iteration: idx,
                        durationMs: ms(t0.duration(to: .now)),
                        detail: "notes=\(subset.count)"
                    )
                }
            }
            if bootstrap.homeIsVisible { await bootstrap.toggleHome() }

            // Phase 5: Voice Capture & Dictate with real FLEURS audio (15 clips) + 30s warm idle
            markPhase("voice_capture_and_dictate", "15 real FLEURS clips + 30s warm idle")
            let corpusURL = fixturesDir.appending(path: "manifest.json")
            let entries = try JSONDecoder().decode([CorpusEntry].self, from: Data(contentsOf: corpusURL))

            let benchModel = VoiceModel(retention: nil)
            await benchModel.release()
            let tCold = ContinuousClock.now
            try await benchModel.prepare()
            let voiceColdPrepareMs = ms(tCold.duration(to: .now))
            let tWarm = ContinuousClock.now
            try await benchModel.prepare()
            let voiceWarmPrepareMs = ms(tWarm.duration(to: .now))

            let benchPasteboard = NSPasteboard.withUniqueName()
            defer { benchPasteboard.releaseGlobally() }

            for idx in 0..<15 {
                let entry = entries[idx % entries.count]
                let wavURL = fixturesDir.appending(path: entry.audio)
                let (samples, rate) = try readMonoFloat(at: wavURL)
                let audio = VoiceAudio(
                    samples: samples,
                    rate: rate,
                    peak: 0.9,
                    activitySeconds: Double(samples.count) / rate
                )
                let t0 = ContinuousClock.now
                let transcript = try await benchModel.transcribe(audio, modelReady: {})
                let elapsedMs = ms(t0.duration(to: .now))
                if idx % 2 == 0 {
                    // Voice to Scratchpad persistence flow
                    _ = try await panel.repository.createScratch(content: transcript)
                } else {
                    // Dictate defaults: clipboard + local copy in Rasc
                    VoiceTextInsertion.copy(transcript, to: benchPasteboard)
                    _ = try await panel.repository.createScratch(content: transcript)
                }
                recordOp(
                    phase: "voice_capture_and_dictate",
                    op: idx % 2 == 0 ? "voice_scratchpad_transcribe" : "voice_dictate_transcribe",
                    iteration: idx,
                    durationMs: elapsedMs,
                    detail: entry.id
                )
            }
            // Hand single model ownership cleanly to VoiceCapture.shared for idle & sleep tests
            await benchModel.release()
            VoiceCapture.shared.setEnabled(true)
            VoiceCapture.shared.checkSetup(prepare: true)
            for _ in 0..<240 where VoiceCapture.shared.setup == .preparing || VoiceCapture.shared.setup == .unchecked {
                try await Task.sleep(for: .milliseconds(100))
            }
            try await Task.sleep(for: .seconds(30))

            // Phase 6: On-device Refine evaluation (if Apple Intelligence is available)
            markPhase("refine_on_device", "checking Apple Foundation Models availability")
            let refineProvider = FoundationModelsRefinementProvider()
            let probeReq = RefinementRequest(
                snapshot: NoteSnapshot(noteID: UUID(), revision: 1, text: "preciso revisar o pr da eficiencia amanha cedo antes da daily")
            )
            let availability = await refineProvider.availability(for: probeReq)
            var refineExecuted = 0
            if availability == .available {
                for idx in 0..<6 {
                    let req = RefinementRequest(
                        snapshot: NoteSnapshot(
                            noteID: UUID(),
                            revision: idx + 1,
                            text: "talvez conversar com o rafael sobre metricas \(idx): mem footprint 63 mb, cpu idle 0.0%, confirmar amanha"
                        )
                    )
                    let t0 = ContinuousClock.now
                    _ = try? await refineProvider.refine(req)
                    refineExecuted += 1
                    recordOp(phase: "refine_on_device", op: "refine_invoke", iteration: idx, durationMs: ms(t0.duration(to: .now)))
                }
            }

            // Phase 7: Sleep / Wake & Memory Pressure model release + re-preparation
            markPhase("sleep_wake_and_memory_pressure", "trigger willSleep/pressure release then didWake re-prepare")
            NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
            try await Task.sleep(for: .seconds(5))
            let tReprepare = ContinuousClock.now
            NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
            for _ in 0..<240 {
                try await Task.sleep(for: .milliseconds(100))
                if VoiceCapture.shared.setup == .installed && VoiceCapture.shared.phase == .idle {
                    // Wait until scheduled reprepare task transitions through preparing -> installed
                    if ms(tReprepare.duration(to: .now)) > 2000 { break }
                }
            }
            let voicePostSleepReprepareMs = ms(tReprepare.duration(to: .now))
            recordOp(phase: "sleep_wake_and_memory_pressure", op: "sleep_wake_cycle", iteration: 0, durationMs: voicePostSleepReprepareMs)

            // Ensure single model ownership again during mixed endurance transcribes
            VoiceCapture.shared.handleResourceConstraint()
            try await Task.sleep(for: .milliseconds(250))

            // Phase 8: Compressed workday endurance loop (60 mixed cycles across 4 rounds + hidden event checks)
            markPhase("workday_endurance_loop", "4 rounds x mixed capture/search/batch/voice + hidden workspace & modifier stress")
            let modifierMonitor = ModifierShortcutMonitor()
            modifierMonitor.start(bindings: [.option: {}])
            defer { modifierMonitor.stop() }

            let enduranceModel = VoiceModel(retention: nil)
            try await enduranceModel.prepare()

            for round in 0..<4 {
                if round > 0 {
                    markPhase("workday_endurance_loop", "round \(round) active")
                }
                for step in 0..<15 {
                    let iter = round * 15 + step

                    // 1) Hidden app switching notification burst (panel hidden)
                    for _ in 0..<2 {
                        NSWorkspace.shared.notificationCenter.post(
                            name: NSWorkspace.didActivateApplicationNotification,
                            object: nil
                        )
                    }

                    // 2) Scroll-wheel noise while modifier monitor is armed (no modifier held)
                    if let scrollCG = CGEvent(
                        scrollWheelEvent2Source: nil,
                        units: .pixel,
                        wheelCount: 1,
                        wheel1: -8,
                        wheel2: 0,
                        wheel3: 0
                    ), let scrollNSEvent = NSEvent(cgEvent: scrollCG) {
                        for _ in 0..<15 {
                            modifierMonitor.benchmarkProcess(scrollNSEvent)
                        }
                    }

                    // 3) Scratchpad capture/park
                    let tCap = ContinuousClock.now
                    await panel.startNewScratch()
                    panel.scratchpadSession.text = "Workday round \(round) step \(step): quick capture and return to IDE."
                    try? await panel.scratchpadSession.flush()
                    if step % 5 == 0 {
                        await panel.keepActiveNote()
                    } else {
                        await panel.hide()
                    }
                    recordOp(phase: "workday_endurance_loop", op: "endurance_scratchpad", iteration: iter, durationMs: ms(tCap.duration(to: .now)))

                    // 4) Periodic Home open/search/close & batch copy/discard/undo
                    if step % 3 == 0 {
                        let tHome = ContinuousClock.now
                        await bootstrap.openHome()
                        if let hs = bootstrap.benchmarkHomeController?.benchmarkSession {
                            hs.searchQuery = "Workday"
                            await hs.reloadImmediately()
                            if step == 6 {
                                let ids = Set(hs.displayedNotes.prefix(8).map(\.id))
                                for id in ids { hs.toggleSelection(id) }
                                _ = try? await hs.batchCopyPayload()
                                let receipts = try await hs.discardSelected(undoManager: undoManager)
                                await hs.undoDiscardBatch(receipts)
                                hs.clearSelection()
                            }
                            hs.searchQuery = ""
                        }
                        if bootstrap.homeIsVisible { await bootstrap.toggleHome() }
                        recordOp(phase: "workday_endurance_loop", op: "endurance_home_cycle", iteration: iter, durationMs: ms(tHome.duration(to: .now)))
                    }

                    // 5) Periodic real Voice transcription (5 per round = 20 total)
                    if step % 3 == 0 {
                        let entry = entries[(iter / 3) % entries.count]
                        let (samples, rate) = try readMonoFloat(at: fixturesDir.appending(path: entry.audio))
                        let audio = VoiceAudio(samples: samples, rate: rate, peak: 0.9, activitySeconds: Double(samples.count) / rate)
                        let tV = ContinuousClock.now
                        let text = try await enduranceModel.transcribe(audio, modelReady: {})
                        _ = try await panel.repository.createScratch(content: text)
                        recordOp(phase: "workday_endurance_loop", op: "endurance_voice", iteration: iter, durationMs: ms(tV.duration(to: .now)))
                    }
                }
                // Brief inter-round workday pause (10s)
                if round < 3 {
                    markPhase("workday_endurance_pause", "round \(round) settle")
                    try await Task.sleep(for: .seconds(10))
                }
            }

            await enduranceModel.release()
            modifierMonitor.stop()
            VoiceCapture.shared.scheduleReprepareAfterConstraint(delay: .milliseconds(100))
            try await Task.sleep(for: .seconds(5))

            // Post-workload cooldown idle (60s) to measure resource reclamation & leaks
            markPhase("post_workload_cooldown", "60s settled idle with Home closed and Panel hidden")
            if bootstrap.homeIsVisible { await bootstrap.toggleHome() }
            if panel.panel.isVisible { await panel.hide() }
            try await Task.sleep(for: .seconds(60))

            let finalNotes = try await panel.repository.fetchAllNonDeleted().count
            markPhase("cooldown_done", "notes=\(finalNotes); awaiting external footprint/leaks")
            try await Task.sleep(for: .seconds(5))

            // Aggregate per-op latencies
            var grouped: [String: [Double]] = [:]
            for item in recordedOps {
                grouped[item.op, default: []].append(item.durationMs)
            }
            let opSummaries = grouped.mapValues { values -> OpSummary in
                let sorted = values.sorted()
                let p50 = sorted[(sorted.count - 1) / 2]
                let p95 = sorted[min(sorted.count - 1, Int((Double(sorted.count) * 0.95).rounded(.up)) - 1)]
                let mean = sorted.reduce(0, +) / Double(max(1, sorted.count))
                return OpSummary(count: sorted.count, p50Ms: p50, p95Ms: p95, meanMs: mean, maxMs: sorted.last ?? 0)
            }

            let home = NSHomeDirectory()
            let homeRedacted = home.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")
            let summary = BenchmarkSummary(
                bundleIdentifier: Bundle.main.bundleIdentifier ?? "unknown",
                isSandboxed: home.contains("/Library/Containers/"),
                homeRedacted: homeRedacted,
                noteCountAtEnd: finalNotes,
                refineAvailability: String(describing: availability),
                refineExecuted: refineExecuted,
                voiceColdPrepareMs: voiceColdPrepareMs,
                voiceWarmPrepareMs: voiceWarmPrepareMs,
                voicePostSleepReprepareMs: voicePostSleepReprepareMs,
                totalElapsedS: sec(startedAt.duration(to: .now)),
                ops: opSummaries
            )
            try encoder.encode(summary).write(to: outputDir.appending(path: "summary.json"))

            markPhase("exiting", "done")
            return 0
        } catch {
            FileHandle.standardError.write(Data("efficiency bench error: \(error)\n".utf8))
            return 1
        }
    }

    private static func readMonoFloat(at url: URL) throws -> ([Float], Double) {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let frames = AVAudioFrameCount(file.length)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else {
            throw VoiceAudioIssue.conversion
        }
        try file.read(into: buffer)
        let count = Int(buffer.frameLength)
        let channels = Int(format.channelCount)
        var mono = [Float](repeating: 0, count: count)
        if let data = buffer.floatChannelData {
            for frame in 0..<count {
                var sum: Float = 0
                for channel in 0..<channels { sum += data[channel][frame] }
                mono[frame] = sum / Float(max(1, channels))
            }
        }
        return (mono, format.sampleRate)
    }

    private static func ms(_ duration: Duration) -> Double {
        (Double(duration.components.seconds) * 1000) + (Double(duration.components.attoseconds) / 1_000_000_000_000_000)
    }

    private static func sec(_ duration: Duration) -> Double {
        Double(duration.components.seconds) + (Double(duration.components.attoseconds) / 1_000_000_000_000_000_000)
    }
}
#endif

import CoreML
import Darwin
import FluidAudio
import Foundation

extension LocalBenchmark {
    static func profile(_ args: [String]) async {
        guard args.count == 5, let engine = StudyEngine(rawValue: args[0]),
              engine != .apple, let unit = ModelCompute(rawValue: args[1]),
              let iterations = Int(args[2]), (1...50).contains(iterations),
              let pause = Int(args[3]), pause >= 0,
              let file = Bundle.main.resourceURL?.appending(path: args[4]) else { exit(2) }
        do {
            let asset = try PortableAssets.verifiedFolder(engine)
            let frames = try loadFixture(file)
            let base: [String: Any] = ["engine": engine.rawValue, "compute": unit.rawValue]
            for attempt in 1...iterations {
                let started = ContinuousClock.now
                let (models, stages) = try await PortableAssets.load(engine, at: asset, compute: unit)
                let loaded = milliseconds(started)
                let manager = AsrManager()
                let initializing = ContinuousClock.now
                try await manager.initialize(models: models)
                let initMS = milliseconds(initializing)
                let first = ContinuousClock.now
                let result = try await manager.transcribe(frames, source: .microphone)
                let firstMS = milliseconds(first)
                await manager.cleanup()
                var replays: [Double] = []
                for _ in 0..<6 {
                    let start = ContinuousClock.now
                    let next = try await StudyRecognizer.transcribe(frames, models: models)
                    guard result.text == next else { throw RecognitionIssue.noTranscript }
                    replays.append(milliseconds(start))
                }
                output(base.merging(["attempt": attempt, "stages_ms": stages, "load_ms": loaded,
                            "manager_init_ms": initMS, "first_inference_ms": firstMS, "reuse_ms": replays,
                            "footprint_bytes": footprint(), "fixture": file.lastPathComponent,
                            "transcript": result.text]) { _, new in new })
                if attempt < iterations, pause > 0 { try await Task.sleep(for: .seconds(pause)) }
            }
            exit(0)
        } catch {
            output(["error": String(describing: error)])
            exit(1)
        }
    }
}

func footprint() -> UInt64 {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
    let code = withUnsafeMutablePointer(to: &info) { pointer in
        pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
    }
    return code == KERN_SUCCESS ? info.phys_footprint : 0
}

extension LocalBenchmark {
    static func lifecycle(_ args: [String]) async {
        guard args.count == 3, let engine = StudyEngine(rawValue: args[0]), engine != .apple,
              let duration = Int(args[1]), duration >= 0, duration <= 600,
              let file = Bundle.main.resourceURL?.appending(path: args[2]) else { exit(2) }
        do {
            let frames = try loadFixture(file)
            let recognizer = StudyRecognizer()
            output(["stage": "initial", "footprint_bytes": footprint(), "cache": await recognizer.cacheState()])
            let begin = ContinuousClock.now
            try await recognizer.preparePortable(engine)
            output(["stage": "prepare", "elapsed_ms": milliseconds(begin), "footprint_bytes": footprint(),
                    "cache": await recognizer.cacheState()])
            for replay in 0..<25 {
                let start = ContinuousClock.now
                let (result, model) = try await recognizer.decode(frames, engine: engine, language: "auto")
                guard !result.isEmpty else { throw RecognitionIssue.noTranscript }
                output(["stage": "capture", "index": replay, "footprint_bytes": footprint(),
                        "decode_ms": milliseconds(start), "model_ms": model])
            }
            try await Task.sleep(for: .seconds(duration))
            output(["stage": "idle", "seconds": duration, "footprint_bytes": footprint(),
                    "cache": await recognizer.cacheState()])
            let restart = ContinuousClock.now
            let (_, model) = try await recognizer.decode(frames, engine: engine, language: "auto")
            output(["stage": "return", "footprint_bytes": footprint(), "decode_ms": milliseconds(restart),
                    "model_ms": model])
            exit(0)
        } catch {
            output(["error": error.localizedDescription])
            exit(1)
        }
    }
}

extension LocalBenchmark {
    @MainActor static func workflow(_ args: [String]) async {
        guard args.count == 4, let engine = StudyEngine(rawValue: args[0]),
              let repeats = Int(args[2]), (1...25).contains(repeats),
              let file = Bundle.main.resourceURL?.appending(path: args[3]) else { exit(2) }
        let directory = FileManager.default.temporaryDirectory.appending(path: "voice-workflow-\(UUID())")
        do {
            defer { try? FileManager.default.removeItem(at: directory) }
            let frames = try loadFixture(file)
            let fixture = StudyFixture(recognition: .actual)
            let study = StudySession(folder: directory, fixture: fixture)
            study.selectedEngine = engine
            study.language = args[1]
            study.completion = .receipt
            await study.load()
            guard study.assetReady else { throw RecognitionIssue.needsSetup }
            let scratch = "Original unfinished scratch."
            study.draft = scratch
            for index in 0..<repeats {
                study.start()
                try await StudyValidation.wait("fixture input") { await fixture.activity().active }
                let audioStart = ContinuousClock.now
                for offset in stride(from: 0, to: frames.count, by: 320) {
                    let end = min(offset + 320, frames.count)
                    try await ContinuousClock().sleep(until: audioStart.advanced(by: .seconds(Double(end) / 16000)))
                    await fixture.send(Array(frames[offset..<end]))
                }
                try await StudyValidation.wait("Listening") { study.phase == .listening }
                study.finish()
                for _ in 0..<520 where study.phase != .kept {
                    if case .recovery = study.phase { throw RecognitionIssue.noTranscript }
                    try await Task.sleep(for: .milliseconds(100))
                }
                guard study.phase == .kept, study.notes.count == index + 1,
                      study.draft == scratch, study.receipt != nil,
                      await !fixture.activity().active else { throw AudioIssue.noFrames }
                output(["engine": engine.rawValue, "trial": index+1, "metrics_ms": study.metrics,
                        "footprint_bytes": footprint(), "durable_count": study.notes.count,
                        "fixture": file.lastPathComponent])
            }
            exit(0)
        } catch {
            output(["error": error.localizedDescription])
            exit(1)
        }
    }
}

extension LocalBenchmark {
    static func verifyCachePolicy() async {
        let recognizer = StudyRecognizer(retention: .seconds(2))
        do {
            let start = ContinuousClock.now
            async let first: Void = recognizer.preparePortable(.fluid)
            async let second: Void = recognizer.preparePortable(.fluid)
            _ = try await (first, second)
            let warm = milliseconds(start)
            try await verify(await recognizer.isPrepared(.fluid), "shared prepare")
            await recognizer.cancelPreparation()
            try await verify(await recognizer.isPrepared(.fluid), "cancel keeps idle ready model")
            try await Task.sleep(for: .milliseconds(1100))
            try await recognizer.preparePortable(.fluid)
            try await Task.sleep(for: .milliseconds(1100))
            try await verify(await recognizer.isPrepared(.fluid), "stale lease cannot evict renewed model")
            await recognizer.releaseForMemoryPressure()
            try await verify(await recognizer.cacheState() == "released", "pressure unload")
            try await recognizer.preparePortable(.ultra)
            let alternate = await recognizer.isPrepared(.ultra)
            let prior = await recognizer.isPrepared(.fluid)
            try await verify(alternate && !prior, "single prepared engine")
            try await Task.sleep(for: .milliseconds(2200))
            try await verify(await recognizer.cacheState() == "released", "idle unload")
            output(["passed": 6, "shared_prepare_ms": warm, "test_retention_seconds": 2])
            exit(0)
        } catch {
            output(["error": String(describing: error)])
            exit(1)
        }
    }

    private static func verify(_ condition: Bool, _ name: String) async throws {
        guard condition else { throw CocoaError(.fileReadUnknown, userInfo: [NSLocalizedDescriptionKey: name]) }
        output(["pass": name])
    }
}

#if DEBUG
import AVFoundation
import Foundation

/// DEBUG-only, on-disk evaluation of the *actual* production voice pipeline.
///
/// Invoked as `Rasc.app/Contents/MacOS/Rasc --run-voice-evals --corpus <manifest.json> --output <dir> [--repetitions N] [--cold]`.
///
/// Uses `VoiceModel` + `VoiceAudio` exactly as the app does. No network, no
/// private data; the caller supplies an explicit corpus manifest. Emits JSONL
/// per clip and a `summary.json`, plus a `run.json` recording app version,
/// commit, machine, model revision, Core ML configuration and timings. Never
/// writes to the note database.
enum VoiceEvalCommandLine {
    static let launchArgument = "--run-voice-evals"

    static func runIfRequested() -> Bool {
        guard ProcessInfo.processInfo.arguments.contains(launchArgument) else { return false }
        Task { @MainActor in
            let status = await execute()
            exit(status)
        }
        return true
    }

    private struct CorpusEntry: Decodable {
        let id: String
        let audio: String
        let reference: String?
        let language: String?
        let category: String?
        let durationSeconds: Double?
    }

    private struct ResultRow: Encodable {
        let id: String
        let repetition: Int
        let language: String?
        let category: String?
        let reference: String?
        let transcript: String
        let audioSeconds: Double
        let inputSampleRate: Double
        let cold: Bool
        let modelLoadMs: Double
        let modelReadyMs: Double
        let initializeMs: Double
        let inferenceMs: Double
        let cleanupMs: Double
        let transcribeTotalMs: Double
        let audioLoadMs: Double
        let audioPrepareMs: Double
        let realTimeFactor: Double?
        let error: String?
    }

    @MainActor
    private static func execute() async -> Int32 {
        do {
            let args = ProcessInfo.processInfo.arguments
            func value(_ name: String) -> String? {
                guard let index = args.firstIndex(of: name), index + 1 < args.count else { return nil }
                return args[index + 1]
            }
            let corpusPath = try requireValue(value("--corpus"), "--corpus required")
            let output = URL(fileURLWithPath: value("--output") ?? FileManager.default.temporaryDirectory
                .appending(path: "rasc-voice-eval-\(UUID().uuidString)").path)
            let repetitions = max(1, Int(value("--repetitions") ?? "1") ?? 1)
            let cold = args.contains("--cold")
            let padShortInput = true
            let corpusRoot = URL(fileURLWithPath: corpusPath).deletingLastPathComponent()

            let manifest = try JSONDecoder().decode([CorpusEntry].self, from: Data(contentsOf: URL(fileURLWithPath: corpusPath)))
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

            let model = VoiceModel()
            // Cold start: release any in-process state, then measure preparation.
            await model.release()
            let prepareStart = ContinuousClock.now
            try await model.prepare()
            let coldLoadMs = Self.ms(prepareStart.duration(to: .now))
            let warmLoadStart = ContinuousClock.now
            try await model.prepare()
            let warmLoadMs = Self.ms(warmLoadStart.duration(to: .now))

            var rows: [ResultRow] = []
            let jsonlPath = output.appending(path: "results.jsonl")
            FileManager.default.createFile(atPath: jsonlPath.path, contents: nil)
            let jsonl = try FileHandle(forWritingTo: jsonlPath)
            defer { try? jsonl.close() }

            for repetition in 1...repetitions {
                for entry in manifest {
                    let audioURL = corpusRoot.appending(path: entry.audio)
                    var row: ResultRow
                    do {
                        let loadStart = ContinuousClock.now
                        let (samples, sampleRate) = try Self.readMonoFloat(at: audioURL)
                        let loadMs = Self.ms(loadStart.duration(to: .now))
                        let audio = VoiceAudio(samples: samples, rate: sampleRate, peak: 1, activitySeconds: Double(samples.count) / sampleRate)

                        if cold { await model.release() }
                        let transcribeStart = ContinuousClock.now
                        let text = try await model.transcribe(audio, modelReady: {})
                        let totalMs = Self.ms(transcribeStart.duration(to: .now))
                        let timing = await model.lastTiming

                        row = ResultRow(
                            id: entry.id, repetition: repetition,
                            language: entry.language, category: entry.category, reference: entry.reference,
                            transcript: text, audioSeconds: audio.seconds, inputSampleRate: sampleRate,
                            cold: cold,
                            modelLoadMs: timing.modelLoadMs, modelReadyMs: timing.modelReadyMs,
                            initializeMs: timing.initializeMs, inferenceMs: timing.inferenceMs, cleanupMs: timing.cleanupMs,
                            transcribeTotalMs: totalMs, audioLoadMs: loadMs, audioPrepareMs: timing.audioPrepareMs,
                            realTimeFactor: timing.realTimeFactor, error: nil
                        )
                    } catch {
                        row = ResultRow(
                            id: entry.id, repetition: repetition, language: entry.language, category: entry.category,
                            reference: entry.reference, transcript: "", audioSeconds: entry.durationSeconds ?? 0, inputSampleRate: 0,
                            cold: cold, modelLoadMs: 0, modelReadyMs: 0, initializeMs: 0, inferenceMs: 0, cleanupMs: 0,
                            transcribeTotalMs: 0, audioLoadMs: 0, audioPrepareMs: 0, realTimeFactor: nil, error: String(describing: error)
                        )
                    }
                    rows.append(row)
                    let data = try JSONEncoder().encode(row)
                    jsonl.write(data)
                    jsonl.write(Data("\n".utf8))
                }
            }

            let summary = Self.summarize(rows, coldLoadMs: coldLoadMs, warmLoadMs: warmLoadMs, repetitions: repetitions, cold: cold)
            try JSONEncoder().encode(summary).write(to: output.appending(path: "summary.json"))
            let run = RunRecord(
                appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?",
                build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?",
                commit: ProcessInfo.processInfo.environment["RASC_EVAL_COMMIT"] ?? "?",
                os: ProcessInfo.processInfo.operatingSystemVersionString,
                machine: ProcessInfo.processInfo.environment["RASC_EVAL_MACHINE"] ?? "?",
                modelRevision: VoiceModelAssets.revision,
                modelPath: Self.redactedPath((try? VoiceModelAssets.availableFolder().path) ?? "?"),
                modelBytes: VoiceModelAssets.totalManifestBytes(),
                configuration: "Core ML CPU + Neural Engine; batch; verbatim; 16 kHz mono; no language hint; trailing-zero pad to 1 s; no streaming; no vocabulary rescoring",
                corpusEntries: manifest.count, repetitions: repetitions, cold: cold, padShortInput: padShortInput,
                coldLoadMs: coldLoadMs, warmLoadMs: warmLoadMs, generatedAt: Date.ISO8601FormatStyle().format(Date())
            )
            try JSONEncoder().encode(run).write(to: output.appending(path: "run.json"))
            FileHandle.standardError.write(Data("voice eval complete: \(output.path)\n".utf8))
            return 0
        } catch {
            FileHandle.standardError.write(Data("voice eval failed: \(error)\n".utf8))
            return 1
        }
    }

    private struct RunRecord: Encodable {
        let appVersion: String, build: String, commit: String, os: String, machine: String
        let modelRevision: String, modelPath: String, modelBytes: Int64, configuration: String
        let corpusEntries: Int, repetitions: Int, cold: Bool, padShortInput: Bool
        let coldLoadMs: Double, warmLoadMs: Double, generatedAt: String
    }

    private struct Summary: Encodable {
        let rows: Int, speechRows: Int, coldLoadMs: Double, warmLoadMs: Double, repetitions: Int, cold: Bool
        let inferenceMsP50: Double?, inferenceMsP95: Double?, transcribeTotalMsP50: Double?, transcribeTotalMsP95: Double?
        let realTimeFactorP50: Double?, realTimeFactorP95: Double?
        let errors: Int
    }

    private static func summarize(_ rows: [ResultRow], coldLoadMs: Double, warmLoadMs: Double, repetitions: Int, cold: Bool) -> Summary {
        func stats(_ values: [Double]) -> (Double?, Double?) {
            let sorted = values.sorted()
            guard !sorted.isEmpty else { return (nil, nil) }
            let p50 = sorted[(sorted.count - 1) / 2]
            let p95 = sorted[min(sorted.count - 1, Int((Double(sorted.count) * 0.95).rounded(.up)) - 1)]
            return (p50, p95)
        }
        let speech = rows.filter {
            $0.error == nil && !($0.reference ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let inference = speech.map(\.inferenceMs)
        let total = speech.map(\.transcribeTotalMs)
        let rtf = speech.compactMap(\.realTimeFactor)
        let (i50, i95) = stats(inference)
        let (t50, t95) = stats(total)
        let (r50, r95) = stats(rtf)
        return Summary(rows: rows.count, speechRows: speech.count, coldLoadMs: coldLoadMs, warmLoadMs: warmLoadMs,
                       repetitions: repetitions, cold: cold,
                       inferenceMsP50: i50, inferenceMsP95: i95, transcribeTotalMsP50: t50, transcribeTotalMsP95: t95,
                       realTimeFactorP50: r50, realTimeFactorP95: r95, errors: rows.count(where: { $0.error != nil }))
    }

    private static func redactedPath(_ path: String) -> String {
        let home = NSHomeDirectory()
        guard path.hasPrefix(home) else { return path }
        return "~" + path.dropFirst(home.count)
    }

    private static func ms(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1_000_000_000_000_000
    }

    /// Read any AVFoundation-supported audio as mono Float at the file's native rate.
    private static func readMonoFloat(at url: URL) throws -> ([Float], Double) {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let frames = AVAudioFrameCount(file.length)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { throw VoiceAudioIssue.conversion }
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
}

private func requireValue<T>(_ value: T?, _ message: String) throws -> T {
    guard let value else { throw NSError(domain: "VoiceEval", code: 2, userInfo: [NSLocalizedDescriptionKey: message]) }
    return value
}
#endif

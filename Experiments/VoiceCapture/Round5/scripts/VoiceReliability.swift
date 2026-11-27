import FluidAudio
import Foundation

private struct ReliabilityWindow: Codable {
    let startSample: Int
    let endSample: Int
    let text: String
    let timings: [TokenTiming]
}

private struct ReliabilityTrial: Encodable {
    let id: String
    let strategy: String
    let reference: String
    let transcript: String
    let audioSeconds: Double
    let resampledFrames: Int
    let resampleMs: Double
    let transcribeTotalMs: Double
    let physFootprintMiB: Double
    let windows: [ReliabilityWindow]
    let error: String?
}

func runVoiceReliability(args: [String]) async throws {
    guard let manifestPath = argValue("--manifest", in: args),
          let modelPath = argValue("--model", in: args),
          let outPath = argValue("--out", in: args) else {
        throw BenchError.invalidArg("--manifest, --model and --out required")
    }
    let strategies = (argValue("--strategies", in: args) ?? "pinned,adaptive,fixed")
        .split(separator: ",").map(String.init)
    let manifest = URL(fileURLWithPath: manifestPath)
    let entries = try JSONDecoder().decode([CorpusEntry].self, from: Data(contentsOf: manifest))
    let model = try await AsrModels.loadLocalOnly(from: URL(fileURLWithPath: modelPath), version: .fluidParakeetPro)
    let out = URL(fileURLWithPath: outPath)
    FileManager.default.createFile(atPath: out.path, contents: nil)
    let output = try FileHandle(forWritingTo: out)
    defer { try? output.close() }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]

    for (index, entry) in entries.enumerated() {
        let url = manifest.deletingLastPathComponent().appending(path: entry.audio ?? "\(entry.id).wav")
        let (channels, rate) = try readPCMChannels(at: url)
        // The stereo fixture includes signal only on channel 1. The whole
        // channel selection path is separately exercised by long-capture-bench.
        let mono = entry.id.hasSuffix("_stereo_ch1") ? channels[1] : channels[0]
        let audio = VoiceAudio(samples: mono, rate: rate, peak: 1, activitySeconds: 0)
        let resampling = ContinuousClock.now
        var samples = try audio.mono16k()
        let resampleMs = ms(resampling.duration(to: .now))
        let frameCount = samples.count
        if samples.count < 16_000 {
            samples.append(contentsOf: repeatElement(0, count: 16_000 - samples.count))
        }
        // Rotate ordering across clips to limit warm-cache bias.
        for offset in strategies.indices {
            let strategy = strategies[(index + offset) % strategies.count]
            let manager = AsrManager()
            try await manager.initialize(models: model)
            let start = ContinuousClock.now
            var windows: [ReliabilityWindow] = []
            var text = ""
            var failure: String?
            do {
                switch strategy {
                case "adaptive":
                    text = try await VoiceRecordingTranscription.transcribe(samples, using: manager)
                case "fixed", "pinned":
                    let max = ASRConstants.maxModelSamples
                    var lower = 0
                    while lower < samples.count {
                        let upper = strategy == "pinned" ? samples.count : min(lower + max, samples.count)
                        var window = Array(samples[lower..<upper])
                        if window.count < 16_000 {
                            window.append(contentsOf: repeatElement(0, count: 16_000 - window.count))
                        }
                        let result = try await manager.transcribe(window, source: .microphone)
                        windows.append(ReliabilityWindow(
                            startSample: lower, endSample: upper, text: result.text,
                            timings: result.tokenTimings ?? []
                        ))
                        lower = upper
                    }
                    text = windows.map(\.text).filter { !$0.isEmpty }.joined(separator: " ")
                default:
                    throw BenchError.invalidArg("Unknown strategy: \(strategy)")
                }
            } catch {
                failure = String(describing: error)
            }
            let decodeMs = ms(start.duration(to: .now))
            let footprint = currentFootprintMiB()
            await manager.cleanup()
            let row = ReliabilityTrial(
                id: entry.id, strategy: strategy,
                reference: entry.reference ?? entry.spoken_text ?? "",
                transcript: VoiceTranscriptSanitizer.clean(text), audioSeconds: audio.seconds,
                resampledFrames: frameCount, resampleMs: resampleMs, transcribeTotalMs: decodeMs,
                physFootprintMiB: footprint, windows: windows, error: failure
            )
            try output.write(contentsOf: encoder.encode(row))
            try output.write(contentsOf: Data("\n".utf8))
        }
    }
}

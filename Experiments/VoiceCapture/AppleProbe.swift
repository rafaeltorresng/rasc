import Foundation
import AVFoundation
import Speech
import CoreMedia
import Darwin

private let clock = ContinuousClock()
private struct ProbeError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

private func milliseconds(since instant: ContinuousClock.Instant) -> Double {
    let duration = instant.duration(to: clock.now).components
    return 1000 * Double(duration.seconds) + Double(duration.attoseconds) / 1e15
}

private func emit(_ event: String, _ fields: [String: Any] = [:]) {
    var record = fields
    record["event"] = event
    if let data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]),
       let line = String(data: data, encoding: .utf8) {
        print(line)
        fflush(nil)
    }
}

@available(macOS 26.0, *)
private enum Engine: String {
    case speech, dictation

    func module(_ locale: Locale) -> any SpeechModule {
        switch self {
        case .speech: SpeechTranscriber(locale: locale, preset: .timeIndexedProgressiveTranscription)
        case .dictation: DictationTranscriber(locale: locale, preset: .progressiveLongDictation)
        }
    }

    func locale(_ identifier: String) async -> Locale? {
        let wanted = Locale(identifier: identifier)
        switch self {
        case .speech: return await SpeechTranscriber.supportedLocale(equivalentTo: wanted)
        case .dictation: return await DictationTranscriber.supportedLocale(equivalentTo: wanted)
        }
    }
}

@main
struct AppleProbe {
    static func main() async {
        do {
            guard #available(macOS 26.0, *) else { throw ProbeError("SpeechAnalyzer requires macOS 26") }
            try await run(Array(CommandLine.arguments.dropFirst()))
        } catch {
            let nsError = error as NSError
            emit("error", ["message": String(describing: error), "domain": nsError.domain, "code": nsError.code])
            exit(1)
        }
    }

    @available(macOS 26.0, *)
    static func run(_ args: [String]) async throws {
        switch args.first {
        case "inventory":
            let speechLocales = await SpeechTranscriber.supportedLocales.map(\.identifier).sorted()
            let dictationLocales = await DictationTranscriber.supportedLocales.map(\.identifier).sorted()
            let speechInstalled = await SpeechTranscriber.installedLocales.map(\.identifier).sorted()
            let dictationInstalled = await DictationTranscriber.installedLocales.map(\.identifier).sorted()
            emit("inventory", [
                "speech_available": SpeechTranscriber.isAvailable,
                "speech_supported": speechLocales, "speech_installed": speechInstalled,
                "dictation_supported": dictationLocales, "dictation_installed": dictationInstalled,
                "legacy_pt_on_device": SFSpeechRecognizer(locale: Locale(identifier: "pt-BR"))?.supportsOnDeviceRecognition ?? false,
                "legacy_en_on_device": SFSpeechRecognizer(locale: Locale(identifier: "en-US"))?.supportsOnDeviceRecognition ?? false,
                "mic_authorization": AVCaptureDevice.authorizationStatus(for: .audio).rawValue,
                "legacy_speech_authorization": SFSpeechRecognizer.authorizationStatus().rawValue,
                "bundle_id": Bundle.main.bundleIdentifier ?? "",
                "containerized": NSHomeDirectory().contains("/Containers/com.rasc.research.voiceprobe/Data"),
                "max_reserved_locales": AssetInventory.maximumReservedLocales,
                "reserved_locales": await AssetInventory.reservedLocales.map(\.identifier).sorted(),
            ])
        case "install", "batch", "paced", "cancel", "cancel-final", "hints", "cancel-prepare":
            guard args.count >= 3, let engine = Engine(rawValue: args[1]),
                  let locale = await engine.locale(args[2]) else { throw ProbeError("Engine or locale unsupported") }
            if args[0] == "install" {
                let module = engine.module(locale)
                let start = clock.now
                emit("asset_start", ["engine": engine.rawValue, "locale": locale.identifier,
                                     "status": String(describing: await AssetInventory.status(forModules: [module]))])
                if let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
                    try await request.downloadAndInstall()
                }
                emit("asset_end", ["engine": engine.rawValue, "locale": locale.identifier,
                                   "status": String(describing: await AssetInventory.status(forModules: [module])),
                                   "elapsed_ms": milliseconds(since: start)])
                return
            }
            if args[0] == "cancel-prepare" {
                try await cancelPreparation(engine: engine, locale: locale)
                return
            }
            guard args.count > 3 else { throw ProbeError("Provide fixture paths") }
            for path in args.dropFirst(3) {
                let url: URL
                if path.hasPrefix("@"), let resources = Bundle.main.resourceURL {
                    url = resources.appending(path: String(path.dropFirst()))
                } else {
                    url = URL(fileURLWithPath: path)
                }
                try await analyze(engine: engine, locale: locale, url: url, mode: args[0])
            }
        case "resample", "resample-drain":
            guard args.count == 2 else { throw ProbeError("resample requires a 48 kHz test fixture path") }
            let url = URL(fileURLWithPath: args[1])
            try await analyze(engine: .speech, locale: Locale(identifier: "en_US"), url: url, mode: args[0])
        case "idle":
            try await measureIdle()
        case "mic":
            let status = AVCaptureDevice.authorizationStatus(for: .audio)
            let allowed: Bool
            if status == .notDetermined, args.contains("--request") {
                allowed = await AVCaptureDevice.requestAccess(for: .audio)
            } else {
                allowed = status == .authorized
            }
            emit("mic_permission", ["authorized": allowed, "status": AVCaptureDevice.authorizationStatus(for: .audio).rawValue])
            guard allowed else { return }
            try await microphone(count: args.dropFirst().compactMap(Int.init).first ?? 3)
        default:
            throw ProbeError("inventory | install ENGINE LOCALE | batch/paced/cancel/cancel-final ENGINE LOCALE FILE... | mic [--request] [COUNT] | idle | resample/resample-drain FILE | hints ENGINE LOCALE FILE... | cancel-prepare ENGINE LOCALE")
        }
    }

    @available(macOS 26.0, *)
    private static func analyze(engine: Engine, locale: Locale, url: URL, mode: String) async throws {
        let start = clock.now
        let module = engine.module(locale)
        let status = await AssetInventory.status(forModules: [module])
        guard status == .installed else { throw ProbeError("Assets are \(status); use install explicitly") }
        let analyzer = SpeechAnalyzer(modules: [module], options: .init(priority: .userInitiated, modelRetention: .whileInUse))
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module]) else {
            throw ProbeError("No analyzer format")
        }
        if mode == "hints" {
            let context = AnalysisContext()
            context.contextualStrings = [.general: ["race condition", "worker", "deploy", "SQLite",
                                                     "fallback", "rollback", "timeout", "retry", "Maya"]]
            try await analyzer.setContext(context)
        }
        let beforePrepare = clock.now
        try await analyzer.prepareToAnalyze(in: format)
        let prepare = milliseconds(since: beforePrepare)
        let file = try AVAudioFile(forReading: url)
        let input = AsyncStream<AnalyzerInput>.makeStream()
        let inputStart = clock.now
        let reader = Task {
            if let speech = module as? SpeechTranscriber {
                return try await collect(speech.results, since: inputStart)
            }
            guard let dictation = module as? DictationTranscriber else { throw ProbeError("Unknown module") }
            return try await collect(dictation.results, since: inputStart)
        }

        do {
            try await analyzer.start(inputSequence: input.stream)
            let duration = Double(file.length) / file.processingFormat.sampleRate
            let shouldPace = mode != "batch"
            let inputFormat = file.processingFormat
            guard let converter = AVAudioConverter(from: inputFormat, to: format) else {
                throw ProbeError("No converter for fixture input format")
            }
            let equalRate = format.sampleRate == inputFormat.sampleRate
            converter.primeMethod = mode == "resample-drain" ? .normal : .none
            let frameCount = AVAudioFrameCount(inputFormat.sampleRate / 10)
            let outputCapacity = AVAudioFrameCount(ceil(format.sampleRate / 10)) + 64
            var outputFrames: UInt64 = 0
            while file.framePosition < file.length {
                guard let raw = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frameCount),
                      let converted = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: outputCapacity) else {
                    throw ProbeError("Cannot allocate fixture buffer")
                }
                try file.read(into: raw, frameCount: frameCount)
                if raw.frameLength == 0 { break }
                if equalRate {
                    try converter.convert(to: converted, from: raw)
                } else {
                    try convertChunk(raw, into: converted, with: converter)
                }
                if shouldPace {
                    let deadline = inputStart.advanced(by: .seconds(Double(file.framePosition) / file.processingFormat.sampleRate))
                    try await clock.sleep(until: deadline)
                }
                if converted.frameLength > 0 {
                    outputFrames += UInt64(converted.frameLength)
                    input.continuation.yield(AnalyzerInput(buffer: converted))
                }
                if mode == "cancel" && file.framePosition >= 8000 { break }
            }

            let stop = clock.now
            if mode == "resample-drain", !equalRate {
                guard let tail = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: outputCapacity) else {
                    throw ProbeError("Cannot allocate converter tail")
                }
                var error: NSError?
                let tailStatus = converter.convert(to: tail, error: &error) { _, state in
                    state.pointee = .endOfStream
                    return nil
                }
                if tailStatus == .error {
                    if let error { throw error }
                    throw ProbeError("PCM tail conversion failed")
                }
                if tail.frameLength > 0 {
                    outputFrames += UInt64(tail.frameLength)
                    input.continuation.yield(AnalyzerInput(buffer: tail))
                }
            }
            if mode == "cancel" || mode == "cancel-final" {
                var finalizer: Task<Void, Error>?
                if mode == "cancel-final" {
                    input.continuation.finish()
                    finalizer = Task { try await analyzer.finalizeAndFinishThroughEndOfInput() }
                    try await Task.sleep(for: .milliseconds(15))
                }
                reader.cancel()
                await analyzer.cancelAndFinishNow()
                input.continuation.finish()
                _ = await reader.result
                finalizer?.cancel()
                if let finalizer { _ = await finalizer.result }
                emit("cancelled", ["engine": engine.rawValue, "fixture": url.lastPathComponent,
                                   "mode": mode, "cancel_ms": milliseconds(since: stop)])
                return
            }
            input.continuation.finish()
            try await analyzer.finalizeAndFinishThroughEndOfInput()
            let output = try await reader.value
            var row: [String: Any] = [
                "engine": engine.rawValue, "locale": locale.identifier, "fixture": url.lastPathComponent,
                "mode": mode, "audio_seconds": duration, "source_rate": inputFormat.sampleRate,
                "analyzer_rate": format.sampleRate, "output_frames": outputFrames,
                "prepare_ms": prepare, "ready_ms": inputStart.duration(since: start),
                "finish_ms": milliseconds(since: stop), "total_ms": milliseconds(since: start),
                "partial_count": output.partialCount, "final_count": output.finals.count,
                "transcript": output.finals.sorted { $0.position < $1.position }.map(\.text).joined(),
            ]
            row["first_result_ms"] = output.first
            row["first_partial_ms"] = output.firstPartial
            emit("result", row)
        } catch {
            reader.cancel()
            input.continuation.finish()
            await analyzer.cancelAndFinishNow()
            _ = await reader.result
            throw error
        }
    }

    @available(macOS 26.0, *)
    private static func cancelPreparation(engine: Engine, locale: Locale) async throws {
        let module = engine.module(locale)
        guard await AssetInventory.status(forModules: [module]) == .installed else {
            throw ProbeError("Install assets before testing preparation cancellation")
        }
        let analyzer = SpeechAnalyzer(modules: [module], options: .init(priority: .userInitiated, modelRetention: .whileInUse))
        let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module])
        let work = Task { try await analyzer.prepareToAnalyze(in: format) }
        try await Task.sleep(for: .milliseconds(2))
        let start = clock.now
        work.cancel()
        await analyzer.cancelAndFinishNow()
        let outcome: String
        switch await work.result {
        case .success: outcome = "prepare_returned_success_after_cancel_requested"
        case .failure: outcome = "prepare_returned_error_after_cancel_requested"
        }
        emit("prepare_cancellation", ["engine": engine.rawValue, "locale": locale.identifier,
                                      "cancel_ms": milliseconds(since: start), "outcome": outcome])
    }

    private static func convertChunk(
        _ input: AVAudioPCMBuffer, into output: AVAudioPCMBuffer, with converter: AVAudioConverter
    ) throws {
        let chunk = ConverterChunk(input)
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, state in
            defer { chunk.used = true }
            state.pointee = chunk.used ? .noDataNow : .haveData
            return chunk.used ? nil : chunk.buffer
        }
        if status == .error {
            if let error { throw error }
            throw ProbeError("PCM rate conversion failed")
        }
    }

    // AVAudioConverter calls its input block synchronously during convert.
    private final class ConverterChunk: @unchecked Sendable {
        let buffer: AVAudioPCMBuffer
        var used = false
        init(_ buffer: AVAudioPCMBuffer) { self.buffer = buffer }
    }

    private static func measureIdle() async throws {
        let started = clock.now
        var before = rusage()
        getrusage(RUSAGE_SELF, &before)
        try await Task.sleep(for: .seconds(5))
        var after = rusage()
        getrusage(RUSAGE_SELF, &after)
        func microseconds(_ value: timeval) -> Int64 {
            Int64(value.tv_sec) * 1_000_000 + Int64(value.tv_usec)
        }
        let user = microseconds(after.ru_utime) - microseconds(before.ru_utime)
        let system = microseconds(after.ru_stime) - microseconds(before.ru_stime)
        emit("idle", ["duration_ms": milliseconds(since: started), "process_cpu_ms": Double(user + system) / 1000,
                      "process_peak_bytes": after.ru_maxrss])
    }

    private struct Results {
        var first: Double?
        var firstPartial: Double?
        var partialCount = 0
        var finals: [(position: Double, text: String)] = []
    }

    @available(macOS 26.0, *)
    private static func collect<S: AsyncSequence & Sendable, R: SpeechModuleResult>(
        _ results: S, since start: ContinuousClock.Instant
    ) async throws -> Results where S.Element == R {
        var collection = Results()
        for try await result in results {
            let elapsed = milliseconds(since: start)
            if collection.first == nil { collection.first = elapsed }
            if result.isFinal {
                let text: String
                if let value = result as? SpeechTranscriber.Result {
                    text = String(value.text.characters)
                } else if let value = result as? DictationTranscriber.Result {
                    text = String(value.text.characters)
                } else { continue }
                collection.finals.append((result.range.start.seconds, text))
            } else {
                if collection.firstPartial == nil { collection.firstPartial = elapsed }
                collection.partialCount += 1
            }
        }
        return collection
    }

    private static func microphone(count: Int) async throws {
        // Discard every microphone sample. Only the arrival timestamp, frame count and device format are inspected.
        for trial in 1...max(1, count) {
            let engine = AVAudioEngine()
            let start = clock.now
            let node = engine.inputNode
            let format = node.outputFormat(forBus: 0)
            guard format.channelCount > 0, format.sampleRate > 0 else {
                throw ProbeError("No audio input route")
            }
            let stream = AsyncStream<(Double, UInt32)>.makeStream(bufferingPolicy: .bufferingOldest(1))
            node.installTap(onBus: 0, bufferSize: 512, format: format) { buffer, _ in
                stream.continuation.yield((milliseconds(since: start), buffer.frameLength))
            }
            defer {
                node.removeTap(onBus: 0)
                engine.stop()
            }
            do {
                engine.prepare()
                try engine.start()
            } catch { throw error }
            let started = milliseconds(since: start)
            let first = await withTaskGroup(of: (Double, UInt32)?.self) { group in
                group.addTask {
                    var iterator = stream.stream.makeAsyncIterator()
                    return await iterator.next()
                }
                group.addTask {
                    try? await Task.sleep(for: .seconds(3))
                    return nil
                }
                let first = await group.next() ?? nil
                group.cancelAll()
                return first
            }
            stream.continuation.finish()
            var row: [String: Any] = ["trial": trial, "start_ms": started, "sample_rate": format.sampleRate,
                                      "channels": format.channelCount, "received": first != nil]
            row["first_buffer_ms"] = first?.0
            row["first_buffer_frames"] = first?.1
            emit("mic_trial", row)
            engine.stop()
            try await Task.sleep(for: .milliseconds(150))
        }
    }
}

private extension ContinuousClock.Instant {
    func duration(since earlier: Self) -> Double {
        let d = earlier.duration(to: self).components
        return Double(d.seconds) * 1000 + Double(d.attoseconds) / 1e15
    }
}

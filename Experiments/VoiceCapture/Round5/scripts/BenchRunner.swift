import AVFoundation
import Accelerate
import AppKit
import Darwin
import FluidAudio
import Foundation
import GRDB
import Speech

@main
enum BenchRunnerMain {
    static func main() async {
        let args = Array(ProcessInfo.processInfo.arguments.dropFirst())
        guard let cmd = args.first else {
            fputs("Usage: RascBench <scale-bench|long-capture-bench|eval-voice|apple-speech|e2e-latency> [options]\n", stderr)
            exit(2)
        }
        do {
            switch cmd {
            case "scale-bench":
                try await runScaleBench(args: Array(args.dropFirst()))
            case "long-capture-bench":
                try await runLongCaptureBench(args: Array(args.dropFirst()))
            case "voice-reliability":
                try await runVoiceReliability(args: Array(args.dropFirst()))
            case "eval-voice":
                try await runEvalVoice(args: Array(args.dropFirst()))
            case "apple-speech":
                if #available(macOS 26.0, *) {
                    try await runAppleSpeech(args: Array(args.dropFirst()))
                } else {
                    throw BenchError.runtime("SpeechTranscriber requires macOS 26+")
                }
            case "e2e-latency":
                try await runE2ELatency(args: Array(args.dropFirst()))
            case "eval-refine":
                try await runEvalRefine(args: Array(args.dropFirst()))
            default:
                throw BenchError.invalidArg("Unknown command: \(cmd)")
            }
        } catch {
            fputs("RascBench failed: \(error)\n", stderr)
            exit(1)
        }
    }
}

enum BenchError: Error, CustomStringConvertible {
    case invalidArg(String)
    case runtime(String)

    var description: String {
        switch self {
        case .invalidArg(let m): "InvalidArg: \(m)"
        case .runtime(let m): "Runtime: \(m)"
        }
    }
}

func argValue(_ name: String, in args: [String]) -> String? {
    guard let idx = args.firstIndex(of: name), idx + 1 < args.count else { return nil }
    return args[idx + 1]
}

func hasFlag(_ name: String, in args: [String]) -> Bool {
    args.contains(name)
}

func ms(_ duration: Duration) -> Double {
    Double(duration.components.seconds) * 1000.0 + Double(duration.components.attoseconds) / 1e15
}

func currentFootprintMiB() -> Double {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
    let kr = withUnsafeMutablePointer(to: &info) { ptr in
        ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), intPtr, &count)
        }
    }
    guard kr == KERN_SUCCESS else { return -1 }
    return Double(info.phys_footprint) / (1024.0 * 1024.0)
}

func fileSize(_ url: URL) -> Int64 {
    (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
}

// MARK: - 1. Scale Bench

struct ScaleResultRow: Encodable {
    let noteCount: Int
    let bootstrapMs: Double
    let seedMs: Double
    let fetchMostRecentP50Ms: Double
    let fetchAllNonDeletedMs: Double
    let keptCount: Int
    let searchLimit20P50Ms: Double
    let searchLimit500Ms: Double
    let batchDiscard50Ms: Double
    let restoreDiscards50Ms: Double
    let batchDiscard500Ms: Double
    let purgeExpired500Ms: Double
    let purgedRows: Int
    let backupMs: Double
    let backupVerifiedNoteCount: Int
    let backupSizeBytes: Int64
    let dbBytesBeforeCheckpoint: Int64
    let walBytesBeforeCheckpoint: Int64
    let checkpointMs: Double
    let walBytesAfterCheckpoint: Int64
}

func median(_ values: [Double]) -> Double {
    let s = values.sorted()
    guard !s.isEmpty else { return 0 }
    return s[(s.count - 1) / 2]
}

func runScaleBench(args: [String]) async throws {
    let outPath = URL(fileURLWithPath: argValue("--out", in: args) ?? "/tmp/rasc-scale-bench.json")
    let counts = (argValue("--counts", in: args) ?? "1000,5000")
        .split(separator: ",")
        .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }

    var rows: [ScaleResultRow] = []
    for count in counts {
        let base = FileManager.default.temporaryDirectory.appending(path: "rasc-scale-\(count)-\(UUID().uuidString)")
        let dbURL = base.appending(path: "Rasc.sqlite")
        let backupURL = base.appending(path: "Rasc-backup.sqlite")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }

        let tBoot = ContinuousClock.now
        let repo = try NoteRepository(databaseURL: dbURL)
        let bootstrapMs = ms(tBoot.duration(to: .now))

        let tSeed = ContinuousClock.now
        var createdIDs: [UUID] = []
        createdIDs.reserveCapacity(count)
        for i in 0..<count {
            let origin: Note.Origin = (i % 10 < 3) ? .dictation : .scratch
            let content = """
            Note \(i): Investigate retry queue logs for deploy #\(i % 40) and Supabase Auth latency. \
            \(String(repeating: "context token ", count: (i % 6) + 1))
            """
            let note = try await repo.createScratch(content: content, origin: origin)
            createdIDs.append(note.id)
            if i % 5 == 0 {
                _ = try await repo.keep(id: note.id)
            }
        }
        let seedMs = ms(tSeed.duration(to: .now))

        var recentSamples: [Double] = []
        for _ in 0..<10 {
            let t = ContinuousClock.now
            _ = try await repo.fetchMostRecent()
            recentSamples.append(ms(t.duration(to: .now)))
        }

        let tAll = ContinuousClock.now
        let allActive = try await repo.fetchAllNonDeleted()
        let fetchAllMs = ms(tAll.duration(to: .now))
        let keptCount = allActive.filter(\.isKept).count

        var search20: [Double] = []
        for _ in 0..<10 {
            let t = ContinuousClock.now
            _ = try await repo.search("retry queue", limit: 20)
            search20.append(ms(t.duration(to: .now)))
        }

        let tSearch500 = ContinuousClock.now
        _ = try await repo.search("retry", limit: 500)
        let search500Ms = ms(tSearch500.duration(to: .now))

        let fifty = Set(createdIDs.prefix(50))
        let tDiscard50 = ContinuousClock.now
        let receipts50 = try await repo.delete(ids: fifty)
        let batchDiscard50Ms = ms(tDiscard50.duration(to: .now))

        let tRestore50 = ContinuousClock.now
        _ = try await repo.restoreDiscards(receipts50)
        let restore50Ms = ms(tRestore50.duration(to: .now))

        let fiveHundred = Set(createdIDs.prefix(500))
        let tDiscard500 = ContinuousClock.now
        _ = try await repo.delete(ids: fiveHundred)
        let batchDiscard500Ms = ms(tDiscard500.duration(to: .now))

        let tPurge = ContinuousClock.now
        let purged = try await repo.purgeExpiredSoftDeletedNotes(
            olderThanDays: 7,
            now: Date().addingTimeInterval(8 * 86_400)
        )
        let purgeMs = ms(tPurge.duration(to: .now))

        let tBackup = ContinuousClock.now
        try await repo.backup(to: backupURL)
        let backupMs = ms(tBackup.duration(to: .now))

        let backupRepo = try NoteRepository(databaseURL: backupURL)
        let backupNotes = try await backupRepo.fetchAllNonDeleted()

        let walURL = URL(fileURLWithPath: dbURL.path + "-wal")
        let dbBefore = fileSize(dbURL)
        let walBefore = fileSize(walURL)

        let tCkpt = ContinuousClock.now
        await repo.checkpointForTermination()
        let ckptMs = ms(tCkpt.duration(to: .now))
        let walAfter = fileSize(walURL)

        let row = ScaleResultRow(
            noteCount: count,
            bootstrapMs: bootstrapMs,
            seedMs: seedMs,
            fetchMostRecentP50Ms: median(recentSamples),
            fetchAllNonDeletedMs: fetchAllMs,
            keptCount: keptCount,
            searchLimit20P50Ms: median(search20),
            searchLimit500Ms: search500Ms,
            batchDiscard50Ms: batchDiscard50Ms,
            restoreDiscards50Ms: restore50Ms,
            batchDiscard500Ms: batchDiscard500Ms,
            purgeExpired500Ms: purgeMs,
            purgedRows: purged,
            backupMs: backupMs,
            backupVerifiedNoteCount: backupNotes.count,
            backupSizeBytes: fileSize(backupURL),
            dbBytesBeforeCheckpoint: dbBefore,
            walBytesBeforeCheckpoint: walBefore,
            checkpointMs: ckptMs,
            walBytesAfterCheckpoint: walAfter
        )
        rows.append(row)
    }

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(rows).write(to: outPath)
    print("scale-bench wrote \(rows.count) rows -> \(outPath.path)")
}

// MARK: - 2. Corpus Loading & Chunked Resample Helper

struct CorpusEntry: Decodable {
    let id: String
    let audio: String?
    let reference: String?
    let spoken_text: String?
    let intended_text: String?
    let locale: String?
    let language: String?
    let scenario: String?
    let category: String?
    let durationSeconds: Double?
}

func readPCMChannels(at url: URL) throws -> (channels: [[Float]], sampleRate: Double) {
    let file = try AVAudioFile(forReading: url)
    let format = file.processingFormat
    let frameCount = AVAudioFrameCount(file.length)
    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
        throw VoiceAudioIssue.conversion
    }
    try file.read(into: buffer)
    let count = Int(buffer.frameLength)
    let chCount = Int(format.channelCount)
    guard let ptrs = buffer.floatChannelData else { throw VoiceAudioIssue.conversion }
    var channels: [[Float]] = []
    channels.reserveCapacity(chCount)
    for ch in 0..<chCount {
        channels.append(Array(UnsafeBufferPointer(start: ptrs[ch], count: count)))
    }
    return (channels, format.sampleRate)
}

func chunkedMono16k(_ samples: [Float], rate: Double, blockSeconds: Double = 15.0) throws -> [Float] {
    guard !samples.isEmpty else { throw VoiceAudioIssue.noFrames }
    guard rate.isFinite, (8000...192000).contains(rate) else { throw VoiceAudioIssue.conversion }
    if rate == 16000 {
        return samples.allSatisfy(\.isFinite) ? samples : samples.map { $0.isFinite ? $0 : 0 }
    }
    guard let inputFormat = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1),
          let outputFormat = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1),
          let converter = AVAudioConverter(from: inputFormat, to: outputFormat)
    else {
        throw VoiceAudioIssue.conversion
    }
    let inputBlockFrames = max(1600, Int(rate * blockSeconds))
    let outputBlockCapacity = AVAudioFrameCount(ceil(Double(inputBlockFrames) * (16000.0 / rate)) + 2048)
    guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: AVAudioFrameCount(inputBlockFrames)),
          let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: outputBlockCapacity)
    else {
        throw VoiceAudioIssue.conversion
    }

    var result: [Float] = []
    result.reserveCapacity(Int(ceil(Double(samples.count) * (16000.0 / rate))) + 256)
    var offset = 0
    while offset < samples.count {
        let len = min(inputBlockFrames, samples.count - offset)
        inputBuffer.frameLength = AVAudioFrameCount(len)
        samples.withUnsafeBufferPointer { src in
            if let base = src.baseAddress {
                inputBuffer.floatChannelData?[0].update(from: base.advanced(by: offset), count: len)
            }
        }
        offset += len
        converter.reset()
        final class OneShotBox: @unchecked Sendable {
            var fed = false
            let buf: AVAudioPCMBuffer
            init(_ buf: AVAudioPCMBuffer) { self.buf = buf }
        }
        let box = OneShotBox(inputBuffer)
        var err: NSError?
        let status = converter.convert(to: outputBuffer, error: &err) { _, outStatus in
            if box.fed {
                outStatus.pointee = .endOfStream
                return nil
            }
            box.fed = true
            outStatus.pointee = .haveData
            return box.buf
        }
        guard status != .error, let ptr = outputBuffer.floatChannelData?[0] else {
            throw VoiceAudioIssue.conversion
        }
        let n = Int(outputBuffer.frameLength)
        for i in 0..<n {
            let v = ptr[i]
            result.append(v.isFinite ? v : 0)
        }
    }
    return result
}

// MARK: - 3. Long Capture Bench

struct LongCaptureRow: Encodable {
    let id: String
    let language: String?
    let category: String?
    let inputRate: Double
    let inputChannels: Int
    let inputFrames: Int
    let audioSeconds: Double
    let activitySeconds: Double
    let expected16kFrames: Int
    let singleShot16kFrames: Int
    let chunked16kFrames: Int
    let singleShotResampleMs: Double
    let chunkedResampleMs: Double
    let memBaselineMiB: Double
    let memAfterMicBufferMiB: Double
    let memAfterSingleShotResampleMiB: Double
    let memAfterTranscribeMiB: Double
    let memAfterReleaseMiB: Double
    let timing: VoiceModel.TranscriptionTiming
    let reference: String
    let transcript: String
}

func runLongCaptureBench(args: [String]) async throws {
    guard let manifestPath = argValue("--manifest", in: args),
          let outPath = argValue("--out", in: args) else {
        throw BenchError.invalidArg("--manifest and --out required")
    }
    let manifestURL = URL(fileURLWithPath: manifestPath)
    let corpusRoot = manifestURL.deletingLastPathComponent()
    let entries = try JSONDecoder().decode([CorpusEntry].self, from: Data(contentsOf: manifestURL))

    let model = VoiceModel()
    try await model.prepare()

    var rows: [LongCaptureRow] = []
    for entry in entries {
        let audioRel = entry.audio ?? "\(entry.id).wav"
        let audioURL = corpusRoot.appending(path: audioRel)
        let (channels, rate) = try readPCMChannels(at: audioURL)
        let frameCount = channels.first?.count ?? 0

        let memBase = currentFootprintMiB()
        let captureLimit = hasFlag("--production-limit", in: args) ? MicBuffer.defaultMaxDurationSeconds : 300
        let micBuffer = MicBuffer(rate: rate, maxDurationSeconds: captureLimit)
        guard let pcmFormat = AVAudioFormat(standardFormatWithSampleRate: rate, channels: AVAudioChannelCount(channels.count)) else {
            throw VoiceAudioIssue.conversion
        }
        let blockSize = 512
        var offset = 0
        while offset < frameCount {
            let count = min(blockSize, frameCount - offset)
            guard let block = AVAudioPCMBuffer(pcmFormat: pcmFormat, frameCapacity: AVAudioFrameCount(count)),
                  let dst = block.floatChannelData else { throw VoiceAudioIssue.conversion }
            block.frameLength = AVAudioFrameCount(count)
            for ch in 0..<channels.count {
                channels[ch].withUnsafeBufferPointer { ptr in
                    if let base = ptr.baseAddress {
                        dst[ch].update(from: base.advanced(by: offset), count: count)
                    }
                }
            }
            micBuffer.append(block)
            offset += count
        }
        let memAfterMic = currentFootprintMiB()
        let audio = micBuffer.audio()
        let expected16k = Int((Double(audio.samples.count) * (16000.0 / rate)).rounded())

        let tSingle = ContinuousClock.now
        let single16 = try audio.mono16k()
        let singleMs = ms(tSingle.duration(to: .now))
        let memAfterSingle = currentFootprintMiB()

        let tChunk = ContinuousClock.now
        let chunked16 = try chunkedMono16k(audio.samples, rate: rate)
        let chunkMs = ms(tChunk.duration(to: .now))

        let rawText = try await model.transcribe(audio, modelReady: {})
        let memAfterTrans = currentFootprintMiB()
        let cleaned = VoiceTranscriptSanitizer.clean(rawText)
        let timing = await model.lastTiming

        let row = LongCaptureRow(
            id: entry.id,
            language: entry.language ?? entry.locale,
            category: entry.category ?? entry.scenario,
            inputRate: rate,
            inputChannels: channels.count,
            inputFrames: audio.samples.count,
            audioSeconds: audio.seconds,
            activitySeconds: audio.activitySeconds,
            expected16kFrames: expected16k,
            singleShot16kFrames: single16.count,
            chunked16kFrames: chunked16.count,
            singleShotResampleMs: singleMs,
            chunkedResampleMs: chunkMs,
            memBaselineMiB: memBase,
            memAfterMicBufferMiB: memAfterMic,
            memAfterSingleShotResampleMiB: memAfterSingle,
            memAfterTranscribeMiB: memAfterTrans,
            memAfterReleaseMiB: memAfterTrans,
            timing: timing,
            reference: entry.reference ?? "",
            transcript: cleaned
        )
        rows.append(row)
        print("long-capture \(entry.id): \(String(format: "%.1f", audio.seconds))s rate=\(Int(rate)) ch=\(channels.count) expected16k=\(expected16k) single16k=\(single16.count) infMs=\(String(format: "%.1f", timing.inferenceMs)) memTrans=\(String(format: "%.1f", memAfterTrans))MiB")
        fflush(stdout)
    }

    await model.release()
    try await Task.sleep(for: .milliseconds(300))
    let releasedMiB = currentFootprintMiB()
    let payload: [String: Any] = [
        "releasedFootprintMiB": releasedMiB,
        "count": rows.count,
    ]
    _ = payload
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(["releasedFootprintMiB": AnyEncodable(releasedMiB), "rows": AnyEncodable(rows)])
        .write(to: URL(fileURLWithPath: outPath))
}

struct AnyEncodable: Encodable {
    private let _encode: (Encoder) throws -> Void
    init<T: Encodable>(_ value: T) { _encode = value.encode }
    func encode(to encoder: Encoder) throws { try _encode(encoder) }
}

// MARK: - 4. Fluid Speech Pro Eval (+ optional onset pad + optional Refine)

struct EvalVoiceRow: Encodable {
    let id: String
    let repetition: Int
    let language: String?
    let category: String?
    let reference: String?
    let spoken_text: String?
    let intended_text: String?
    let rawTranscript: String
    let transcript: String
    let audioSeconds: Double
    let inputSampleRate: Double
    let cold: Bool
    let onsetPadMs: Int
    let modelLoadMs: Double
    let modelReadyMs: Double
    let audioPrepareMs: Double
    let initializeMs: Double
    let inferenceMs: Double
    let cleanupMs: Double
    let transcribeTotalMs: Double
    let audioLoadMs: Double
    let realTimeFactor: Double?
    let physFootprintMiB: Double
    let refinedText: String?
    let refineDecision: String?
    let refineKind: String?
    let refineMs: Double?
    let refineResolvedLanguage: String?
    let refineError: String?
    let error: String?
}

func runEvalVoice(args: [String]) async throws {
    guard let manifestPath = argValue("--manifest", in: args),
          let outPath = argValue("--out", in: args) else {
        throw BenchError.invalidArg("--manifest and --out required")
    }
    let cold = hasFlag("--cold", in: args)
    let doRefine = hasFlag("--refine", in: args)
    let onsetPadMs = Int(argValue("--onset-pad-ms", in: args) ?? "0") ?? 0
    let maxClips = Int(argValue("--limit", in: args) ?? "0") ?? 0

    let manifestURL = URL(fileURLWithPath: manifestPath)
    let corpusRoot = manifestURL.deletingLastPathComponent()
    var entries = try JSONDecoder().decode([CorpusEntry].self, from: Data(contentsOf: manifestURL))
    if maxClips > 0 { entries = Array(entries.prefix(maxClips)) }

    let outURL = URL(fileURLWithPath: outPath)
    try FileManager.default.createDirectory(at: outURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: outURL.path, contents: nil)
    let handle = try FileHandle(forWritingTo: outURL)
    defer { try? handle.close() }

    let model = VoiceModel()
    await model.release()
    let tCold = ContinuousClock.now
    try await model.prepare()
    let coldLoadMs = ms(tCold.duration(to: .now))
    let tWarm = ContinuousClock.now
    try await model.prepare()
    let warmLoadMs = ms(tWarm.duration(to: .now))

    let refineProvider = FoundationModelsRefinementProvider()
    let encoder = JSONEncoder()

    for entry in entries {
        let rel = entry.audio ?? "\(entry.id).wav"
        let url = corpusRoot.appending(path: rel)
        let row: EvalVoiceRow
        do {
            let tLoad = ContinuousClock.now
            let (channels, rate) = try readPCMChannels(at: url)
            let loadMs = ms(tLoad.duration(to: .now))
            var mono = channels.first ?? []
            if onsetPadMs > 0 {
                let padSamples = Int((Double(onsetPadMs) / 1000.0) * rate)
                if padSamples > 0 {
                    mono = Array(repeating: Float(0), count: padSamples) + mono
                }
            }
            let audio = VoiceAudio(samples: mono, rate: rate, peak: 1.0, activitySeconds: Double(mono.count) / rate)
            if cold { await model.release() }
            let tTotal = ContinuousClock.now
            let rawText = try await model.transcribe(audio, modelReady: {})
            let totalMs = ms(tTotal.duration(to: .now))
            let cleaned = VoiceTranscriptSanitizer.clean(rawText)
            let timing = await model.lastTiming

            var rText: String? = nil
            var rDecision: String? = nil
            var rKind: String? = nil
            var rMs: Double? = nil
            var rLang: String? = nil
            var rErr: String? = nil

            if doRefine && !cleaned.isEmpty {
                let req = RefinementRequest(snapshot: NoteSnapshot(noteID: UUID(), revision: 1, text: cleaned))
                let tRef = ContinuousClock.now
                do {
                    let res = try await refineProvider.refine(req)
                    rMs = ms(tRef.duration(to: .now))
                    rText = res.text
                    rDecision = res.decision.rawValue
                    rKind = res.kind.rawValue
                    rLang = res.languageTrace?.resolvedLocale
                } catch {
                    rMs = ms(tRef.duration(to: .now))
                    rErr = String(describing: error)
                }
            }

            row = EvalVoiceRow(
                id: entry.id, repetition: 1,
                language: entry.language ?? entry.locale,
                category: entry.category ?? entry.scenario,
                reference: entry.reference,
                spoken_text: entry.spoken_text,
                intended_text: entry.intended_text,
                rawTranscript: rawText,
                transcript: cleaned,
                audioSeconds: audio.seconds,
                inputSampleRate: rate,
                cold: cold,
                onsetPadMs: onsetPadMs,
                modelLoadMs: timing.modelLoadMs,
                modelReadyMs: timing.modelReadyMs,
                audioPrepareMs: timing.audioPrepareMs,
                initializeMs: timing.initializeMs,
                inferenceMs: timing.inferenceMs,
                cleanupMs: timing.cleanupMs,
                transcribeTotalMs: totalMs,
                audioLoadMs: loadMs,
                realTimeFactor: timing.realTimeFactor,
                physFootprintMiB: currentFootprintMiB(),
                refinedText: rText,
                refineDecision: rDecision,
                refineKind: rKind,
                refineMs: rMs,
                refineResolvedLanguage: rLang,
                refineError: rErr,
                error: nil
            )
        } catch {
            row = EvalVoiceRow(
                id: entry.id, repetition: 1,
                language: entry.language ?? entry.locale,
                category: entry.category ?? entry.scenario,
                reference: entry.reference,
                spoken_text: entry.spoken_text,
                intended_text: entry.intended_text,
                rawTranscript: "",
                transcript: "",
                audioSeconds: entry.durationSeconds ?? 0,
                inputSampleRate: 0,
                cold: cold,
                onsetPadMs: onsetPadMs,
                modelLoadMs: 0, modelReadyMs: 0, audioPrepareMs: 0,
                initializeMs: 0, inferenceMs: 0, cleanupMs: 0, transcribeTotalMs: 0, audioLoadMs: 0,
                realTimeFactor: nil, physFootprintMiB: currentFootprintMiB(),
                refinedText: nil, refineDecision: nil, refineKind: nil, refineMs: nil,
                refineResolvedLanguage: nil, refineError: nil,
                error: String(describing: error)
            )
        }
        handle.write(try encoder.encode(row))
        handle.write(Data("\n".utf8))
    }

    let metaURL = outURL.deletingPathExtension().appendingPathExtension("meta.json")
    try JSONEncoder().encode(["coldLoadMs": coldLoadMs, "warmLoadMs": warmLoadMs]).write(to: metaURL)
    print("eval-voice finished \(entries.count) clips -> \(outURL.path) (cold=\(String(format: "%.1f", coldLoadMs))ms warm=\(String(format: "%.2f", warmLoadMs))ms)")
}

// MARK: - 5. Apple SpeechTranscriber Eval

struct AppleSpeechRow: Encodable {
    let id: String
    let language: String
    let category: String?
    let reference: String?
    let spoken_text: String?
    let intended_text: String?
    let transcript: String
    let audioSeconds: Double
    let prepareMs: Double
    let transcribeTotalMs: Double
    let error: String?
}

@available(macOS 26.0, *)
func ensureAppleLocale(_ identifier: String) async throws -> Locale {
    guard SpeechTranscriber.isAvailable,
          let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: identifier)) else {
        throw BenchError.runtime("Apple SpeechTranscriber unsupported for \(identifier)")
    }
    let module = SpeechTranscriber(locale: locale, preset: .timeIndexedProgressiveTranscription)
    let status = await AssetInventory.status(forModules: [module])
    if status != .installed {
        print("Installing Apple SpeechTranscriber asset for \(locale.identifier) (status=\(status))...")
        fflush(stdout)
        if let req = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
            try await req.downloadAndInstall()
        }
    }
    return locale
}

@available(macOS 26.0, *)
func runAppleSpeechClip(samples: [Float], sampleRate: Double, locale: Locale) async throws -> (text: String, prepareMs: Double, totalMs: Double) {
    let mono16 = try chunkedMono16k(samples, rate: sampleRate)
    let module = SpeechTranscriber(locale: locale, preset: .timeIndexedProgressiveTranscription)
    let analyzer = SpeechAnalyzer(modules: [module], options: .init(priority: .userInitiated, modelRetention: .whileInUse))
    guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module]),
          format.sampleRate == 16000, format.channelCount == 1,
          format.commonFormat == .pcmFormatInt16 else {
        throw BenchError.runtime("Unexpected SpeechAnalyzer format")
    }
    let streamPair = AsyncStream<AnalyzerInput>.makeStream()
    let totalStart = ContinuousClock.now
    try await analyzer.prepareToAnalyze(in: format)
    let prepareMs = ms(totalStart.duration(to: .now))

    let reader = Task {
        var chunks: [Double: String] = [:]
        for try await result in module.results where result.isFinal {
            chunks[result.range.start.seconds] = String(result.text.characters)
        }
        return chunks.keys.sorted().compactMap { chunks[$0] }.joined()
    }
    do {
        try await analyzer.start(inputSequence: streamPair.stream)
        for offset in stride(from: 0, to: mono16.count, by: 1600) {
            let count = min(1600, mono16.count - offset)
            guard let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: UInt32(count)),
                  let int16Ptr = buf.int16ChannelData?[0] else {
                throw VoiceAudioIssue.conversion
            }
            buf.frameLength = UInt32(count)
            for i in 0..<count {
                let v = mono16[offset + i]
                int16Ptr[i] = v.isFinite ? Int16(max(-1, min(1, v)) * 32767) : 0
            }
            streamPair.continuation.yield(.init(buffer: buf))
        }
        streamPair.continuation.finish()
        try await analyzer.finalizeAndFinishThroughEndOfInput()
        let text = try await reader.value
        let totalMs = ms(totalStart.duration(to: .now))
        return (text, prepareMs, totalMs)
    } catch {
        streamPair.continuation.finish()
        reader.cancel()
        await analyzer.cancelAndFinishNow()
        _ = await reader.result
        throw error
    }
}

@available(macOS 26.0, *)
func runAppleSpeech(args: [String]) async throws {
    guard let manifestPath = argValue("--manifest", in: args),
          let outPath = argValue("--out", in: args) else {
        throw BenchError.invalidArg("--manifest and --out required")
    }
    let manifestURL = URL(fileURLWithPath: manifestPath)
    let corpusRoot = manifestURL.deletingLastPathComponent()
    let entries = try JSONDecoder().decode([CorpusEntry].self, from: Data(contentsOf: manifestURL))

    let enLocale = try await ensureAppleLocale("en-US")
    let ptLocale = try await ensureAppleLocale("pt-BR")

    let outURL = URL(fileURLWithPath: outPath)
    try FileManager.default.createDirectory(at: outURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: outURL.path, contents: nil)
    let handle = try FileHandle(forWritingTo: outURL)
    defer { try? handle.close() }
    let encoder = JSONEncoder()

    for entry in entries {
        let langRaw = entry.language ?? entry.locale ?? "en-US"
        let locale = langRaw.lowercased().hasPrefix("pt") || langRaw.lowercased() == "mixed" ? ptLocale : enLocale
        let rel = entry.audio ?? "\(entry.id).wav"
        let url = corpusRoot.appending(path: rel)
        let row: AppleSpeechRow
        do {
            let (channels, rate) = try readPCMChannels(at: url)
            let mono = channels.first ?? []
            let secs = Double(mono.count) / rate
            let (text, prepMs, totMs) = try await runAppleSpeechClip(samples: mono, sampleRate: rate, locale: locale)
            row = AppleSpeechRow(
                id: entry.id, language: langRaw, category: entry.category ?? entry.scenario,
                reference: entry.reference, spoken_text: entry.spoken_text, intended_text: entry.intended_text,
                transcript: text, audioSeconds: secs, prepareMs: prepMs, transcribeTotalMs: totMs, error: nil
            )
        } catch {
            row = AppleSpeechRow(
                id: entry.id, language: langRaw, category: entry.category ?? entry.scenario,
                reference: entry.reference, spoken_text: entry.spoken_text, intended_text: entry.intended_text,
                transcript: "", audioSeconds: entry.durationSeconds ?? 0, prepareMs: 0, transcribeTotalMs: 0,
                error: String(describing: error)
            )
        }
        handle.write(try encoder.encode(row))
        handle.write(Data("\n".utf8))
    }
    print("apple-speech finished \(entries.count) clips -> \(outURL.path)")
}

// MARK: - 6. End-to-End Voice Latency Breakdown (Isolated DB + Ephemeral Pasteboard)

struct E2ELatencyTrial: Encodable {
    let id: String
    let mode: String
    let audioSeconds: Double
    let preflightCheckMs: Double
    let modelLoadMs: Double
    let modelReadyMs: Double
    let audioPrepareMs: Double
    let initializeMs: Double
    let inferenceMs: Double
    let cleanupMs: Double
    let sanitizeMs: Double
    let finishToTranscriptMs: Double
    let dbSaveAndFetchMs: Double
    let finishToScratchpadEditableMs: Double
    let dictatePrepAndCopyMs: Double
    let finishToDictateDeliveryMs: Double
}

struct E2ELatencySummary: Encodable {
    let trials: [E2ELatencyTrial]
    let coldShortcutToReadyMs: Double
    let warmShortcutToReadyP50Ms: Double
    let postIdleShortcutToReadyP50Ms: Double
    let coldFinishToTranscriptMs: Double
    let warmFinishToTranscriptP50Ms: Double
    let warmFinishToTranscriptP95Ms: Double
    let postIdleFinishToTranscriptP50Ms: Double
    let warmFinishToScratchpadP50Ms: Double
    let warmFinishToScratchpadP95Ms: Double
    let warmFinishToDictateP50Ms: Double
    let warmFinishToDictateP95Ms: Double
}

func percentile(_ values: [Double], _ p: Double) -> Double {
    let s = values.sorted()
    guard !s.isEmpty else { return 0 }
    let idx = min(s.count - 1, max(0, Int(ceil(Double(s.count) * p)) - 1))
    return s[idx]
}

@MainActor
private func measurePreflightChecks() -> Double {
    let t0 = ContinuousClock.now
    _ = AVCaptureDevice.authorizationStatus(for: .audio)
    _ = AXIsProcessTrusted()
    if let dict = CGSessionCopyCurrentDictionary() as? [String: Any] {
        _ = dict["CGSSessionSecureInputPID"]
    }
    return ms(t0.duration(to: .now))
}

@MainActor
private func measureDictatePrepAndCopy(_ cleaned: String) -> Double {
    let pasteboard = NSPasteboard.withUniqueName()
    defer { pasteboard.releaseGlobally() }
    let t0 = ContinuousClock.now
    let dictateText = VoiceTextInsertion.textWithSmartLeadingSpace(cleaned, precedingCharacter: " ")
    _ = VoiceTextInsertion.copy(dictateText, to: pasteboard)
    return ms(t0.duration(to: .now))
}

func runE2ELatency(args: [String]) async throws {
    guard let manifestPath = argValue("--manifest", in: args),
          let outPath = argValue("--out", in: args) else {
        throw BenchError.invalidArg("--manifest and --out required")
    }
    let limit = Int(argValue("--limit", in: args) ?? "12") ?? 12
    let manifestURL = URL(fileURLWithPath: manifestPath)
    let corpusRoot = manifestURL.deletingLastPathComponent()
    let entries = Array(try JSONDecoder().decode([CorpusEntry].self, from: Data(contentsOf: manifestURL)).prefix(max(3, limit)))

    let baseDir = FileManager.default.temporaryDirectory.appending(path: "rasc-e2e-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: baseDir) }
    let repo = try NoteRepository(databaseURL: baseDir.appending(path: "Rasc.sqlite"))

    let model = VoiceModel()
    var trials: [E2ELatencyTrial] = []

    func runSingle(entry: CorpusEntry, mode: String, releaseFirst: Bool, sleepBefore: Bool) async throws -> E2ELatencyTrial {
        if releaseFirst { await model.release() }
        if sleepBefore { try await Task.sleep(for: .milliseconds(500)) }
        let url = corpusRoot.appending(path: entry.audio ?? "\(entry.id).wav")
        let (channels, rate) = try readPCMChannels(at: url)
        let audio = VoiceAudio(samples: channels.first ?? [], rate: rate, peak: 1.0, activitySeconds: Double(channels.first?.count ?? 0) / rate)

        let preflightMs = await MainActor.run { measurePreflightChecks() }
        let tStart = ContinuousClock.now
        let rawText = try await model.transcribe(audio, modelReady: {})
        let tTransEnd = ContinuousClock.now
        let timing = await model.lastTiming

        let tSan0 = ContinuousClock.now
        let cleaned = VoiceTranscriptSanitizer.clean(rawText)
        let sanitizeMs = ms(tSan0.duration(to: .now))

        let tDb0 = ContinuousClock.now
        let note = try await repo.createScratch(content: cleaned, origin: .scratch)
        _ = try await repo.fetchEditable(id: note.id)
        let dbMs = ms(tDb0.duration(to: .now))

        let dictateMs = await MainActor.run { measureDictatePrepAndCopy(cleaned) }

        let finishToTranscript = ms(tStart.duration(to: tTransEnd)) + sanitizeMs
        return E2ELatencyTrial(
            id: entry.id,
            mode: mode,
            audioSeconds: audio.seconds,
            preflightCheckMs: preflightMs,
            modelLoadMs: timing.modelLoadMs,
            modelReadyMs: timing.modelReadyMs,
            audioPrepareMs: timing.audioPrepareMs,
            initializeMs: timing.initializeMs,
            inferenceMs: timing.inferenceMs,
            cleanupMs: timing.cleanupMs,
            sanitizeMs: sanitizeMs,
            finishToTranscriptMs: finishToTranscript,
            dbSaveAndFetchMs: dbMs,
            finishToScratchpadEditableMs: finishToTranscript + dbMs,
            dictatePrepAndCopyMs: dictateMs,
            finishToDictateDeliveryMs: finishToTranscript + dictateMs
        )
    }

    // 1. Cold first use
    trials.append(try await runSingle(entry: entries[0], mode: "cold", releaseFirst: true, sleepBefore: false))
    // 2. Warm runs
    for entry in entries {
        trials.append(try await runSingle(entry: entry, mode: "warm", releaseFirst: false, sleepBefore: false))
    }
    // 3. Post-idle-release runs (model leased/released between notes, warm OS page cache)
    for entry in entries.prefix(5) {
        trials.append(try await runSingle(entry: entry, mode: "post_idle_release", releaseFirst: true, sleepBefore: true))
    }

    let cold = trials.first { $0.mode == "cold" }!
    let warm = trials.filter { $0.mode == "warm" }
    let postIdle = trials.filter { $0.mode == "post_idle_release" }

    let summary = E2ELatencySummary(
        trials: trials,
        coldShortcutToReadyMs: cold.preflightCheckMs,
        warmShortcutToReadyP50Ms: median(warm.map(\.preflightCheckMs)),
        postIdleShortcutToReadyP50Ms: median(postIdle.map(\.preflightCheckMs)),
        coldFinishToTranscriptMs: cold.finishToTranscriptMs,
        warmFinishToTranscriptP50Ms: median(warm.map(\.finishToTranscriptMs)),
        warmFinishToTranscriptP95Ms: percentile(warm.map(\.finishToTranscriptMs), 0.95),
        postIdleFinishToTranscriptP50Ms: median(postIdle.map(\.finishToTranscriptMs)),
        warmFinishToScratchpadP50Ms: median(warm.map(\.finishToScratchpadEditableMs)),
        warmFinishToScratchpadP95Ms: percentile(warm.map(\.finishToScratchpadEditableMs), 0.95),
        warmFinishToDictateP50Ms: median(warm.map(\.finishToDictateDeliveryMs)),
        warmFinishToDictateP95Ms: percentile(warm.map(\.finishToDictateDeliveryMs), 0.95)
    )

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(summary).write(to: URL(fileURLWithPath: outPath))
    print("e2e-latency: cold=\(String(format: "%.1f", summary.coldFinishToTranscriptMs))ms warmP50=\(String(format: "%.1f", summary.warmFinishToTranscriptP50Ms))ms scratchP50=\(String(format: "%.1f", summary.warmFinishToScratchpadP50Ms))ms postIdleP50=\(String(format: "%.1f", summary.postIdleFinishToTranscriptP50Ms))ms")
}

// MARK: - 7. Curated Text Note Refine Eval (Live Foundation Models)

struct EvalRefineInput: Decodable {
    let id: String
    let category: String
    let language: String
    let text: String
    let expectedBehavior: String
}

struct EvalRefineRow: Encodable {
    let id: String
    let category: String
    let language: String
    let inputText: String
    let expectedBehavior: String
    let availability: String
    let decision: String?
    let kind: String?
    let resolvedLocale: String?
    let resolverConfidence: String?
    let decisionReason: String?
    let latencyMs: Double
    let outputText: String?
    let error: String?
}

func runEvalRefine(args: [String]) async throws {
    guard let inPath = argValue("--in", in: args),
          let outPath = argValue("--out", in: args) else {
        throw BenchError.invalidArg("--in and --out required")
    }
    let lines = try String(contentsOfFile: inPath, encoding: .utf8).split(separator: "\n")
    let decoder = JSONDecoder()
    let inputs = try lines.map { try decoder.decode(EvalRefineInput.self, from: Data($0.utf8)) }

    let provider = FoundationModelsRefinementProvider()
    let probeReq = RefinementRequest(snapshot: NoteSnapshot(noteID: UUID(), revision: 1, text: inputs.first?.text ?? "hello"))
    let avail = await provider.availability(for: probeReq)
    let availString = String(describing: avail)

    var rows: [EvalRefineRow] = []
    for item in inputs {
        let req = RefinementRequest(snapshot: NoteSnapshot(noteID: UUID(), revision: 1, text: item.text))
        let t0 = ContinuousClock.now
        do {
            let res = try await provider.refine(req)
            let dt = ms(t0.duration(to: .now))
            rows.append(EvalRefineRow(
                id: item.id, category: item.category, language: item.language,
                inputText: item.text, expectedBehavior: item.expectedBehavior,
                availability: availString,
                decision: res.decision.rawValue,
                kind: res.kind.rawValue,
                resolvedLocale: res.languageTrace?.resolvedLocale,
                resolverConfidence: res.languageTrace?.resolverConfidence,
                decisionReason: res.languageTrace?.decisionReason,
                latencyMs: dt,
                outputText: res.text,
                error: nil
            ))
        } catch {
            let dt = ms(t0.duration(to: .now))
            rows.append(EvalRefineRow(
                id: item.id, category: item.category, language: item.language,
                inputText: item.text, expectedBehavior: item.expectedBehavior,
                availability: availString,
                decision: nil, kind: nil, resolvedLocale: nil, resolverConfidence: nil, decisionReason: nil,
                latencyMs: dt, outputText: nil, error: String(describing: error)
            ))
        }
    }

    let outURL = URL(fileURLWithPath: outPath)
    try FileManager.default.createDirectory(at: outURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(rows).write(to: outURL)
    print("eval-refine finished \(rows.count) cases (availability=\(availString)) -> \(outURL.path)")
}

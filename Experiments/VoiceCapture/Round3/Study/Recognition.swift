import AVFoundation
import CoreML
import FluidAudio
import Foundation
import Speech

enum StudyEngine: String, CaseIterable, Identifiable, Sendable {
    case apple, fluid, ultra
    var id: Self { self }
    var title: String {
        switch self {
        case .apple: "Apple SpeechTranscriber"
        case .fluid: "Fluid Speech Pro"
        case .ultra: "Parakeet Ultra"
        }
    }
    var folder: String {
        switch self {
        case .apple: ""
        case .fluid: "fluid-pro"
        case .ultra: "ultra"
        }
    }
    var assetRevision: String {
        switch self {
        case .apple: "system"
        case .fluid: "3b9d38a93d606f84011e5a0a669b7ea146375a22"
        case .ultra: "95eaa59a39d4394f047a4dc5cce480388a60d1b6"
        }
    }
    var fluidVersion: AsrModelVersion { self == .fluid ? .fluidParakeetPro : .v3 }

}

enum RecognitionIssue: LocalizedError {
    case unavailable, needsSetup, noTranscript, timedOut
    var errorDescription: String? {
        switch self {
        case .unavailable: "This speech model or language is unavailable on this Mac."
        case .needsSetup: "Set up the speech model before recording."
        case .noTranscript: "No speech was recognized."
        case .timedOut: "Transcription took too long."
        }
    }
}

actor StudyRecognizer {
    private struct Preparation {
        let engine: StudyEngine
        let id: UUID
        let task: Task<AsrModels, any Error>
    }

    private struct Prediction {
        let id: UUID
        let task: Task<(String, Double), any Error>
    }

    private var prepared: (engine: StudyEngine, id: UUID, models: AsrModels)?
    private var loading: Preparation?
    private var decoding: Prediction?
    private var expiry: Task<Void, Never>?
    private var leaseID: UUID?
    private var discardAfterPrediction = false
    private let retention: Duration
    private let compute: ModelCompute

    init(retention: Duration = .seconds(180), compute: ModelCompute = PortableAssets.defaultCompute) {
        self.retention = retention
        self.compute = compute
    }

    nonisolated static func ready(_ engine: StudyEngine, language: String) async throws -> Bool {
        if engine != .apple { return (try? PortableAssets.verifiedFolder(engine)) != nil }
        guard SpeechTranscriber.isAvailable,
              let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: language)) else {
            throw RecognitionIssue.unavailable
        }
        let module = SpeechTranscriber(locale: locale, preset: .timeIndexedProgressiveTranscription)
        return await AssetInventory.status(forModules: [module]) == .installed
    }

    nonisolated static func installApple(language: String) async throws {
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: language)) else {
            throw RecognitionIssue.unavailable
        }
        let module = SpeechTranscriber(locale: locale, preset: .timeIndexedProgressiveTranscription)
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
            try await request.downloadAndInstall()
        }
    }

    func decode(_ frames: [Float], engine: StudyEngine, language: String,
                onPartial: @escaping @Sendable () -> Void = {},
                onModelReady: @escaping @Sendable () -> Void = {}) async throws -> (String, Double) {
        if engine == .apple { return try await SpeechDecode.run(frames, language: language, onPartial: onPartial) }

        // A Core ML call may finish after its waiter cancels. Keep the slot until
        // the operation actually returns, so a retry cannot overlap its inference.
        while let previous = decoding {
            _ = await previous.task.result
            finishPrediction(previous.id)
            try Task.checkCancellation()
        }
        try Task.checkCancellation()
        let id = UUID()
        let task = Task {
            let started = ContinuousClock.now
            let models = try await portableModels(engine)
            let elapsed = milliseconds(started)
            try Task.checkCancellation()
            onModelReady()
            // TDT requires one second of input. A suffix keeps the real onset
            // and speech samples unchanged.
            let padded = frames.count < 16000 ? frames + Array(repeating: 0, count: 16000 - frames.count) : frames
            return (try await Self.transcribe(padded, models: models), elapsed)
        }
        decoding = Prediction(id: id, task: task)
        defer { finishPrediction(id) }
        return try await withTaskCancellationHandler {
            let result = try await task.value
            try Task.checkCancellation()
            return result
        } onCancel: {
            task.cancel()
        }
    }

    private func finishPrediction(_ id: UUID) {
        guard decoding?.id == id else { return }
        decoding = nil
        if discardAfterPrediction {
            discardAfterPrediction = false
            releaseLoadedModel()
        } else if prepared != nil {
            extendRetention()
        }
    }

    static func transcribe(_ frames: [Float], models: AsrModels) async throws -> String {
        let manager = AsrManager()
        do {
            try await manager.initialize(models: models)
            let result = try await manager.transcribe(frames, source: .microphone)
            try Task.checkCancellation()
            await manager.cleanup()
            return result.text
        } catch {
            await manager.cleanup()
            throw error
        }
    }

    func preparePortable(_ engine: StudyEngine) async throws {
        _ = try await portableModels(engine)
    }

    private func portableModels(_ engine: StudyEngine) async throws -> AsrModels {
        try Task.checkCancellation()
        if let prepared, prepared.engine == engine {
            extendRetention()
            return prepared.models
        }
        while let previous = loading, previous.engine != engine || previous.task.isCancelled {
            previous.task.cancel()
            _ = await previous.task.result
            if loading?.id == previous.id { loading = nil }
            try Task.checkCancellation()
            if let prepared, prepared.engine == engine {
                extendRetention()
                return prepared.models
            }
        }

        let preparation: Preparation
        if let loading {
            preparation = loading
        } else {
            dropPreparedModel()
            let folder = try PortableAssets.verifiedFolder(engine)
            let task = Task { try await PortableAssets.load(engine, at: folder, compute: compute).models }
            preparation = Preparation(engine: engine, id: UUID(), task: task)
            loading = preparation
        }

        do {
            let models = try await preparation.task.value
            guard !preparation.task.isCancelled else { throw CancellationError() }
            if loading?.id == preparation.id {
                loading = nil
                prepared = (engine, preparation.id, models)
                extendRetention()
            }
            guard prepared?.id == preparation.id else { throw CancellationError() }
            try Task.checkCancellation()
            return models
        } catch {
            if loading?.id == preparation.id { loading = nil }
            throw error
        }
    }

    func cacheState() -> String {
        if loading != nil { return "loading" }
        return prepared == nil ? "released" : "prepared"
    }

    func isPrepared(_ engine: StudyEngine) -> Bool { prepared?.engine == engine }

    private func extendRetention() {
        expiry?.cancel()
        let id = UUID()
        leaseID = id
        expiry = Task { [weak self, retention] in
            do { try await Task.sleep(for: retention) }
            catch { return }
            await self?.expirePreparedModel(id)
        }
    }

    private func expirePreparedModel(_ id: UUID) {
        guard leaseID == id, decoding == nil else { return }
        dropPreparedModel()
    }

    private func dropPreparedModel() {
        prepared = nil
        expiry?.cancel()
        expiry = nil
        leaseID = nil
    }

    func cancelPreparation() {
        // Retain an already-prepared model after cancelling a recording.
        // The in-flight slot is cleared by its waiter, not abandoned.
        loading?.task.cancel()
    }

    func releaseLoadedModel() {
        cancelPreparation()
        dropPreparedModel()
    }

    func releaseForMemoryPressure() {
        if decoding != nil { discardAfterPrediction = true }
        else { releaseLoadedModel() }
    }
}

enum SpeechDecode {
    static func run(_ frames: [Float], language: String,
                    onPartial: @escaping @Sendable () -> Void) async throws -> (String, Double) {
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: language)) else {
            throw RecognitionIssue.unavailable
        }
        let module = SpeechTranscriber(locale: locale, preset: .timeIndexedProgressiveTranscription)
        guard await AssetInventory.status(forModules: [module]) == .installed else {
            throw RecognitionIssue.needsSetup
        }
        let analyzer = SpeechAnalyzer(modules: [module], options: .init(priority: .userInitiated, modelRetention: .whileInUse))
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module]),
              format.sampleRate == 16000, format.channelCount == 1,
              format.commonFormat == .pcmFormatInt16 else { throw AudioIssue.conversion }
        let input = AsyncStream<AnalyzerInput>.makeStream()
        return try await withTaskCancellationHandler {
            let started = ContinuousClock.now
            try await analyzer.prepareToAnalyze(in: format)
            try Task.checkCancellation()
            let prepareTime = milliseconds(started)
            let reader = Task {
                var final: [Double: String] = [:]
                var seenPartial = false
                for try await result in module.results {
                    if result.isFinal {
                        final[result.range.start.seconds] = String(result.text.characters)
                    } else if !seenPartial {
                        onPartial()
                        seenPartial = true
                    }
                }
                return final.keys.sorted().compactMap { final[$0] }.joined()
            }
            do {
                try await analyzer.start(inputSequence: input.stream)
                for offset in stride(from: 0, to: frames.count, by: 1600) {
                    try Task.checkCancellation()
                    let count = min(1600, frames.count - offset)
                    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: UInt32(count)),
                          let samples = buffer.int16ChannelData?[0] else { throw AudioIssue.conversion }
                    buffer.frameLength = UInt32(count)
                    for position in 0..<count {
                        let value = frames[offset + position]
                        samples[position] = value.isFinite ? Int16(max(-1, min(1, value)) * 32767) : 0
                    }
                    input.continuation.yield(.init(buffer: buffer))
                }
                input.continuation.finish()
                try await analyzer.finalizeAndFinishThroughEndOfInput()
                return (try await reader.value, prepareTime)
            } catch {
                input.continuation.finish()
                reader.cancel()
                await analyzer.cancelAndFinishNow()
                _ = await reader.result
                throw error
            }
        } onCancel: {
            input.continuation.finish()
            Task { await analyzer.cancelAndFinishNow() }
        }
    }
}

func milliseconds(_ start: ContinuousClock.Instant, to end: ContinuousClock.Instant = .now) -> Double {
    let value = start.duration(to: end).components
    return Double(value.seconds) * 1000 + Double(value.attoseconds) / 1e15
}

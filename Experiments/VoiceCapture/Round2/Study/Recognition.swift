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
        case .apple: "Apple Speech"
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
}

enum RecognitionIssue: LocalizedError {
    case unavailable, needsSetup, noTranscript
    var errorDescription: String? {
        switch self {
        case .unavailable: "This speech model or language is unavailable on this Mac."
        case .needsSetup: "Set up the speech model before recording."
        case .noTranscript: "Rasc couldn’t find words in this recording."
        }
    }
}

actor StudyRecognizer {
    private struct LoadedModel {
        let engine: StudyEngine
        let models: AsrModels
        let time: ContinuousClock.Instant
    }
    private var cached: LoadedModel?
    private var expiry: Task<Void, Never>?

    nonisolated private static func directory(_ engine: StudyEngine) -> URL? {
        Bundle.main.resourceURL?.appending(path: "Models/\(engine.folder)", directoryHint: .isDirectory)
    }

    nonisolated static func ready(_ engine: StudyEngine, language: String) async throws -> Bool {
        if engine != .apple {
            guard let folder = directory(engine) else { return false }
            return FileManager.default.fileExists(atPath: folder.appending(path: "provenance.json").path)
        }
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

    func decode(_ frames: [Float], engine: StudyEngine, language: String, override: URL? = nil,
                onPartial: @escaping @Sendable () -> Void = {}) async throws -> (String, Double) {
        if engine == .apple { return try await SpeechDecode.run(frames, language: language, onPartial: onPartial) }
        let start = ContinuousClock.now
        let models = try await portableModels(engine, override: override)
        let elapsed = milliseconds(start)
        let manager = AsrManager()
        try await manager.initialize(models: models)
        defer { Task { await manager.cleanup() } }
        let result = try await manager.transcribe(frames, source: .microphone)
        try Task.checkCancellation()
        if override == nil { retain(models, engine: engine) }
        return (result.text, elapsed)
    }

    func preparePortable(_ engine: StudyEngine) async throws {
        let models = try await portableModels(engine)
        try Task.checkCancellation()
        retain(models, engine: engine)
    }

    private func portableModels(_ engine: StudyEngine, override: URL? = nil) async throws -> AsrModels {
        if override == nil, let cached, cached.engine == engine { return cached.models }
        guard let folder = override ?? Self.directory(engine) else { throw RecognitionIssue.needsSetup }
        let version: AsrModelVersion = engine == .fluid ? .fluidParakeetPro : .v3
        let models = try await AsrModels.loadLocalOnly(from: folder, version: version)
        try Task.checkCancellation()
        return models
    }

    private func retain(_ models: AsrModels, engine: StudyEngine) {
        let now = ContinuousClock.now
        cached = LoadedModel(engine: engine, models: models, time: now)
        expiry?.cancel()
        expiry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled else { return }
            await self?.releaseLoadedModel(started: now)
        }
    }

    func releaseLoadedModel(started: ContinuousClock.Instant? = nil) {
        guard started == nil || started == cached?.time else { return }
        cached = nil
        expiry?.cancel()
        expiry = nil
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
                        samples[position] = Int16((max(-1, min(1, frames[offset + position]))) * 32767)
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

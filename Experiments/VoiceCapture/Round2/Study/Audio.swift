import AVFoundation
import Accelerate
import Foundation

enum AudioIssue: LocalizedError {
    case noInput, noFrames, conversion
    var errorDescription: String? {
        switch self {
        case .noInput: "Rasc couldn’t open a microphone. Check the input in System Settings."
        case .noFrames: "Rasc didn’t receive any microphone audio."
        case .conversion: "Rasc couldn’t prepare this recording for transcription."
        }
    }
}

struct StudyAudio: Sendable {
    let samples: [Float]
    let rate: Double
    let peak: Float
    var seconds: Double { Double(samples.count) / rate }

    // Conversion is performed outside the real-time audio callback.
    func mono16k() throws -> [Float] {
        guard !samples.isEmpty else { throw AudioIssue.noFrames }
        if rate == 16000 { return samples }
        guard let inputFormat = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1),
              let outputFormat = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1),
              let input = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: UInt32(samples.count)),
              let output = AVAudioPCMBuffer(pcmFormat: outputFormat,
                                            frameCapacity: UInt32(ceil(seconds * 16000) + 1024)),
              let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw AudioIssue.conversion
        }
        input.frameLength = UInt32(samples.count)
        samples.withUnsafeBufferPointer { source in
            if let address = source.baseAddress { input.floatChannelData?[0].update(from: address, count: source.count) }
        }
        let feeder = Feeder(input)
        var error: NSError?
        let result = converter.convert(to: output, error: &error) { _, status in
            if feeder.used {
                status.pointee = .endOfStream
                return nil
            }
            feeder.used = true
            status.pointee = .haveData
            return feeder.buffer
        }
        guard result != .error, let values = output.floatChannelData?[0], output.frameLength > 0 else {
            throw AudioIssue.conversion
        }
        return Array(UnsafeBufferPointer(start: values, count: Int(output.frameLength)))
    }

    private final class Feeder: @unchecked Sendable {
        let buffer: AVAudioPCMBuffer
        var used = false
        init(_ buffer: AVAudioPCMBuffer) { self.buffer = buffer }
    }
}

final class MicBuffer: @unchecked Sendable {
    struct Status {
        let count: Int
        let rms: Float
        let first: ContinuousClock.Instant?
        let full: Bool
    }

    let rate: Double
    private let limit: Int
    private let lock = NSLock()
    private var storage: [Float] = []
    private var level: Float = 0
    private var peak: Float = 0
    private var first: ContinuousClock.Instant?

    init(rate: Double) {
        self.rate = rate
        limit = Int(rate * 90)
        storage.reserveCapacity(limit)
    }

    func append(_ block: AVAudioPCMBuffer) {
        guard let channel = block.floatChannelData?[0] else { return }
        let timestamp = ContinuousClock.now
        lock.withLock {
            let count = min(Int(block.frameLength), limit - storage.count)
            guard count > 0 else { return }
            if first == nil { first = timestamp }
            let values = UnsafeBufferPointer(start: channel, count: count)
            storage.append(contentsOf: values)
            level = vDSP.rootMeanSquare(values)
            peak = max(peak, level)
        }
    }

    func status() -> Status {
        lock.withLock { Status(count: storage.count, rms: level, first: first, full: storage.count == limit) }
    }

    func audio() -> StudyAudio {
        lock.withLock { StudyAudio(samples: storage, rate: rate, peak: peak) }
    }
}

actor Microphone {
    private var engine: AVAudioEngine?
    private var input: AVAudioInputNode?
    private var changes: (any NSObjectProtocol)?
    private var owner: UUID?

    func start(id: UUID, onRouteChange: @escaping @Sendable () -> Void) throws -> MicBuffer {
        guard owner == nil else { throw AudioIssue.noInput }
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0, format.commonFormat == .pcmFormatFloat32,
              !format.isInterleaved else { throw AudioIssue.noInput }
        let buffer = MicBuffer(rate: format.sampleRate)
        input.installTap(onBus: 0, bufferSize: 512, format: format) { block, _ in buffer.append(block) }
        do {
            engine.prepare()
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            engine.stop()
            throw error
        }
        self.engine = engine
        self.input = input
        owner = id
        changes = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine,
                                                         queue: nil) { _ in onRouteChange() }
        return buffer
    }

    func stop(id: UUID) {
        guard owner == id else { return }
        if let changes { NotificationCenter.default.removeObserver(changes) }
        input?.removeTap(onBus: 0)
        engine?.stop()
        changes = nil
        engine = nil
        input = nil
        owner = nil
    }
}

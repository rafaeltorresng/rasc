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
    let activitySeconds: Double
    var seconds: Double { Double(samples.count) / rate }

    // Conversion is performed outside the real-time audio callback.
    func mono16k() throws -> [Float] {
        guard !samples.isEmpty else { throw AudioIssue.noFrames }
        guard rate.isFinite, (8000...192000).contains(rate) else { throw AudioIssue.conversion }
        if rate == 16000 { return Self.finite(samples) }
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
        return Self.finite(Array(UnsafeBufferPointer(start: values, count: Int(output.frameLength))))
    }

    private static func finite(_ frames: [Float]) -> [Float] {
        if frames.allSatisfy(\.isFinite) { return frames }
        return frames.map { $0.isFinite ? $0 : 0 }
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
        let last: ContinuousClock.Instant?
        let full: Bool
    }

    let rate: Double
    private let limit: Int
    private let retainsAudio: Bool
    private let lock = NSLock()
    private var storage: [Float] = []
    private var frameCount = 0
    private var level: Float = 0
    private var peak: Float = 0
    private var activeFrames = 0
    private var windowFrames = 0
    private var windowEnergy: Float = 0
    private var sealed = false
    private var first: ContinuousClock.Instant?
    private var last: ContinuousClock.Instant?

    init(rate: Double, retainsAudio: Bool = true) {
        self.rate = rate
        self.retainsAudio = retainsAudio
        limit = Int(rate * 90)
        if retainsAudio { storage.reserveCapacity(limit) }
    }

    func append(_ block: AVAudioPCMBuffer) {
        guard let channel = block.floatChannelData?[0] else { return }
        append(UnsafeBufferPointer(start: channel, count: Int(block.frameLength)))
    }

    func append(_ frames: UnsafeBufferPointer<Float>) {
        let timestamp = ContinuousClock.now
        lock.withLock {
            guard !sealed else { return }
            let count = min(frames.count, limit - frameCount)
            guard count > 0, let base = frames.baseAddress else { return }
            if first == nil { first = timestamp }
            last = timestamp
            frameCount += count
            guard retainsAudio else { return }
            let values = UnsafeBufferPointer(start: base, count: count)
            storage.append(contentsOf: values)
            let rms = vDSP.rootMeanSquare(values)
            let blockPeak = vDSP.maximumMagnitude(values)
            level = rms.isFinite ? rms : 0
            if blockPeak.isFinite { peak = max(peak, blockPeak) }
            // Keep fixed 10 ms windows across callback boundaries. Small tap
            // blocks must not change how many windows a transient can count.
            let step = max(1, Int(rate / 100))
            var offset = 0
            while offset < count {
                let length = min(step - windowFrames, count - offset)
                let window = UnsafeBufferPointer(start: base.advanced(by: offset), count: length)
                let energy = vDSP.sumOfSquares(window)
                if energy.isFinite { windowEnergy += energy }
                windowFrames += length
                if windowFrames == step {
                    if windowEnergy > Float(step) * 0.000004 { activeFrames += step }
                    windowFrames = 0
                    windowEnergy = 0
                }
                offset += length
            }
        }
    }

    func status() -> Status {
        lock.withLock { Status(count: frameCount, rms: level, first: first, last: last, full: frameCount == limit) }
    }

    func audio() -> StudyAudio {
        lock.withLock {
            sealed = true
            let remainder = windowEnergy > Float(windowFrames) * 0.000004 ? windowFrames : 0
            return StudyAudio(samples: storage, rate: rate, peak: peak,
                              activitySeconds: Double(activeFrames + remainder) / rate)
        }
    }
}

actor Microphone {
    private var engine: AVAudioEngine?
    private var input: AVAudioInputNode?
    private var changes: (any NSObjectProtocol)?
    private var owner: UUID?

    func start(id: UUID, retainsAudio: Bool = true, onRouteChange: @escaping @Sendable () -> Void) throws -> MicBuffer {
        guard owner == nil else { throw AudioIssue.noInput }
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard (8000...192000).contains(format.sampleRate), format.channelCount > 0, format.commonFormat == .pcmFormatFloat32,
              !format.isInterleaved else { throw AudioIssue.noInput }
        let buffer = MicBuffer(rate: format.sampleRate, retainsAudio: retainsAudio)
        self.engine = engine
        self.input = input
        owner = id
        changes = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine,
                                                         queue: nil) { _ in onRouteChange() }
        input.installTap(onBus: 0, bufferSize: 512, format: format) { block, _ in buffer.append(block) }
        do {
            engine.prepare()
            try engine.start()
        } catch {
            stop(id: id)
            throw AudioIssue.noInput
        }
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

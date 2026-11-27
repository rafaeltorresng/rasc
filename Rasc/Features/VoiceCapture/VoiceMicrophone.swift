import AVFoundation
import Accelerate
import Foundation

enum VoiceAudioIssue: LocalizedError {
    case noInput, noFrames, conversion
    var errorDescription: String? {
        switch self {
        case .noInput: "Rasc couldn’t open a microphone. Check the input in System Settings."
        case .noFrames: "Rasc didn’t receive any microphone audio."
        case .conversion: "Rasc couldn’t prepare this recording for transcription."
        }
    }
}

struct VoiceAudio: Sendable {
    let samples: [Float]
    let rate: Double
    let peak: Float
    let activitySeconds: Double
    var seconds: Double { Double(samples.count) / rate }

    // Conversion is performed outside the real-time audio callback.
    func mono16k() throws -> [Float] {
        guard !samples.isEmpty else { throw VoiceAudioIssue.noFrames }
        guard rate.isFinite, (8000...192000).contains(rate) else { throw VoiceAudioIssue.conversion }
        if rate == 16000 { return Self.finite(samples) }
        guard let inputFormat = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1),
              let outputFormat = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1),
              let input = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: UInt32(samples.count)),
              let output = AVAudioPCMBuffer(pcmFormat: outputFormat,
                                            frameCapacity: UInt32(ceil(seconds * 16000) + 1024)),
              let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw VoiceAudioIssue.conversion
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
            throw VoiceAudioIssue.conversion
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
    static let defaultMaxDurationSeconds: Double = 300

    struct Status {
        let count: Int
        let rms: Float
        let first: ContinuousClock.Instant?
        let last: ContinuousClock.Instant?
        let full: Bool
        let elapsedSeconds: Double
        let remainingSeconds: Double
    }

    let rate: Double
    let maxDurationSeconds: Double
    private let limit: Int
    private let chunkCapacity: Int
    private let lock = NSLock()
    private var chunks: [[Float]] = []
    private var frameCount = 0
    private var level: Float = 0
    private var peak: Float = 0
    private var activeFrames = 0
    private var windowFrames = 0
    private var windowEnergy: Float = 0
    private var sealed = false
    private var first: ContinuousClock.Instant?
    private var last: ContinuousClock.Instant?

    init(rate: Double, maxDurationSeconds: Double = defaultMaxDurationSeconds) {
        self.rate = rate
        self.maxDurationSeconds = maxDurationSeconds
        limit = max(1, Int(rate * maxDurationSeconds))
        chunkCapacity = max(1, min(limit, Int(rate * 5)))
    }

    func append(_ block: AVAudioPCMBuffer) {
        let frameLength = Int(block.frameLength)
        guard frameLength > 0, let channelData = block.floatChannelData else { return }
        let channelCount = Int(block.format.channelCount)
        guard channelCount > 0 else { return }

        if channelCount == 1 {
            append(UnsafeBufferPointer(start: channelData[0], count: frameLength))
            return
        }

        var selectedChannel = 0
        var bestMagnitude: Float = 0
        for channelIndex in 0..<channelCount {
            let channelBuffer = UnsafeBufferPointer(start: channelData[channelIndex], count: frameLength)
            let channelPeak = vDSP.maximumMagnitude(channelBuffer)
            if channelPeak.isFinite, channelPeak > bestMagnitude {
                bestMagnitude = channelPeak
                selectedChannel = channelIndex
            }
        }
        append(UnsafeBufferPointer(start: channelData[selectedChannel], count: frameLength))
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
            var appended = 0
            while appended < count {
                if chunks.isEmpty || chunks[chunks.count - 1].count >= chunkCapacity {
                    var nextChunk: [Float] = []
                    nextChunk.reserveCapacity(chunkCapacity)
                    chunks.append(nextChunk)
                }
                let lastIndex = chunks.count - 1
                let room = chunkCapacity - chunks[lastIndex].count
                let sliceLength = min(room, count - appended)
                let slice = UnsafeBufferPointer(start: base.advanced(by: appended), count: sliceLength)
                chunks[lastIndex].append(contentsOf: slice)
                appended += sliceLength
            }
            let values = UnsafeBufferPointer(start: base, count: count)
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
        lock.withLock {
            let elapsed = Double(frameCount) / rate
            let remaining = max(0, Double(limit - frameCount) / rate)
            return Status(
                count: frameCount,
                rms: level,
                first: first,
                last: last,
                full: frameCount == limit,
                elapsedSeconds: elapsed,
                remainingSeconds: remaining
            )
        }
    }

    func audio() -> VoiceAudio {
        lock.withLock {
            sealed = true
            let remainder = windowEnergy > Float(windowFrames) * 0.000004 ? windowFrames : 0
            let finalSamples: [Float]
            if chunks.isEmpty {
                finalSamples = []
            } else if chunks.count == 1 {
                let only = chunks[0]
                if only.count < only.capacity / 2 {
                    finalSamples = only.withUnsafeBufferPointer { Array($0) }
                } else {
                    finalSamples = only
                }
            } else {
                var flattened: [Float] = []
                flattened.reserveCapacity(frameCount)
                for chunk in chunks {
                    flattened.append(contentsOf: chunk)
                }
                finalSamples = flattened
            }
            chunks = []
            return VoiceAudio(samples: finalSamples, rate: rate, peak: peak,
                              activitySeconds: Double(activeFrames + remainder) / rate)
        }
    }
}

actor VoiceMicrophone {
    private var engine: AVAudioEngine?
    private var input: AVAudioInputNode?
    private var changes: (any NSObjectProtocol)?
    private var owner: UUID?

    func start(id: UUID, onRouteChange: @escaping @Sendable () -> Void) throws -> MicBuffer {
        try Task.checkCancellation()
        guard owner == nil else { throw VoiceAudioIssue.noInput }
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard (8000...192000).contains(format.sampleRate), format.channelCount > 0, format.commonFormat == .pcmFormatFloat32,
              !format.isInterleaved else { throw VoiceAudioIssue.noInput }
        let buffer = MicBuffer(rate: format.sampleRate)
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
            throw VoiceAudioIssue.noInput
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

import AVFoundation
import Foundation

enum LocalBenchmark {
    static func run(_ args: [String]) async {
        guard args.count > 2, let engine = StudyEngine(rawValue: args[0]), let resources = Bundle.main.resourceURL else {
            print("usage: --benchmark ENGINE LOCALE NAME.wav... (resource files)")
            exit(2)
        }
        var options = Array(args.dropFirst(2))
        var compute = PortableAssets.defaultCompute
        var lead = 0
        while let option = options.first, option.contains("=") {
            options.removeFirst()
            if option.hasPrefix("compute="), let mode = ModelCompute(rawValue: String(option.dropFirst(8))) {
                compute = mode
            } else if option.hasPrefix("lead="), let count = Int(option.dropFirst(5)), (0...3200).contains(count) {
                lead = count
            } else { exit(2) }
        }
        let recognizer = StudyRecognizer(compute: compute)
        for filename in options {
            do {
                let file = Array(repeating: Float.zero, count: lead) + (try loadFixture(resources.appending(path: filename)))
                let start = ContinuousClock.now
                let (text, prepare) = try await recognizer.decode(file, engine: engine, language: args[1])
                output(["engine": engine.rawValue, "fixture": filename, "transcript": text,
                        "prepare_ms": prepare, "finish_ms": milliseconds(start)])
            } catch {
                output(["engine": engine.rawValue, "fixture": filename, "error": error.localizedDescription])
            }
        }
        exit(0)
    }

    static func loadFixture(_ url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        guard file.processingFormat.sampleRate == 16000, file.processingFormat.channelCount == 1,
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: UInt32(file.length)) else {
            throw AudioIssue.conversion
        }
        try file.read(into: buffer)
        guard let pointer = buffer.floatChannelData?[0] else { throw AudioIssue.noFrames }
        return Array(UnsafeBufferPointer(start: pointer, count: Int(buffer.frameLength)))
    }

    static func output(_ fields: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys]) else { return }
        print(String(decoding: data, as: UTF8.self))
        fflush(nil)
    }
}

import AVFoundation
import Foundation

enum LocalBenchmark {
    static func run(_ args: [String]) async {
        guard args.count > 2, let engine = StudyEngine(rawValue: args[0]), let resources = Bundle.main.resourceURL else {
            print("usage: --benchmark ENGINE LOCALE NAME.wav... (resource files)")
            exit(2)
        }
        let recognizer = StudyRecognizer()
        for filename in args.dropFirst(2) {
            do {
                let file = try loadFixture(resources.appending(path: filename))
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

    @MainActor
    static func validate() async {
        do {
            let folder = FileManager.default.temporaryDirectory.appending(path: "voice-study-smoke-\(UUID())")
            defer { try? FileManager.default.removeItem(at: folder) }
            let study = StudySession(folder: folder)
            await study.load()
            guard let url = Bundle.main.resourceURL?.appending(path: "en-clip.wav") else { throw AudioIssue.noFrames }
            try await study.exerciseSynthetic(try loadFixture(url))
            print("Study fixture passed: audio, Apple recognition, editable review, exactly one commit, draft preservation, Undo")
            exit(0)
        } catch {
            print("Study validation failed: \(error)")
            exit(1)
        }
    }

    private static func loadFixture(_ url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        guard file.processingFormat.sampleRate == 16000, file.processingFormat.channelCount == 1,
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: UInt32(file.length)) else {
            throw AudioIssue.conversion
        }
        try file.read(into: buffer)
        guard let pointer = buffer.floatChannelData?[0] else { throw AudioIssue.noFrames }
        return Array(UnsafeBufferPointer(start: pointer, count: Int(buffer.frameLength)))
    }

    private static func output(_ fields: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys]) else { return }
        print(String(decoding: data, as: UTF8.self))
        fflush(nil)
    }
}

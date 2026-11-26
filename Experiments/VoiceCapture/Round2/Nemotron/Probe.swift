import AVFoundation
import Darwin
import FluidAudio
import Foundation

func millis(_ start: ContinuousClock.Instant) -> Double {
    let duration = start.duration(to: .now).components
    return Double(duration.seconds) * 1000 + Double(duration.attoseconds) / 1e15
}

func emit(_ row: [String: Any]) throws {
    let data = try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])
    print(String(decoding: data, as: UTF8.self))
    fflush(nil)
}

let args = Array(CommandLine.arguments.dropFirst())
guard args.count >= 3, let resources = Bundle.main.resourceURL else {
    print("Usage: NemotronProbe batch|paced auto|LOCALE FILE.wav... (bundled)")
    exit(2)
}
do {
    let start = ContinuousClock.now
    let manager = StreamingNemotronMultilingualAsrManager()
    try await manager.loadModels(from: resources.appending(path: "model"))
    await manager.setLanguage(args[1] == "auto" ? nil : args[1])
    try emit(["event": "load", "engine": "nemotron", "load_ms": millis(start), "language_hint": args[1]])
    for filename in args.dropFirst(2) {
        await manager.reset()
        do {
            let audio = try AVAudioFile(forReading: resources.appending(path: filename))
            let started = ContinuousClock.now
            var first: Double? = nil
            while audio.framePosition < audio.length {
                guard let buffer = AVAudioPCMBuffer(pcmFormat: audio.processingFormat, frameCapacity: 1600) else { break }
                try audio.read(into: buffer)
                guard let values = buffer.floatChannelData?[0], buffer.frameLength > 0 else { break }
                if args[0] == "paced" {
                    let deadline = started.advanced(by: .seconds(Double(audio.framePosition) / 16000))
                    try await ContinuousClock().sleep(until: deadline)
                }
                let partial = try await manager.process(samples: Array(UnsafeBufferPointer(start: values,
                                                                                           count: Int(buffer.frameLength))))
                if first == nil && !partial.isEmpty { first = millis(started) }
            }
            let stop = ContinuousClock.now
            let final = try await manager.finish()
            var row: [String: Any] = ["engine": "nemotron", "fixture": filename, "transcript": final,
                                      "mode": args[0], "language_hint": args[1],
                                      "finish_ms": millis(stop), "total_processing_and_feed_ms": millis(started)]
            if let first { row["first_partial_ms"] = first }
            try emit(row)
        } catch {
            try emit(["engine": "nemotron", "fixture": filename, "error": String(describing: error)])
        }
    }
} catch {
    try? emit(["error": String(describing: error)])
    exit(1)
}

import AVFoundation
import Foundation

enum NativeMic {
    static func run(_ args: [String]) async {
        var status = AVCaptureDevice.authorizationStatus(for: .audio)
        if status == .notDetermined && args.contains("request") {
            _ = await AVCaptureDevice.requestAccess(for: .audio)
            status = AVCaptureDevice.authorizationStatus(for: .audio)
        }
        LocalBenchmark.output(["mic_permission": status.rawValue, "retains_audio": false])
        guard status == .authorized else { exit(3) }

        let mic = Microphone()
        do {
            for trial in 1...12 {
                let id = UUID()
                let begin = ContinuousClock.now
                let buffer = try await mic.start(id: id, retainsAudio: false) {}
                let startedAt = milliseconds(begin)
                for _ in 0..<200 where buffer.status().first == nil {
                    try await Task.sleep(for: .milliseconds(10))
                }
                let finish = ContinuousClock.now
                let atFinish = buffer.status()
                try await Task.sleep(for: .milliseconds(trial.isMultiple(of: 2) ? 120 : 0))
                await mic.stop(id: id)
                let stopped = buffer.status()
                LocalBenchmark.output([
                    "trial": trial, "rate": buffer.rate, "engine_ms": startedAt,
                    "first_buffer_ms": stopped.first.map { milliseconds(begin, to: $0) } ?? -1,
                    "samples_after_finish": stopped.count - atFinish.count,
                    "stop_ms": milliseconds(finish), "released": true
                ])
                try await Task.sleep(for: .milliseconds(130))
            }
            exit(0)
        } catch {
            LocalBenchmark.output(["error": "microphone unavailable"])
            exit(1)
        }
    }
}

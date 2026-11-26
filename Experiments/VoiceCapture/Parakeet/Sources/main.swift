import Darwin
import FluidAudio
import Foundation

enum ProbeFailure: Error { case usage }

func ms(since start: ContinuousClock.Instant) -> Double {
    let value = start.duration(to: .now).components
    return Double(value.seconds) * 1000 + Double(value.attoseconds) / 1e15
}

func output(_ fields: [String: Any]) throws {
    let data = try JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys])
    print(String(decoding: data, as: UTF8.self))
    fflush(nil)
}

let args = Array(CommandLine.arguments.dropFirst())
do {
    guard args.count >= 2 else { throw ProbeFailure.usage }
    let start = ContinuousClock.now
    let cache = URL(fileURLWithPath: args[1], isDirectory: true)
    if args[0] == "download" {
        let folder = try await AsrModels.download(to: cache, version: .v3)
        try output(["event": "asset_end", "engine": "parakeet-v3", "folder": folder.lastPathComponent,
                    "elapsed_ms": ms(since: start)])
    } else {
        guard args[0] == "batch", args.count > 2 else { throw ProbeFailure.usage }
        let models = try AsrModels.loadLocal(from: cache, version: .v3)
        let manager = AsrManager()
        try await manager.loadModels(models)
        try output(["event": "setup", "engine": "parakeet-v3", "prepare_ms": ms(since: start)])
        for path in args.dropFirst(2) {
            let file = URL(fileURLWithPath: path)
            let began = ContinuousClock.now
            do {
                var state = TdtDecoderState.make()
                let result = try await manager.transcribe(file, decoderState: &state)
                try output(["event": "result", "engine": "parakeet-v3", "fixture": file.lastPathComponent,
                            "mode": "batch", "transcript": result.text, "finish_ms": ms(since: began)])
            } catch {
                try output(["event": "case_error", "engine": "parakeet-v3", "fixture": file.lastPathComponent,
                            "error": String(describing: error), "finish_ms": ms(since: began)])
            }
        }
        await manager.cleanup()
    }
} catch {
    try? output(["event": "error", "engine": "parakeet-v3", "message": String(describing: error)])
    exit(1)
}

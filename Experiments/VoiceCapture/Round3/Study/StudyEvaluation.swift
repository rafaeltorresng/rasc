import AVFoundation
import Foundation

struct StudyEvaluation: Codable, Sendable {
    struct Comparison: Codable, Sendable {
        let recognized: String
        let kept: String
    }

    private let id: UUID
    private let engine: String
    private let locale: String
    private let completion: String
    private let outcome: String
    private let milliseconds: [String: Double]

    @MainActor init(capture: StudySession.Capture, metrics: [String: Double], outcome: String) {
        id = capture.id
        engine = capture.engine.rawValue
        locale = capture.engine == .apple ? capture.language : "auto"
        completion = capture.completion.rawValue
        self.outcome = outcome
        milliseconds = metrics
    }

    func write(in directory: URL, comparison: Comparison? = nil) async throws {
        try await Task.detached(priority: .utility) {
            let folder = directory.appending(path: "Evaluation", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
            let data = if let comparison { try encoder.encode(comparison) } else { try encoder.encode(self) }
            let suffix = comparison == nil ? outcome : "comparison"
            let name = "\(id.uuidString)-\(suffix).json"
            try data.write(to: folder.appending(path: name), options: .atomic)
        }.value
    }

    static func removeFiles(in directory: URL) async throws {
        try await Task.detached(priority: .utility) {
            for name in ["Evaluation", "Evaluation Clips"] {
                let target = directory.appending(path: name)
                if FileManager.default.fileExists(atPath: target.path) {
                    try FileManager.default.removeItem(at: target)
                }
            }
        }.value
    }

    static func writeAudio(_ audio: StudyAudio, id: UUID, directory: URL) async throws {
        try await Task.detached(priority: .utility) {
            let folder = directory.appending(path: "Evaluation Clips", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let samples = try audio.mono16k()
            guard let format = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1),
                  let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: UInt32(samples.count)),
                  let channel = buffer.floatChannelData?[0] else { throw AudioIssue.conversion }
            buffer.frameLength = UInt32(samples.count)
            samples.withUnsafeBufferPointer {
                if let base = $0.baseAddress { channel.update(from: base, count: $0.count) }
            }
            let target = folder.appending(path: id.uuidString + ".wav")
            let temporary = folder.appending(path: UUID().uuidString + ".wav")
            defer { try? FileManager.default.removeItem(at: temporary) }
            do {
                let file = try AVAudioFile(forWriting: temporary, settings: format.settings)
                try file.write(from: buffer)
            }
            if FileManager.default.fileExists(atPath: target.path) {
                _ = try FileManager.default.replaceItemAt(target, withItemAt: temporary)
            } else {
                try FileManager.default.moveItem(at: temporary, to: target)
            }
        }.value
    }
}

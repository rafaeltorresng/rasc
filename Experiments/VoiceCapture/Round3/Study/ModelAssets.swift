import CoreML
import FluidAudio
import Foundation

enum ModelCompute: String, Sendable, CaseIterable {
    case neural, gpu, cpu, all, encoderCPU

    var units: MLComputeUnits {
        switch self {
        case .neural, .encoderCPU: .cpuAndNeuralEngine
        case .gpu: .cpuAndGPU
        case .cpu: .cpuOnly
        case .all: .all
        }
    }
}

enum PortableAssets {
    static let components = ["Preprocessor", "Encoder", "Decoder", "JointDecision"]
    static let defaultCompute: ModelCompute = .neural

    static func verifiedFolder(_ engine: StudyEngine) throws -> URL {
        guard let folder = Bundle.main.resourceURL?.appending(path: "Models/\(engine.folder)", directoryHint: .isDirectory),
              let state = try? Data(contentsOf: folder.appending(path: "provenance.json")),
              let installed = try? JSONDecoder().decode(Installation.self, from: state),
              installed.revision == engine.assetRevision,
              components.allSatisfy({
                  FileManager.default.fileExists(atPath: folder.appending(path: $0 + ".mlmodelc").path)
              }) else { throw RecognitionIssue.needsSetup }
        return folder
    }

    private struct Installation: Decodable { let revision: String }

    // Both research packs are monolithic Core ML exports from the same TDT family.
    // Match the pinned FluidAudio loadLocalOnly configuration: CPU for the preprocessor.
    // Timing exposes deployment work inside MLModel.load without taking a dependency fork.
    static func load(_ engine: StudyEngine, at folder: URL, compute: ModelCompute = defaultCompute) async throws
        -> (models: AsrModels, stages: [String: Double]) {
        let start = ContinuousClock.now
        let data = try Data(contentsOf: folder.appending(path: "parakeet_vocab.json"))
        let encoded = try JSONDecoder().decode([String: String].self, from: data)
        var vocabulary: [Int: String] = [:]
        for (key, value) in encoded {
            guard let token = Int(key) else { throw RecognitionIssue.needsSetup }
            vocabulary[token] = value
        }
        guard !vocabulary.isEmpty else { throw RecognitionIssue.needsSetup }
        var stages = ["vocabulary": milliseconds(start)]
        var models: [String: MLModel] = [:]
        let configuration = AsrModels.defaultConfiguration()
        configuration.computeUnits = compute.units
        for name in components {
            try Task.checkCancellation()
            let options = AsrModels.defaultConfiguration()
            let useCPU = name == "Preprocessor" || (name == "Encoder" && compute == .encoderCPU)
            options.computeUnits = useCPU ? .cpuOnly : compute.units
            let started = ContinuousClock.now
            models[name] = try await MLModel.load(contentsOf: folder.appending(path: name + ".mlmodelc"),
                                                  configuration: options)
            stages[name] = milliseconds(started)
        }
        try Task.checkCancellation()
        guard let encoder = models["Encoder"], let preprocessor = models["Preprocessor"],
              let decoder = models["Decoder"], let joint = models["JointDecision"] else { throw RecognitionIssue.needsSetup }
        return (AsrModels(encoder: encoder, preprocessor: preprocessor, decoder: decoder, joint: joint,
                          configuration: configuration, vocabulary: vocabulary, version: engine.fluidVersion), stages)
    }
}

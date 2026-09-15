import Foundation

#if DEBUG
import OSLog
#endif

#if canImport(FoundationModels)
import FoundationModels
#endif

struct FoundationModelsRefinementProvider: RefinementProvider {
    let metadata = RefinementMetadata(
        provider: "foundation-models",
        modelIdentifier: "system-language-model.default",
        promptVersion: RefinementPrompt.version
    )

    func availability(for _: RefinementRequest) async -> RefinementAvailability {
        let availability: RefinementAvailability
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            availability = Self.availability(of: SystemLanguageModel.default)
        } else {
            availability = .unavailable(.unsupportedEnvironment)
        }
        #else
        availability = .unavailable(.unsupportedEnvironment)
        #endif

        #if DEBUG
        Self.logger.debug("SystemLanguageModel availability: \(availability.diagnosticLabel, privacy: .public)")
        #endif
        return availability
    }

    func refine(_ request: RefinementRequest) async throws -> RefinementResult {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return try await refineWithSystemModel(request)
        }
        #endif
        throw RefinementError.unavailable(.unsupportedEnvironment)
    }

    #if DEBUG
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Rasc",
        category: "FoundationModels"
    )
    #endif
}

#if canImport(FoundationModels)
@available(macOS 26.0, *)
private extension FoundationModelsRefinementProvider {
    static func availability(of model: SystemLanguageModel) -> RefinementAvailability {
        switch model.availability {
        case .available:
            .available
        case let .unavailable(reason):
            switch reason {
            case .appleIntelligenceNotEnabled:
                .unavailable(.appleIntelligenceNotEnabled)
            case .deviceNotEligible:
                .unavailable(.deviceNotEligible)
            case .modelNotReady:
                .unavailable(.modelNotReady)
            @unknown default:
                .unavailable(.unknown)
            }
        }
    }

    func refineWithSystemModel(_ request: RefinementRequest) async throws -> RefinementResult {
        let model = SystemLanguageModel.default
        guard case .available = Self.availability(of: model) else {
            if case let .unavailable(reason) = Self.availability(of: model) {
                throw RefinementError.unavailable(reason)
            }
            throw RefinementError.unavailable(.unknown)
        }

        try Task.checkCancellation()

        // LanguageModelSession is intentionally scoped to this one operation.
        let session = LanguageModelSession(
            model: model,
            instructions: RefinementPrompt.instructions(for: request.scope)
        )

        do {
            let prompt = try RefinementPrompt.contentPrompt(for: request)
            let result: RefinementResult
            switch request.scope {
            case .wholeNote:
                let response = try await session.respond(
                    to: prompt,
                    generating: FoundationRefinementOutput.self
                )
                result = try response.content.refinementResult(inputText: request.inputText)
            case .selection:
                let response = try await session.respond(
                    to: prompt,
                    generating: SelectionRefinementOutput.self
                )
                result = try response.content.refinementResult(inputText: request.inputText)
            }
            try Task.checkCancellation()
            return result
        } catch is CancellationError {
            throw CancellationError()
        // Xcode 26.2's Foundation Models module exposes GenerationError as the
        // typed error for respond(to:generating:). Keep this SDK-compatible
        // catch until the installed SDK exposes the newer error model.
        } catch let error as LanguageModelSession.GenerationError {
            throw Self.refinementError(for: error)
        }
    }

    static func refinementError(
        for error: LanguageModelSession.GenerationError
    ) -> RefinementError {
        switch error {
        case .exceededContextWindowSize:
            .contextTooLarge
        case .assetsUnavailable:
            .unavailable(.modelNotReady)
        case .unsupportedLanguageOrLocale:
            .unsupportedLanguage
        case .unsupportedGuide, .decodingFailure:
            .invalidOutput
        case .guardrailViolation, .rateLimited, .concurrentRequests, .refusal:
            .providerFailure
        @unknown default:
            .providerFailure
        }
    }
}

@available(macOS 26.0, *)
@Generable(description: "A conservative refinement of one note or selected note region")
private struct FoundationRefinementOutput {
    @Guide(
        description: "Whether text changed meaningfully or should remain exactly unchanged",
        .anyOf(["changed", "noChange"])
    )
    var decision: String

    @Guide(
        description: "The closest internal note kind",
        .anyOf(["messyText", "tasks", "meeting", "idea", "message", "technical", "alreadyGood", "unknown"])
    )
    var kind: String

    @Guide(description: "The refined text, or the exact original text for noChange")
    var text: String

    func refinementResult(inputText: String) throws -> RefinementResult {
        guard let decision = RefinementDecision(rawValue: decision),
              let kind = RefinementKind(rawValue: kind)
        else {
            throw RefinementError.invalidOutput
        }

        switch decision {
        case .changed:
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw RefinementError.invalidOutput
            }
            return RefinementResult(decision: decision, kind: kind, text: text)
        case .noChange:
            return RefinementResult(decision: decision, kind: kind, text: inputText)
        }
    }
}

@available(macOS 26.0, *)
@Generable(description: "A conservative replacement for one selected note fragment")
private struct SelectionRefinementOutput {
    @Guide(
        description: "Whether the selected text changed or should remain unchanged",
        .anyOf(["changed", "noChange"])
    )
    var decision: String

    @Guide(
        description: "Only the replacement text for the selected fragment. For noChange, copy the selected text exactly."
    )
    var replacement: String

    func refinementResult(inputText: String) throws -> RefinementResult {
        guard let decision = RefinementDecision(rawValue: decision) else {
            throw RefinementError.invalidOutput
        }

        switch decision {
        case .changed:
            guard !replacement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw RefinementError.invalidOutput
            }
            return RefinementResult(decision: decision, kind: .unknown, text: replacement)
        case .noChange:
            return RefinementResult(decision: decision, kind: .alreadyGood, text: inputText)
        }
    }
}
#endif

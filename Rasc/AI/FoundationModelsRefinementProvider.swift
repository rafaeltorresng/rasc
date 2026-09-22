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

        let resolvedLanguage = RefineLanguageResolver.resolve(request: request)
        #if DEBUG
        let legacyResolvedLanguage = RefineLanguageResolverV1.resolve(request: request)
        #endif

        // LanguageModelSession is intentionally scoped to this one operation.
        let session = LanguageModelSession(
            model: model,
            instructions: RefinementPrompt.instructions(
                for: request.scope,
                resolvedLanguage: resolvedLanguage
            )
        )

        do {
            let prompt = try RefinementPrompt.contentPrompt(for: request)
            var result: RefinementResult
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

            let rawResult = result
            let validation = RefineLanguageValidator.validate(
                input: request.inputText,
                output: rawResult.text,
                resolved: resolvedLanguage
            )
            let validatorRejected = rawResult.decision == .changed && validation.violates

            if validatorRejected {
                result = RefinementResult(decision: .noChange, kind: .alreadyGood, text: request.inputText)
            }

            let unresolvedGuard = RefineUnresolvedLanguageGuard.evaluate(
                input: request.inputText,
                output: rawResult.text,
                rawDecision: rawResult.decision,
                resolved: resolvedLanguage
            )
            let unresolvedGuardRejected = !validatorRejected
                && rawResult.decision == .changed
                && unresolvedGuard.shouldReject

            if unresolvedGuardRejected {
                result = RefinementResult(decision: .noChange, kind: .alreadyGood, text: request.inputText)
            }

            let trace = RefinementLanguageTrace(
                resolvedLabel: resolvedLanguage.label.rawValue,
                resolvedLocale: resolvedLanguage.localeIdentifier,
                resolverConfidence: resolvedLanguage.confidence == .high ? "high" : "insufficient",
                resolverReason: resolvedLanguage.resolverReason,
                rawDecision: rawResult.decision,
                rawText: rawResult.text,
                validatorEvaluated: resolvedLanguage.enforcesPostValidation,
                validatorRejected: validatorRejected,
                decisionReason: Self.decisionReason(
                    raw: rawResult,
                    final: result,
                    validatorRejected: validatorRejected,
                    unresolvedGuardRejected: unresolvedGuardRejected,
                    resolved: resolvedLanguage
                ),
                legacyResolvedLabel: {
                    #if DEBUG
                    legacyResolvedLanguage.label.rawValue
                    #else
                    nil
                    #endif
                }(),
                legacyResolvedLocale: {
                    #if DEBUG
                    legacyResolvedLanguage.localeIdentifier
                    #else
                    nil
                    #endif
                }(),
                legacyResolverConfidence: {
                    #if DEBUG
                    legacyResolvedLanguage.confidence == .high ? "high" : "insufficient"
                    #else
                    nil
                    #endif
                }(),
                legacyResolverReason: {
                    #if DEBUG
                    legacyResolvedLanguage.resolverReason
                    #else
                    nil
                    #endif
                }(),
                legacyUsedSystemFallback: {
                    #if DEBUG
                    legacyResolvedLanguage.usedSystemFallback
                    #else
                    nil
                    #endif
                }(),
                markerAssessmentLabel: validation.markerAssessment?.rawValue,
                independentAssessmentLabel: validation.independentAssessment?.label.rawValue,
                independentAssessmentConfidence: validation.independentAssessment?.confidence.rawValue,
                validatorDecisionReason: validation.reason.rawValue,
                unresolvedGuardEvaluated: RefineUnresolvedLanguageGuard.isStrictUnresolvedEligible(resolvedLanguage),
                unresolvedGuardRejected: unresolvedGuardRejected,
                sourceEvidenceLabel: unresolvedGuard.sourceEvidence?.label.rawValue,
                sourceEvidenceStrong: unresolvedGuard.sourceEvidence?.isStrong,
                unresolvedGuardDecisionReason: unresolvedGuard.reason.rawValue,
                unresolvedGuardOutputAssessmentLabel: unresolvedGuard.outputAssessment?.label.rawValue,
                unresolvedGuardOutputAssessmentConfidence: unresolvedGuard.outputAssessment?.confidence.rawValue
            )

            try Task.checkCancellation()
            return RefinementResult(
                decision: result.decision,
                kind: result.kind,
                text: result.text,
                languageTrace: trace
            )
        } catch is CancellationError {
            throw CancellationError()
        // Xcode 26.2's Foundation Models module exposes GenerationError as the
        // typed error for respond(to:generating:). Keep this SDK-compatible
        // catch until the installed SDK exposes the newer error model.
        } catch let error as LanguageModelSession.GenerationError {
            throw Self.refinementError(for: error)
        }
    }

    static func decisionReason(
        raw: RefinementResult,
        final: RefinementResult,
        validatorRejected: Bool,
        unresolvedGuardRejected: Bool,
        resolved: ResolvedRefineLanguage
    ) -> String {
        if validatorRejected {
            return "language_contract_violation_rejected_to_noChange"
        }
        if unresolvedGuardRejected {
            return "unresolved_language_guard_rejected_to_noChange"
        }
        if raw.decision == .noChange {
            return "model_returned_noChange"
        }
        if !resolved.enforcesPostValidation {
            return "changed_validation_skipped_insufficient_resolver_confidence"
        }
        return "changed_passed_language_validation"
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

import Foundation

/// Eval-oriented trace of language resolution and validation. Fixture data only.
struct RefinementLanguageTrace: Equatable, Sendable, Codable {
    let resolvedLabel: String
    let resolvedLocale: String
    let resolverConfidence: String
    let resolverReason: String
    let rawDecision: RefinementDecision
    let rawText: String
    let validatorEvaluated: Bool
    let validatorRejected: Bool
    let decisionReason: String
    let legacyResolvedLabel: String?
    let legacyResolvedLocale: String?
    let legacyResolverConfidence: String?
    let legacyResolverReason: String?
    let legacyUsedSystemFallback: Bool?
    let markerAssessmentLabel: String?
    let independentAssessmentLabel: String?
    let independentAssessmentConfidence: String?
    let validatorDecisionReason: String?
    let unresolvedGuardEvaluated: Bool?
    let unresolvedGuardRejected: Bool?
    let sourceEvidenceLabel: String?
    let sourceEvidenceStrong: Bool?
    let unresolvedGuardDecisionReason: String?
    let unresolvedGuardOutputAssessmentLabel: String?
    let unresolvedGuardOutputAssessmentConfidence: String?

    init(
        resolvedLabel: String,
        resolvedLocale: String,
        resolverConfidence: String,
        resolverReason: String,
        rawDecision: RefinementDecision,
        rawText: String,
        validatorEvaluated: Bool,
        validatorRejected: Bool,
        decisionReason: String,
        legacyResolvedLabel: String? = nil,
        legacyResolvedLocale: String? = nil,
        legacyResolverConfidence: String? = nil,
        legacyResolverReason: String? = nil,
        legacyUsedSystemFallback: Bool? = nil,
        markerAssessmentLabel: String? = nil,
        independentAssessmentLabel: String? = nil,
        independentAssessmentConfidence: String? = nil,
        validatorDecisionReason: String? = nil,
        unresolvedGuardEvaluated: Bool? = nil,
        unresolvedGuardRejected: Bool? = nil,
        sourceEvidenceLabel: String? = nil,
        sourceEvidenceStrong: Bool? = nil,
        unresolvedGuardDecisionReason: String? = nil,
        unresolvedGuardOutputAssessmentLabel: String? = nil,
        unresolvedGuardOutputAssessmentConfidence: String? = nil
    ) {
        self.resolvedLabel = resolvedLabel
        self.resolvedLocale = resolvedLocale
        self.resolverConfidence = resolverConfidence
        self.resolverReason = resolverReason
        self.rawDecision = rawDecision
        self.rawText = rawText
        self.validatorEvaluated = validatorEvaluated
        self.validatorRejected = validatorRejected
        self.decisionReason = decisionReason
        self.legacyResolvedLabel = legacyResolvedLabel
        self.legacyResolvedLocale = legacyResolvedLocale
        self.legacyResolverConfidence = legacyResolverConfidence
        self.legacyResolverReason = legacyResolverReason
        self.legacyUsedSystemFallback = legacyUsedSystemFallback
        self.markerAssessmentLabel = markerAssessmentLabel
        self.independentAssessmentLabel = independentAssessmentLabel
        self.independentAssessmentConfidence = independentAssessmentConfidence
        self.validatorDecisionReason = validatorDecisionReason
        self.unresolvedGuardEvaluated = unresolvedGuardEvaluated
        self.unresolvedGuardRejected = unresolvedGuardRejected
        self.sourceEvidenceLabel = sourceEvidenceLabel
        self.sourceEvidenceStrong = sourceEvidenceStrong
        self.unresolvedGuardDecisionReason = unresolvedGuardDecisionReason
        self.unresolvedGuardOutputAssessmentLabel = unresolvedGuardOutputAssessmentLabel
        self.unresolvedGuardOutputAssessmentConfidence = unresolvedGuardOutputAssessmentConfidence
    }
}

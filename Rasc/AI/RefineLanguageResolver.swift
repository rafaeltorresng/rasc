import Foundation
import NaturalLanguage

enum RefineLanguageResolutionConfidence: Equatable, Sendable {
    /// Clear single-language signal; post-generation validation is enforced.
    case high
    /// Insufficient note-language evidence; validation is not enforced.
    case insufficient
}

struct ResolvedRefineLanguage: Equatable, Sendable {
    let label: RefineLanguageLabel
    let localeIdentifier: String
    let confidence: RefineLanguageResolutionConfidence
    let usedSystemFallback: Bool
    let resolverReason: String

    var enforcesPostValidation: Bool {
        confidence == .high && label != .mixed && label != .ambiguous && label != .unknown
    }

    /// True when the user selected a fixed output locale (authorized translation target).
    var isFixedTarget: Bool {
        resolverReason == "fixed_locale_policy"
    }
}

enum RefineLanguageResolver {
    static func resolve(request: RefinementRequest) -> ResolvedRefineLanguage {
        resolve(
            policy: request.languagePolicy,
            inputText: request.inputText,
            surroundingText: surroundingText(for: request)
        )
    }

    static func resolve(
        policy: RefineLanguagePolicy,
        inputText: String,
        surroundingText: String?
    ) -> ResolvedRefineLanguage {
        switch policy {
        case let .fixed(locale):
            let label = label(for: locale) ?? .english
            return ResolvedRefineLanguage(
                label: label,
                localeIdentifier: locale.identifier,
                confidence: .high,
                usedSystemFallback: false,
                resolverReason: "fixed_locale_policy"
            )
        case .matchNote:
            return resolveMatchNote(inputText: inputText, surroundingText: surroundingText)
        }
    }

    private static func resolveMatchNote(
        inputText: String,
        surroundingText: String?
    ) -> ResolvedRefineLanguage {
        let combined = [surroundingText, inputText]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        let detectionText = combined.isEmpty ? inputText : combined
        let tokenCount = detectionText
            .split(whereSeparator: \.isWhitespace)
            .filter { !$0.isEmpty }
            .count

        if isTechnicalOnlyAmbiguous(detectionText, tokenCount: tokenCount) {
            return unresolved(reason: "ambiguous_short_or_technical_only")
        }

        if let markerResolution = resolveFromMarkers(detectionText) {
            return markerResolution
        }

        if detectionText.count >= 20,
           let naturalLanguageResolution = resolveFromNaturalLanguage(detectionText) {
            return naturalLanguageResolution
        }

        return unresolved(reason: "unresolved_insufficient_evidence")
    }

    private static func resolveFromMarkers(_ text: String) -> ResolvedRefineLanguage? {
        let scores = RefineLanguageDetection.markerScores(in: text, boundaryAware: true)
        let sorted = scores.sorted { $0.score > $1.score }
        guard let top = sorted.first else { return nil }

        if top.score == 0 {
            return nil
        }

        let secondScore = sorted.dropFirst().first?.score ?? 0
        if top.score >= 2 && top.score - secondScore >= 2 {
            return highConfidence(top.label, reason: "marker_clear_margin")
        }

        if top.score >= 1 && secondScore == 0 {
            return highConfidence(top.label, reason: "marker_single_language")
        }

        if top.score >= 2 && secondScore >= 2 && top.score - secondScore <= 1 {
            return highConfidence(.mixed, reason: "marker_true_tie")
        }

        return nil
    }

    private static func resolveFromNaturalLanguage(_ text: String) -> ResolvedRefineLanguage? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let hypotheses = recognizer.languageHypotheses(withMaximum: 3) as [NLLanguage: Double]?,
              let dominant = recognizer.dominantLanguage,
              let topScore = hypotheses[dominant]
        else { return nil }

        let sorted = hypotheses.sorted { $0.value > $1.value }
        let secondScore = sorted.dropFirst().first?.value ?? 0
        guard topScore >= 0.55, topScore - secondScore >= 0.20,
              let label = label(for: dominant)
        else { return nil }

        return ResolvedRefineLanguage(
            label: label,
            localeIdentifier: RefineLanguageDetection.localeIdentifier(for: label),
            confidence: .high,
            usedSystemFallback: false,
            resolverReason: "natural_language_tie_break"
        )
    }

    private static func isTechnicalOnlyAmbiguous(_ text: String, tokenCount: Int) -> Bool {
        let romanceScore = RefineLanguageDetection.markerScores(in: text, boundaryAware: true)
            .filter { $0.label != .english }
            .map(\.score)
            .max() ?? 0
        if romanceScore > 0 { return false }

        let technicalTokens: Set<String> = [
            "retry", "deploy", "api", "queue", "bug", "draft", "fix", "sync", "staging", "rollback",
            "endpoint", "auth", "callback", "worker", "logs", "pr", "hotfix", "backend", "frontend",
        ]
        let tokens = text.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard !tokens.isEmpty else { return true }

        let allTechnical = tokens.allSatisfy { token in
            technicalTokens.contains(token.trimmingCharacters(in: .punctuationCharacters))
        }
        return tokenCount <= 3 || allTechnical
    }

    private static func highConfidence(
        _ label: RefineLanguageLabel,
        reason: String
    ) -> ResolvedRefineLanguage {
        ResolvedRefineLanguage(
            label: label,
            localeIdentifier: RefineLanguageDetection.localeIdentifier(for: label),
            confidence: .high,
            usedSystemFallback: false,
            resolverReason: reason
        )
    }

    private static func unresolved(reason: String) -> ResolvedRefineLanguage {
        ResolvedRefineLanguage(
            label: .ambiguous,
            localeIdentifier: RefineLanguageDetection.localeIdentifier(for: .ambiguous),
            confidence: .insufficient,
            usedSystemFallback: false,
            resolverReason: reason
        )
    }

    private static func surroundingText(for request: RefinementRequest) -> String? {
        guard let context = request.selectionContext else { return nil }
        return [context.before, context.after]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func label(for locale: Locale) -> RefineLanguageLabel? {
        let identifier = locale.identifier.lowercased()
        if identifier.hasPrefix("pt") { return .portuguese }
        if identifier.hasPrefix("es") { return .spanish }
        if identifier.hasPrefix("en") { return .english }
        return nil
    }

    private static func label(for language: NLLanguage) -> RefineLanguageLabel? {
        switch language.rawValue.prefix(2) {
        case "pt": .portuguese
        case "en": .english
        case "es": .spanish
        default: nil
        }
    }
}

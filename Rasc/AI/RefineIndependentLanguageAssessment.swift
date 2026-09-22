import Foundation
import NaturalLanguage

enum RefineIndependentLanguageAssessmentConfidence: String, Codable, Sendable, Equatable {
    case high
    case medium
    case low
    case insufficient
    case requiresReview
}

struct RefineIndependentLanguageAssessment: Equatable, Sendable {
    var label: RefineLanguageLabel
    var confidence: RefineIndependentLanguageAssessmentConfidence
    var markerLabel: RefineLanguageLabel
    var disagreesWithMarkers: Bool
}

enum RefineIndependentLanguageAssessor {
    static let minimumNaturalLanguageCharacterCount = 12

    static func assess(text: String) -> RefineIndependentLanguageAssessment {
        let markerLabel = RefineLanguageDetection.detect(in: text, ignoreTechnicalEnglishBoost: true)

        if let naturalLanguage = assessWithNaturalLanguage(text) {
            return RefineIndependentLanguageAssessment(
                label: naturalLanguage.label,
                confidence: naturalLanguage.confidence,
                markerLabel: markerLabel,
                disagreesWithMarkers: markerLabel != naturalLanguage.label
                    && markerLabel != .mixed
                    && naturalLanguage.label != .mixed
            )
        }

        if text.count < minimumNaturalLanguageCharacterCount {
            return RefineIndependentLanguageAssessment(
                label: markerLabel,
                confidence: .requiresReview,
                markerLabel: markerLabel,
                disagreesWithMarkers: false
            )
        }

        return RefineIndependentLanguageAssessment(
            label: markerLabel,
            confidence: markerLabel == .ambiguous ? .low : .medium,
            markerLabel: markerLabel,
            disagreesWithMarkers: false
        )
    }

    private static func assessWithNaturalLanguage(
        _ text: String
    ) -> (label: RefineLanguageLabel, confidence: RefineIndependentLanguageAssessmentConfidence)? {
        guard text.count >= minimumNaturalLanguageCharacterCount else { return nil }

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let dominant = recognizer.dominantLanguage else { return nil }

        let hypotheses = recognizer.languageHypotheses(withMaximum: 3)
        let mapped = mapNaturalLanguage(dominant)
        let topScore = hypotheses[dominant] ?? 0
        let confidence: RefineIndependentLanguageAssessmentConfidence = if topScore >= 0.75 {
            .high
        } else if topScore >= 0.45 {
            .medium
        } else {
            .low
        }

        return (mapped, confidence)
    }

    private static func mapNaturalLanguage(_ language: NLLanguage) -> RefineLanguageLabel {
        switch language {
        case .portuguese: .portuguese
        case .english: .english
        case .spanish: .spanish
        default: .unknown
        }
    }
}

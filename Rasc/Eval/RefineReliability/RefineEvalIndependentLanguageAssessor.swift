import Foundation
import NaturalLanguage

enum RefineEvalLanguageAssessmentConfidence: String, Codable, Sendable {
    case high
    case medium
    case low
    case insufficient
    case requiresReview
}

enum RefineEvalLanguageAssessmentMethod: String, Codable, Sendable {
    case authoritativeExpected
    case naturalLanguage
    case markerHeuristic
    case unresolved
}

struct RefineEvalIndependentLanguageAssessment: Codable, Equatable, Sendable {
    var label: String
    var confidence: RefineEvalLanguageAssessmentConfidence
    var method: RefineEvalLanguageAssessmentMethod
    var hypotheses: [String: Double]?
    var markerLabel: String?
    var disagreesWithMarkers: Bool
}

enum RefineEvalIndependentLanguageAssessor {
    static let minimumNaturalLanguageCharacterCount = 12

    static func assess(
        text: String,
        authoritativeExpectedTag: String?
    ) -> RefineEvalIndependentLanguageAssessment {
        let markerLabel = RefineEvalLanguageAnalyzer.detectLanguage(in: text).rawValue
        let nl = assessWithNaturalLanguage(text)

        if let authoritativeExpectedTag, !authoritativeExpectedTag.isEmpty, authoritativeExpectedTag != "mixed" {
            if text.count < minimumNaturalLanguageCharacterCount {
                return RefineEvalIndependentLanguageAssessment(
                    label: authoritativeExpectedTag,
                    confidence: .requiresReview,
                    method: .authoritativeExpected,
                    hypotheses: nil,
                    markerLabel: markerLabel,
                    disagreesWithMarkers: markerDisagrees(markerLabel, with: authoritativeExpectedTag)
                )
            }
        }

        if let nl {
            let disagrees = markerDisagrees(markerLabel, with: nl.label)
            return RefineEvalIndependentLanguageAssessment(
                label: nl.label,
                confidence: nl.confidence,
                method: .naturalLanguage,
                hypotheses: nl.hypotheses,
                markerLabel: markerLabel,
                disagreesWithMarkers: disagrees
            )
        }

        if text.count < minimumNaturalLanguageCharacterCount {
            return RefineEvalIndependentLanguageAssessment(
                label: authoritativeExpectedTag ?? markerLabel,
                confidence: .requiresReview,
                method: authoritativeExpectedTag == nil ? .markerHeuristic : .authoritativeExpected,
                hypotheses: nil,
                markerLabel: markerLabel,
                disagreesWithMarkers: false
            )
        }

        return RefineEvalIndependentLanguageAssessment(
            label: markerLabel,
            confidence: markerLabel == RefineLanguageLabel.ambiguous.rawValue ? .low : .medium,
            method: .markerHeuristic,
            hypotheses: nil,
            markerLabel: markerLabel,
            disagreesWithMarkers: false
        )
    }

    static func isUnauthorizedDrift(
        input: String,
        output: String,
        expectedTag: String?
    ) -> (drift: Bool, assessment: RefineEvalIndependentLanguageAssessment, generationDrift: Bool) {
        guard let expectedTag, expectedTag != "mixed" else {
            let assessment = assess(text: output, authoritativeExpectedTag: expectedTag)
            return (false, assessment, false)
        }

        let outputAssessment = assess(text: output, authoritativeExpectedTag: expectedTag)
        let inputAssessment = assess(text: input, authoritativeExpectedTag: expectedTag)

        if outputAssessment.confidence == .requiresReview || outputAssessment.confidence == .insufficient {
            return (false, outputAssessment, false)
        }

        let generationDrift = unauthorizedTranslation(
            input: input,
            output: output,
            expectedTag: expectedTag,
            inputAssessment: inputAssessment,
            outputAssessment: outputAssessment
        )

        let drift = generationDrift && outputAssessment.label != expectedTag
        return (drift, outputAssessment, generationDrift)
    }

    private static func unauthorizedTranslation(
        input: String,
        output: String,
        expectedTag: String,
        inputAssessment: RefineEvalIndependentLanguageAssessment,
        outputAssessment: RefineEvalIndependentLanguageAssessment
    ) -> Bool {
        if outputAssessment.label == expectedTag {
            return false
        }
        if outputAssessment.label == RefineLanguageLabel.mixed.rawValue {
            return false
        }
        if inputAssessment.label == expectedTag && outputAssessment.label != expectedTag {
            return true
        }
        if expectedTag == "pt" || expectedTag == "es" {
            return outputAssessment.label == "en" || outputAssessment.label == "english"
        }
        if expectedTag == "en" {
            return outputAssessment.label == "pt"
                || outputAssessment.label == "portuguese"
                || outputAssessment.label == "es"
                || outputAssessment.label == "spanish"
        }
        return false
    }

    private static func assessWithNaturalLanguage(
        _ text: String
    ) -> (label: String, confidence: RefineEvalLanguageAssessmentConfidence, hypotheses: [String: Double])? {
        guard text.count >= minimumNaturalLanguageCharacterCount else { return nil }

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let dominant = recognizer.dominantLanguage else { return nil }

        let hypotheses = recognizer.languageHypotheses(withMaximum: 3)
        let mapped = mapNaturalLanguage(dominant)
        let topScore = hypotheses[dominant] ?? 0
        let confidence: RefineEvalLanguageAssessmentConfidence = if topScore >= 0.75 {
            .high
        } else if topScore >= 0.45 {
            .medium
        } else {
            .low
        }

        let hypothesisMap = hypotheses.reduce(into: [String: Double]()) { partial, entry in
            partial[entry.key.rawValue] = entry.value
        }

        return (mapped, confidence, hypothesisMap)
    }

    private static func mapNaturalLanguage(_ language: NLLanguage) -> String {
        switch language {
        case .portuguese: "pt"
        case .english: "en"
        case .spanish: "es"
        default: language.rawValue
        }
    }

    private static func markerDisagrees(_ markerLabel: String, with other: String) -> Bool {
        normalize(markerLabel) != normalize(other)
    }

    private static func normalize(_ tag: String) -> String {
        switch tag.lowercased() {
        case "portuguese", "pt": "pt"
        case "english", "en": "en"
        case "spanish", "es": "es"
        case "mixed": "mixed"
        default: tag.lowercased()
        }
    }
}

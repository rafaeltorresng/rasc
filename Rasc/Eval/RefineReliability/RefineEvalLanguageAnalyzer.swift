import Foundation

enum RefineEvalLanguageAnalyzer {
    static func detectLanguage(in text: String) -> RefineLanguageLabel {
        RefineLanguageDetection.detect(in: text)
    }

    static func label(for tag: String?) -> RefineLanguageLabel {
        RefineLanguageDetection.label(for: tag)
    }

    static func isDrift(input: String, output: String, expected: RefineEvalExpectation) -> Bool {
        guard let expectedTag = expected.expectedLanguage else { return false }
        if expectedTag == "mixed" {
            return false
        }

        let independent = RefineEvalIndependentLanguageAssessor.isUnauthorizedDrift(
            input: input,
            output: output,
            expectedTag: expectedTag
        )
        return independent.drift
    }
}

import Foundation

enum RefineLanguageLabel: String, Codable, Sendable {
    case portuguese
    case english
    case spanish
    case mixed
    case ambiguous
    case unknown
}

enum RefineLanguageDetection {
    static let portugueseMarkers = [
        "ação", "amanhã", "acho", "depois", "falar", "não", "obrigado", "reunião", "talvez", "ver",
        "você", "pra", "tá", "também", "porque", "então", "hoje", "sexta", "relatório", "enviar",
        "revisar", "com", "sobre", "né", "msg", "cadê", "demora", "ideia", "mandar",
    ]
    static let englishMarkers = [
        "the", "and", "maybe", "tomorrow", "check", "deploy", "should", "would", "meeting", "thanks",
        "please", "review", "before", "after", "might", "could", "about", "team", "launch",
    ]
    static let spanishMarkers = [
        "el", "la", "los", "las", "quizás", "quizá", "mañana", "hola", "gracias", "reunión",
        "tal vez", "equipo", "después", "hoy", "viernes", "debería", "informe", "vuelo", "quedó",
    ]

    /// Legacy substring-based detection used only by resolver v1 shadow comparisons.
    static func detect(in text: String, ignoreTechnicalEnglishBoost: Bool = false) -> RefineLanguageLabel {
        let lowered = text.lowercased()
        let pt = score(text, markers: portugueseMarkers, boundaryAware: false)
        let en = score(text, markers: englishMarkers, boundaryAware: false)
        let es = score(text, markers: spanishMarkers, boundaryAware: false)

        let technicalEnglish = !ignoreTechnicalEnglishBoost
            && (lowered.contains("_") || lowered.contains("retry") || lowered.contains("queue"))
        let adjustedEN = en + (technicalEnglish ? 1 : 0)

        let scores: [(RefineLanguageLabel, Int)] = [
            (.portuguese, pt),
            (.english, adjustedEN),
            (.spanish, es),
        ]
        let sorted = scores.sorted { $0.1 > $1.1 }
        let top = sorted[0]
        let second = sorted[1]

        if text.count <= 3 {
            return .ambiguous
        }

        if top.1 == 0 && second.1 == 0 {
            if technicalEnglish { return .english }
            return .ambiguous
        }

        if top.1 > 0 && second.1 > 0 && abs(top.1 - second.1) <= 1 {
            return .mixed
        }

        return top.0
    }

    static func markerScores(in text: String, boundaryAware: Bool = true) -> [(label: RefineLanguageLabel, score: Int)] {
        [
            (.portuguese, score(text, markers: portugueseMarkers, boundaryAware: boundaryAware)),
            (.english, score(text, markers: englishMarkers, boundaryAware: boundaryAware)),
            (.spanish, score(text, markers: spanishMarkers, boundaryAware: boundaryAware)),
        ]
    }

    static func containsMarker(_ marker: String, in text: String, boundaryAware: Bool) -> Bool {
        let lowered = text.lowercased()
        guard boundaryAware else {
            return lowered.contains(marker)
        }

        let escaped = NSRegularExpression.escapedPattern(for: marker)
        let pattern = "(?<![\\p{L}])\(escaped)(?![\\p{L}])"
        return lowered.range(of: pattern, options: .regularExpression) != nil
    }

    static func score(_ text: String, markers: [String], boundaryAware: Bool) -> Int {
        markers.reduce(0) { partial, marker in
            partial + (containsMarker(marker, in: text, boundaryAware: boundaryAware) ? 1 : 0)
        }
    }

    static func label(for tag: String?) -> RefineLanguageLabel {
        switch tag?.lowercased() {
        case "pt": .portuguese
        case "en": .english
        case "es": .spanish
        case "mixed": .mixed
        default: .unknown
        }
    }

    static func localeIdentifier(for label: RefineLanguageLabel) -> String {
        switch label {
        case .portuguese: "pt-BR"
        case .english: "en-US"
        case .spanish: "es-ES"
        case .mixed: "mixed"
        case .ambiguous, .unknown: "und"
        }
    }
}

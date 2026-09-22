import Foundation

struct RefineLanguageSourceEvidence: Equatable, Sendable {
    var label: RefineLanguageLabel
    var isStrong: Bool
}

enum RefineLanguageSourceEvidenceAssessor {
    private static let portugueseMarkers = RefineLanguageDetection.portugueseMarkers + [
        "versão", "preciso", "fechar", "subir", "filas", "fila", "ajustar", "café", "otimo", "ótimo",
        "instruções", "ignorar", "rollback", "checar", "validar", "pingar", "export", "hj",
    ]
    private static let englishMarkers = RefineLanguageDetection.englishMarkers + [
        "later", "expand", "project", "plan", "milestones", "sales", "units", "target", "version", "build",
    ]
    private static let spanishMarkers = RefineLanguageDetection.spanishMarkers + [
        "instrucciones", "instrucciones",
    ]

    private static let englishInfinitiveFalsePositives: Set<String> = [
        "after", "answer", "buffer", "character", "cluster", "error", "filter", "footer", "header",
        "master", "monitor", "number", "offer", "order", "over", "parameter", "partner", "render",
        "super", "timer", "tracker", "transfer", "under", "user", "review",
    ]

    static func assess(in text: String) -> RefineLanguageSourceEvidence {
        let portugueseScore = markerScore(text, markers: portugueseMarkers) + portugueseMorphologyScore(text)
        let englishScore = markerScore(text, markers: englishMarkers)
        let spanishScore = markerScore(text, markers: spanishMarkers)

        let ordered = [
            (RefineLanguageLabel.portuguese, portugueseScore),
            (RefineLanguageLabel.english, englishScore),
            (RefineLanguageLabel.spanish, spanishScore),
        ].sorted { $0.1 > $1.1 }

        let top = ordered[0]
        let second = ordered[1]

        if top.1 == 0 {
            return RefineLanguageSourceEvidence(label: .ambiguous, isStrong: false)
        }

        if second.1 > 0 && abs(top.1 - second.1) <= 1 {
            return RefineLanguageSourceEvidence(label: .mixed, isStrong: false)
        }

        return RefineLanguageSourceEvidence(label: top.0, isStrong: top.1 >= 2)
    }

    private static func markerScore(_ text: String, markers: [String]) -> Int {
        let lowered = text.lowercased()
        let padded = " \(lowered) "
        var score = 0
        for marker in markers {
            if marker.contains(" ") {
                if lowered.contains(marker) {
                    score += 1
                }
            } else if padded.contains(" \(marker) ")
                || padded.hasPrefix(" \(marker) ")
                || padded.hasSuffix(" \(marker) ")
            {
                score += 1
            }
        }
        return score
    }

    private static func portugueseMorphologyScore(_ text: String) -> Int {
        var score = 0
        if text.unicodeScalars.contains(where: isPortugueseDiacritic) {
            score += 2
        }

        for token in text.lowercased().split(whereSeparator: \.isWhitespace) {
            let cleaned = token.trimmingCharacters(in: .punctuationCharacters)
            guard cleaned.count >= 4 else { continue }
            if cleaned.hasSuffix("ar") || cleaned.hasSuffix("er") || cleaned.hasSuffix("ir"),
               !englishInfinitiveFalsePositives.contains(cleaned)
            {
                score += 2
            }
        }

        let padded = " \(text.lowercased()) "
        if score >= 2, padded.contains(" no ") || padded.contains(" na ") {
            score += 1
        }

        return score
    }

    private static func isPortugueseDiacritic(_ scalar: UnicodeScalar) -> Bool {
        switch scalar.value {
        case 0x00E0...0x00E3, 0x00E7, 0x00E8...0x00EA, 0x00EC, 0x00ED, 0x00F2...0x00F5, 0x00FA, 0x00FC:
            true
        default:
            false
        }
    }
}

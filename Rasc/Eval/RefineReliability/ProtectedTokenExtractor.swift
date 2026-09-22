import Foundation

enum ProtectedTokenCategory: String, Codable, Sendable, CaseIterable {
    case url
    case email
    case handle
    case money
    case date
    case time
    case number
    case percentage
    case identifier
    case codeLike
    case quotedLiteral
    case opaqueID
}

enum ProtectedTokenPreservationPolicy: String, Codable, Sendable {
    case exact
    case semantic
}

enum ProtectedTokenPreservationStatus: String, Codable, Sendable {
    case preserved
    case safelyNormalized
    case notPreserved
}

struct ProtectedToken: Hashable, Sendable {
    let value: String
    let category: ProtectedTokenCategory
    let normalized: String
}

enum ProtectedTokenExtractor {
    private struct LocatedToken {
        let token: ProtectedToken
        let range: NSRange
    }

    static func extract(from text: String) -> [ProtectedToken] {
        var located: [LocatedToken] = []

        // Precedence is intentional: compound literals own their full ranges before
        // less-specific classes (handles and numbers) are considered.
        appendNonOverlapping(urlMatches(in: text), to: &located)
        appendNonOverlapping(matches(in: text, pattern: #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#, options: [.caseInsensitive], category: .email), to: &located)
        appendNonOverlapping(quotedLiteralMatches(in: text), to: &located)
        appendNonOverlapping(matches(in: text, pattern: #"(?<![A-Za-z0-9])(?:R\$|US\$|\$|€|£|¥)(?:\s*[+-]?\d[\d.,]*)?"#, category: .money), to: &located)
        appendNonOverlapping(dateMatches(in: text), to: &located)
        appendNonOverlapping(timeMatches(in: text), to: &located)
        appendNonOverlapping(matches(in: text, pattern: #"(?<![A-Za-z0-9_])\d+(?:[.,]\d+)?\s?%"#, category: .percentage), to: &located)
        appendNonOverlapping(opaqueIDMatches(in: text), to: &located)
        appendNonOverlapping(matches(in: text, pattern: #"@[A-Za-z0-9_]{1,32}"#, category: .handle), to: &located)
        appendNonOverlapping(codeLikeMatches(in: text), to: &located)
        appendNonOverlapping(identifierMatches(in: text), to: &located)
        appendNonOverlapping(matches(in: text, pattern: #"(?<![A-Za-z0-9_])(?:\d+(?:[.,]\d+)?)(?![A-Za-z0-9_])"#, category: .number), to: &located)

        var seen = Set<String>()
        return located.sorted { $0.range.location < $1.range.location }.compactMap { value in
            let key = "\(value.token.category.rawValue):\(value.token.value)"
            guard seen.insert(key).inserted else { return nil }
            return value.token
        }
    }

    static func preservationPolicy(for category: ProtectedTokenCategory) -> ProtectedTokenPreservationPolicy {
        switch category {
        case .money, .date, .time, .number, .percentage:
            return .semantic
        case .url, .email, .handle, .identifier, .codeLike, .quotedLiteral, .opaqueID:
            return .exact
        }
    }

    static func preservationStatus(of token: ProtectedToken, in output: String) -> ProtectedTokenPreservationStatus {
        if output.contains(token.value) {
            return .preserved
        }
        guard preservationPolicy(for: token.category) == .semantic,
              let inputCanonical = semanticCanonicalValue(for: token),
              extract(from: output).contains(where: {
                  $0.category == token.category && semanticCanonicalValue(for: $0) == inputCanonical
              }) else {
            return .notPreserved
        }
        return .safelyNormalized
    }

    static func missingTokens(input: String, output: String, required: [String]) -> [String] {
        let extracted = Set(extract(from: input).map(\.normalized))
        let outputNormalized = normalize(output)
        var missing: [String] = []
        for token in required {
            let norm = normalize(token)
            if !outputNormalized.contains(norm) && !extracted.contains(where: { outputNormalized.contains($0) }) {
                if !outputNormalized.contains(norm) {
                    missing.append(token)
                }
            }
        }
        return missing
    }

    static func mutatedInputTokens(input: String, output: String) -> [ProtectedToken] {
        extract(from: input).filter { preservationStatus(of: $0, in: output) == .notPreserved }
    }

    static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).lowercased()
    }

    private static func appendNonOverlapping(_ candidates: [LocatedToken], to result: inout [LocatedToken]) {
        for candidate in candidates where !result.contains(where: { NSIntersectionRange($0.range, candidate.range).length > 0 }) {
            result.append(candidate)
        }
    }

    private static func quotedLiteralMatches(in text: String) -> [LocatedToken] {
        var tokens: [LocatedToken] = []
        tokens.append(contentsOf: matches(in: text, pattern: #"\"[^\"\n]{2,}\""#, category: .quotedLiteral))
        tokens.append(contentsOf: matches(in: text, pattern: #"'[^'\n]{2,}'"#, category: .quotedLiteral))
        tokens.append(contentsOf: matches(in: text, pattern: #"`[^`\n]+`"#, category: .quotedLiteral))
        return tokens
    }

    private static func urlMatches(in text: String) -> [LocatedToken] {
        matches(in: text, pattern: #"https?://[^\s\)\]\"']+"#, category: .url).compactMap { located in
            let value = located.token.value.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:"))
            guard !value.isEmpty else { return nil }
            let removedUTF16Count = located.token.value.utf16.count - value.utf16.count
            return LocatedToken(
                token: ProtectedToken(value: value, category: .url, normalized: normalize(value)),
                range: NSRange(location: located.range.location, length: located.range.length - removedUTF16Count)
            )
        }
    }

    private static func dateMatches(in text: String) -> [LocatedToken] {
        var tokens: [LocatedToken] = []
        tokens.append(contentsOf: matches(in: text, pattern: #"\b\d{4}-\d{2}-\d{2}\b"#, category: .date))
        tokens.append(contentsOf: matches(in: text, pattern: #"\b\d{1,2}/\d{1,2}(?:/\d{2,4})?\b"#, category: .date))
        return tokens
    }

    private static func timeMatches(in text: String) -> [LocatedToken] {
        var tokens: [LocatedToken] = []
        tokens.append(contentsOf: matches(in: text, pattern: #"(?<![A-Za-z0-9])(?:1[0-2]|0?[1-9])(?::[0-5]\d)?\s?(?:AM|PM)(?![A-Za-z0-9])"#, options: [.caseInsensitive], category: .time))
        tokens.append(contentsOf: matches(in: text, pattern: #"(?<![A-Za-z0-9])(?:[01]?\d|2[0-3]):[0-5]\d(?![A-Za-z0-9])"#, category: .time))
        tokens.append(contentsOf: matches(in: text, pattern: #"(?<![A-Za-z0-9])(?:[01]?\d|2[0-3])h(?:[0-5]\d)?(?![A-Za-z0-9])"#, options: [.caseInsensitive], category: .time))
        return tokens
    }

    private static func opaqueIDMatches(in text: String) -> [LocatedToken] {
        var tokens = matches(in: text, pattern: #"\b[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}\b"#, options: [.caseInsensitive], category: .opaqueID)
        tokens.append(contentsOf: matches(in: text, pattern: #"\b[A-Z]{2,}-\d+\b"#, category: .opaqueID))
        tokens.append(contentsOf: matches(in: text, pattern: #"\b[0-9a-fA-F]{7,64}\b"#, category: .opaqueID).filter {
            $0.token.value.contains(where: \.isNumber)
                && $0.token.value.lowercased().contains(where: { ("a"..."f").contains(String($0)) })
        })
        return tokens
    }

    private static func codeLikeMatches(in text: String) -> [LocatedToken] {
        var tokens: [LocatedToken] = []
        tokens.append(contentsOf: matches(in: text, pattern: #"\b[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)+\(\)"#, category: .codeLike))
        tokens.append(contentsOf: matches(in: text, pattern: #"\b[A-Za-z_][A-Za-z0-9_]*\(\)"#, category: .codeLike))
        tokens.append(contentsOf: matches(in: text, pattern: #"(?:^|(?<=\s))(?:\.?\.?/)?(?:[A-Za-z0-9_.-]+/)+[A-Za-z0-9_.-]+"#, category: .codeLike))
        return tokens
    }

    private static func identifierMatches(in text: String) -> [LocatedToken] {
        var tokens: [LocatedToken] = []
        tokens.append(contentsOf: matches(in: text, pattern: #"\b[A-Za-z][A-Za-z0-9]*_[A-Za-z0-9_]+\b"#, category: .identifier))
        tokens.append(contentsOf: matches(in: text, pattern: #"\b[a-z]+[A-Z][A-Za-z0-9]*\b"#, category: .identifier))
        tokens.append(contentsOf: matches(in: text, pattern: #"\b(?:[A-Z]{2,}[A-Z0-9]*[a-z][A-Za-z0-9]*|[A-Z][a-z]+[A-Z][A-Za-z0-9]*)\b"#, category: .identifier))
        tokens.append(contentsOf: matches(in: text, pattern: #"\b(?:[A-Za-z0-9]+-){2,}[A-Za-z0-9]+\b|\b[A-Za-z]+-[A-Za-z0-9]*\d[A-Za-z0-9-]*\b"#, category: .identifier))
        tokens.append(contentsOf: matches(in: text, pattern: #"\bv\d+(?:\.\d+)+\b"#, options: [.caseInsensitive], category: .identifier))
        tokens.append(contentsOf: matches(in: text, pattern: #"\b(?=[A-Za-z0-9]*[A-Za-z])(?=[A-Za-z0-9]*\d)[A-Za-z0-9]{3,}\b"#, category: .identifier))
        tokens.append(contentsOf: matches(in: text, pattern: #"#[0-9]+"#, category: .identifier))
        return tokens
    }

    private static func semanticCanonicalValue(for token: ProtectedToken) -> String? {
        switch token.category {
        case .money, .percentage:
            return token.value.replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
        case .time:
            return canonicalMinutes(token.value).map(String.init)
        case .date, .number:
            return token.value.trimmingCharacters(in: .whitespacesAndNewlines)
        case .url, .email, .handle, .identifier, .codeLike, .quotedLiteral, .opaqueID:
            return nil
        }
    }

    private static func canonicalMinutes(_ value: String) -> Int? {
        let compact = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if compact.hasSuffix("am") || compact.hasSuffix("pm") {
            let isPM = compact.hasSuffix("pm")
            let clock = compact.dropLast(2).trimmingCharacters(in: .whitespaces)
            let pieces = clock.split(separator: ":", omittingEmptySubsequences: false)
            guard let rawHour = Int(pieces[0]), (1...12).contains(rawHour) else { return nil }
            let minute = pieces.count == 2 ? Int(pieces[1]) : 0
            guard let minute, (0...59).contains(minute) else { return nil }
            let hour = (rawHour % 12) + (isPM ? 12 : 0)
            return hour * 60 + minute
        }

        let separator: Character = compact.contains(":") ? ":" : "h"
        let pieces = compact.split(separator: separator, omittingEmptySubsequences: false)
        guard let hour = Int(pieces[0]), (0...23).contains(hour) else { return nil }
        let minute = pieces.count == 2 && !pieces[1].isEmpty ? Int(pieces[1]) : 0
        guard let minute, (0...59).contains(minute) else { return nil }
        return hour * 60 + minute
    }

    private static func matches(in text: String, pattern: String, options: NSRegularExpression.Options = [], category: ProtectedTokenCategory) -> [LocatedToken] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, options: [], range: range).compactMap { match in
            guard let matchRange = Range(match.range, in: text) else { return nil }
            let value = String(text[matchRange])
            return LocatedToken(token: ProtectedToken(value: value, category: category, normalized: normalize(value)), range: match.range)
        }
    }
}

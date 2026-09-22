import Foundation

enum RefineProtectedLiteralClass: String, Codable, Equatable, Sendable, CaseIterable {
    case url
    case email
    case handle
    case identifier
    case codeLike
    case quotedLiteral
    case opaqueID
    case integer
    case money
    case percentage
    case time
}

enum RefineProtectedLiteralViolationReason: String, Codable, Equatable, Sendable {
    case dropped = "protectedLiteralDropped"
    case mutated = "protectedLiteralMutated"
    case currencyDropped
    case currencyChanged
    case valueChanged
    case literalDropped
    case multiplicityChanged
    case ambiguousTransformation
    case ampmChanged
    case crossFamilyRewrite
}

struct RefineProtectedLiteral: Equatable, Sendable {
    let value: String
    let literalClass: RefineProtectedLiteralClass
}

struct RefineProtectedLiteralViolation: Equatable, Sendable {
    let reason: RefineProtectedLiteralViolationReason
    let literalClass: RefineProtectedLiteralClass
}

enum RefineProtectedLiteralValidationOutcome: Equatable, Sendable {
    case valid
    case invalid(RefineProtectedLiteralViolation)

    var violation: RefineProtectedLiteralViolation? {
        guard case let .invalid(violation) = self else { return nil }
        return violation
    }
}

struct RefinementProtectedLiteralTrace: Codable, Equatable, Sendable {
    let validatorEvaluated: Bool
    let validatorRejected: Bool
    let violationReason: RefineProtectedLiteralViolationReason?
    let literalClass: RefineProtectedLiteralClass?
}

enum RefineProtectedLiteralValidator {
    private struct LocatedLiteral {
        let literal: RefineProtectedLiteral?
        let range: NSRange
    }

    static func extract(from text: String) -> [RefineProtectedLiteral] {
        var located: [LocatedLiteral] = []

        appendNonOverlapping(urlMatches(in: text), to: &located)
        appendNonOverlapping(matches(in: text, pattern: #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#, options: [.caseInsensitive], literalClass: .email), to: &located)
        appendNonOverlapping(quotedLiteralMatches(in: text), to: &located)

        // These exact-policy exclusions claim their spans so integers and technical
        // identifier patterns cannot accidentally promote semantic-equivalence work.
        appendNonOverlapping(excludedSemanticMatches(in: text), to: &located)

        appendNonOverlapping(opaqueIDMatches(in: text), to: &located)
        appendNonOverlapping(matches(in: text, pattern: #"@[A-Za-z0-9_]{1,32}"#, literalClass: .handle), to: &located)
        appendNonOverlapping(codeLikeMatches(in: text), to: &located)
        appendNonOverlapping(identifierMatches(in: text), to: &located)
        appendNonOverlapping(matches(in: text, pattern: #"(?<![A-Za-z0-9_.,])[-+]?\d+(?![A-Za-z0-9_.,])"#, literalClass: .integer), to: &located)

        var seen = Set<String>()
        return located
            .sorted { $0.range.location < $1.range.location }
            .compactMap(\.literal)
            .filter { seen.insert("\($0.literalClass.rawValue):\($0.value)").inserted }
    }

    static func validate(source: String, proposal: String) -> RefineProtectedLiteralValidationOutcome {
        let required = extract(from: source)
        guard !required.isEmpty else { return .valid }
        let proposed = extract(from: proposal)

        for literal in required {
            if proposed.contains(where: {
                $0.literalClass == literal.literalClass && $0.value == literal.value
            }) {
                continue
            }
            let reason: RefineProtectedLiteralViolationReason = proposed.contains {
                $0.literalClass == literal.literalClass
            } ? .mutated : .dropped
            return .invalid(RefineProtectedLiteralViolation(
                reason: reason,
                literalClass: literal.literalClass
            ))
        }
        return .valid
    }

    static func finalize(_ result: RefinementResult, for request: RefinementRequest) -> RefinementResult {
        guard result.decision == .changed, result.protectedLiteralTrace == nil else { return result }

        switch validate(source: request.inputText, proposal: result.text) {
        case .valid:
            return RefinementResult(
                decision: result.decision,
                kind: result.kind,
                text: result.text,
                languageTrace: result.languageTrace,
                protectedLiteralTrace: RefinementProtectedLiteralTrace(
                    validatorEvaluated: true,
                    validatorRejected: false,
                    violationReason: nil,
                    literalClass: nil
                )
            )
        case let .invalid(violation):
            return RefinementResult(
                decision: .noChange,
                kind: .alreadyGood,
                text: request.inputText,
                languageTrace: result.languageTrace,
                protectedLiteralTrace: RefinementProtectedLiteralTrace(
                    validatorEvaluated: true,
                    validatorRejected: true,
                    violationReason: violation.reason,
                    literalClass: violation.literalClass
                )
            )
        }
    }

    private static func appendNonOverlapping(_ candidates: [LocatedLiteral], to result: inout [LocatedLiteral]) {
        for candidate in candidates where !result.contains(where: {
            NSIntersectionRange($0.range, candidate.range).length > 0
        }) {
            result.append(candidate)
        }
    }

    private static func urlMatches(in text: String) -> [LocatedLiteral] {
        matches(in: text, pattern: #"https?://[^\s\)\]\"']+"#, literalClass: .url).compactMap { located in
            guard let literal = located.literal else { return nil }
            let value = literal.value.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:"))
            guard !value.isEmpty else { return nil }
            let removedUTF16Count = literal.value.utf16.count - value.utf16.count
            return LocatedLiteral(
                literal: RefineProtectedLiteral(value: value, literalClass: .url),
                range: NSRange(location: located.range.location, length: located.range.length - removedUTF16Count)
            )
        }
    }

    private static func quotedLiteralMatches(in text: String) -> [LocatedLiteral] {
        matches(in: text, pattern: #"\"[^\"\n]{2,}\""#, literalClass: .quotedLiteral)
            + matches(in: text, pattern: #"'[^'\n]{2,}'"#, literalClass: .quotedLiteral)
            + matches(in: text, pattern: #"`[^`\n]+`"#, literalClass: .quotedLiteral)
    }

    private static func excludedSemanticMatches(in text: String) -> [LocatedLiteral] {
        let patterns = [
            #"(?<![A-Za-z0-9])(?:R\$|US\$|BRL|USD|EUR|GBP|\$|€|£|¥)(?:\s*[+-]?\d[\d.,]*)?"#,
            #"\b\d{4}-\d{2}-\d{2}\b"#,
            #"\b\d{1,2}/\d{1,2}(?:/\d{2,4})?\b"#,
            #"(?<![A-Za-z0-9])(?:1[0-2]|0?[1-9])(?::[0-5]\d)?\s?(?:AM|PM)(?![A-Za-z0-9])"#,
            #"(?<![A-Za-z0-9])(?:[01]?\d|2[0-3]):[0-5]\d(?![A-Za-z0-9])"#,
            #"(?<![A-Za-z0-9])(?:[01]?\d|2[0-3])h(?:[0-5]\d)?(?![A-Za-z0-9])"#,
            #"(?<![A-Za-z0-9_])\d+(?:[.,]\d+)?\s?%"#,
            #"(?<![A-Za-z0-9_])\d+[.,]\d+(?:[.,]\d+)*(?![A-Za-z0-9_])"#,
        ]
        return patterns.flatMap { excludedMatches(in: text, pattern: $0) }
    }

    private static func opaqueIDMatches(in text: String) -> [LocatedLiteral] {
        var values = matches(in: text, pattern: #"\b[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}\b"#, options: [.caseInsensitive], literalClass: .opaqueID)
        values += matches(in: text, pattern: #"\b[A-Z]{2,}-\d+\b"#, literalClass: .opaqueID)
        values += matches(in: text, pattern: #"\b[0-9a-fA-F]{7,64}\b"#, literalClass: .opaqueID).filter {
            guard let value = $0.literal?.value.lowercased() else { return false }
            return value.contains(where: \.isNumber)
                && value.contains(where: { ("a"..."f").contains(String($0)) })
        }
        return values
    }

    private static func codeLikeMatches(in text: String) -> [LocatedLiteral] {
        matches(in: text, pattern: #"\b[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)+\(\)"#, literalClass: .codeLike)
            + matches(in: text, pattern: #"\b[A-Za-z_][A-Za-z0-9_]*\(\)"#, literalClass: .codeLike)
            + matches(in: text, pattern: #"(?:^|(?<=\s))(?:/|\./|\.\./)(?:[A-Za-z0-9_.-]+/)*[A-Za-z0-9_.-]+\b"#, literalClass: .codeLike)
            + matches(in: text, pattern: #"\b(?=[A-Za-z0-9_./-]*/)(?=[A-Za-z0-9_./-]*(?:[._-]|\d))[A-Za-z0-9_.-]+(?:/[A-Za-z0-9_.-]+)+\b"#, literalClass: .codeLike)
    }

    private static func identifierMatches(in text: String) -> [LocatedLiteral] {
        matches(in: text, pattern: #"\b[A-Za-z][A-Za-z0-9]*_[A-Za-z0-9_]+\b"#, literalClass: .identifier)
            + matches(in: text, pattern: #"\b[a-z]+[A-Z][A-Za-z0-9]*\b"#, literalClass: .identifier)
            + matches(in: text, pattern: #"\b(?:[A-Z]{2,}[A-Z0-9]*[a-z][A-Za-z0-9]*|[A-Z][a-z]+[A-Z][A-Za-z0-9]*)\b"#, literalClass: .identifier)
            + matches(in: text, pattern: #"\b(?:[A-Za-z0-9]+-){2,}[A-Za-z0-9]+\b|\b[A-Za-z]+-[A-Za-z0-9]*\d[A-Za-z0-9-]*\b"#, literalClass: .identifier)
            + matches(in: text, pattern: #"\bv\d+(?:\.\d+)+\b"#, options: [.caseInsensitive], literalClass: .identifier)
            + matches(in: text, pattern: #"\b(?=[A-Za-z0-9]*[A-Za-z])(?=[A-Za-z0-9]*\d)[A-Za-z0-9]{3,}\b"#, literalClass: .identifier)
            + matches(in: text, pattern: #"#[0-9]+"#, literalClass: .identifier)
    }

    private static func excludedMatches(in text: String, pattern: String) -> [LocatedLiteral] {
        rawMatches(in: text, pattern: pattern, options: [.caseInsensitive]).map {
            LocatedLiteral(literal: nil, range: $0.range)
        }
    }

    private static func matches(
        in text: String,
        pattern: String,
        options: NSRegularExpression.Options = [],
        literalClass: RefineProtectedLiteralClass
    ) -> [LocatedLiteral] {
        rawMatches(in: text, pattern: pattern, options: options).compactMap { match in
            guard let range = Range(match.range, in: text) else { return nil }
            return LocatedLiteral(
                literal: RefineProtectedLiteral(value: String(text[range]), literalClass: literalClass),
                range: match.range
            )
        }
    }

    private static func rawMatches(
        in text: String,
        pattern: String,
        options: NSRegularExpression.Options = []
    ) -> [NSTextCheckingResult] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return [] }
        return regex.matches(
            in: text,
            range: NSRange(text.startIndex..<text.endIndex, in: text)
        )
    }
}

enum RefineMoneyCurrencyIdentity: String, Equatable, Sendable {
    case brl
    case usd
    case ambiguousDollar
    case eur
    case gbp
}

enum RefineMoneyAmountParseOutcome: Equatable, Sendable {
    case parsed(Decimal)
    case ambiguous
    case invalid
}

struct RefineMoneyLiteral: Equatable, Sendable {
    let rawValue: String
    let currency: RefineMoneyCurrencyIdentity
    let amountText: String?
    let amount: RefineMoneyAmountParseOutcome
}

/// A conservative semantic validator for explicitly marked money literals.
/// It intentionally does not parse dates, times, percentages, or bare numbers.
enum RefineMoneyLiteralValidator {
    private static let moneyPattern = #"(?<![\p{L}\p{N}_])(R\$|US\$|BRL|USD|EUR|GBP|\$|€|£)(?:\s*([+-]?\d+(?:[.,]\d+)*))?(?![\p{L}\p{N}_])"#
    private static let bareNumberPattern = #"(?<![\p{L}\p{N}_])[-+]?\d+(?:[.,]\d+)*(?![\p{L}\p{N}_%])"#

    static func extract(from text: String) -> [RefineMoneyLiteral] {
        guard let regex = try? NSRegularExpression(
            pattern: moneyPattern,
            options: [.caseInsensitive]
        ) else { return [] }

        return regex.matches(
            in: text,
            range: NSRange(text.startIndex..<text.endIndex, in: text)
        ).compactMap { match in
            guard let rawRange = Range(match.range(at: 0), in: text),
                  let markerRange = Range(match.range(at: 1), in: text),
                  let currency = currencyIdentity(for: String(text[markerRange]))
            else { return nil }

            let amountText: String? = {
                guard match.range(at: 2).location != NSNotFound,
                      let range = Range(match.range(at: 2), in: text)
                else { return nil }
                return String(text[range])
            }()
            return RefineMoneyLiteral(
                rawValue: String(text[rawRange]),
                currency: currency,
                amountText: amountText,
                amount: parseAmount(amountText)
            )
        }
    }

    static func validate(source: String, proposal: String) -> RefineProtectedLiteralValidationOutcome {
        let required = extract(from: source)
        guard !required.isEmpty else { return .valid }
        let proposed = extract(from: proposal)

        guard required.count == proposed.count else {
            if proposed.isEmpty {
                let reason: RefineProtectedLiteralViolationReason = proposalContainsSourceAmount(
                    proposal,
                    required: required
                ) ? .currencyDropped : .literalDropped
                return invalid(reason)
            }
            return invalid(.multiplicityChanged)
        }

        var used = Array(repeating: false, count: proposed.count)
        for sourceLiteral in required {
            if let exactIndex = proposed.indices.first(where: {
                !used[$0] && proposed[$0].rawValue == sourceLiteral.rawValue
            }) {
                used[exactIndex] = true
                continue
            }

            guard case let .parsed(sourceAmount) = sourceLiteral.amount else {
                return invalid(.ambiguousTransformation)
            }

            if let semanticIndex = proposed.indices.first(where: { index in
                guard !used[index], proposed[index].currency == sourceLiteral.currency,
                      case let .parsed(candidateAmount) = proposed[index].amount
                else { return false }
                return candidateAmount == sourceAmount
            }) {
                used[semanticIndex] = true
                continue
            }

            let remaining = proposed.indices.filter { !used[$0] }
            if remaining.contains(where: { index in
                guard case let .parsed(candidateAmount) = proposed[index].amount else { return false }
                return candidateAmount == sourceAmount && proposed[index].currency != sourceLiteral.currency
            }) {
                return invalid(.currencyChanged)
            }
            if remaining.contains(where: { index in
                guard proposed[index].currency == sourceLiteral.currency,
                      case let .parsed(candidateAmount) = proposed[index].amount
                else { return false }
                return candidateAmount != sourceAmount
            }) {
                return invalid(.valueChanged)
            }
            if remaining.contains(where: {
                if case .parsed = proposed[$0].amount { return false }
                return true
            }) {
                return invalid(.ambiguousTransformation)
            }
            return invalid(.currencyChanged)
        }

        return used.allSatisfy { $0 } ? .valid : invalid(.multiplicityChanged)
    }

    static func finalize(_ result: RefinementResult, for request: RefinementRequest) -> RefinementResult {
        guard result.decision == .changed else { return result }
        switch validate(source: request.inputText, proposal: result.text) {
        case .valid:
            return result
        case let .invalid(violation):
            return RefinementResult(
                decision: .noChange,
                kind: .alreadyGood,
                text: request.inputText,
                languageTrace: result.languageTrace,
                protectedLiteralTrace: RefinementProtectedLiteralTrace(
                    validatorEvaluated: true,
                    validatorRejected: true,
                    violationReason: violation.reason,
                    literalClass: .money
                )
            )
        }
    }

    static func parseAmount(_ text: String?) -> RefineMoneyAmountParseOutcome {
        guard var text, !text.isEmpty else { return .invalid }
        let isNegative = text.hasPrefix("-")
        if text.hasPrefix("+") || text.hasPrefix("-") {
            text.removeFirst()
        }
        guard !text.isEmpty,
              text.unicodeScalars.allSatisfy({ CharacterSet.decimalDigits.contains($0) || $0 == "," || $0 == "." })
        else { return .invalid }

        let commaCount = text.filter { $0 == "," }.count
        let periodCount = text.filter { $0 == "." }.count
        let normalized: String

        if commaCount > 0, periodCount > 0 {
            guard let lastComma = text.lastIndex(of: ","),
                  let lastPeriod = text.lastIndex(of: ".")
            else { return .invalid }
            let decimalSeparator: Character = lastComma > lastPeriod ? "," : "."
            let groupingSeparator: Character = decimalSeparator == "," ? "." : ","
            let pieces = text.split(separator: decimalSeparator, omittingEmptySubsequences: false)
            guard pieces.count == 2,
                  (1...2).contains(pieces[1].count),
                  validGroupedInteger(String(pieces[0]), separator: groupingSeparator)
            else { return .invalid }
            normalized = String(pieces[0]).replacingOccurrences(of: String(groupingSeparator), with: "")
                + "." + pieces[1]
        } else if commaCount > 0 || periodCount > 0 {
            let separator: Character = commaCount > 0 ? "," : "."
            let pieces = text.split(separator: separator, omittingEmptySubsequences: false)
            if pieces.count == 2, (1...2).contains(pieces[1].count) {
                normalized = String(pieces[0]) + "." + String(pieces[1])
            } else if pieces.count == 2, pieces[1].count == 3 {
                return .ambiguous
            } else if pieces.count > 2,
                      (1...3).contains(pieces[0].count),
                      pieces.dropFirst().allSatisfy({ $0.count == 3 }) {
                normalized = pieces.joined()
            } else {
                return .invalid
            }
        } else {
            normalized = text
        }

        let signed = isNegative ? "-" + normalized : normalized
        guard let value = Decimal(string: signed, locale: Locale(identifier: "en_US_POSIX")) else {
            return .invalid
        }
        return .parsed(value)
    }

    private static func currencyIdentity(for marker: String) -> RefineMoneyCurrencyIdentity? {
        switch marker.uppercased() {
        case "R$", "BRL": .brl
        case "US$", "USD": .usd
        case "$": .ambiguousDollar
        case "€", "EUR": .eur
        case "£", "GBP": .gbp
        default: nil
        }
    }

    private static func validGroupedInteger(_ text: String, separator: Character) -> Bool {
        let pieces = text.split(separator: separator, omittingEmptySubsequences: false)
        if pieces.count == 1 {
            return !pieces[0].isEmpty && pieces[0].allSatisfy(\.isNumber)
        }
        return (1...3).contains(pieces[0].count)
            && pieces[0].allSatisfy(\.isNumber)
            && pieces.dropFirst().allSatisfy { $0.count == 3 && $0.allSatisfy(\.isNumber) }
    }

    private static func proposalContainsSourceAmount(
        _ proposal: String,
        required: [RefineMoneyLiteral]
    ) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: bareNumberPattern) else { return false }
        let candidateAmounts = regex.matches(
            in: proposal,
            range: NSRange(proposal.startIndex..<proposal.endIndex, in: proposal)
        ).compactMap { match -> Decimal? in
            guard let range = Range(match.range, in: proposal),
                  case let .parsed(value) = parseAmount(String(proposal[range]))
            else { return nil }
            return value
        }
        return required.contains { literal in
            guard case let .parsed(value) = literal.amount else { return false }
            return candidateAmounts.contains(value)
        }
    }

    private static func invalid(
        _ reason: RefineProtectedLiteralViolationReason
    ) -> RefineProtectedLiteralValidationOutcome {
        .invalid(RefineProtectedLiteralViolation(reason: reason, literalClass: .money))
    }
}

enum RefinePercentageValueParseOutcome: Equatable, Sendable {
    case parsed(Decimal)
    case ambiguous
    case invalid
}

struct RefinePercentageLiteral: Equatable, Sendable {
    let rawValue: String
    let numericText: String?
    let value: RefinePercentageValueParseOutcome
}

/// A conservative semantic validator for explicitly marked percentage literals.
/// It intentionally does not parse dates, times, money, or bare numbers.
enum RefinePercentageLiteralValidator {
    private static let percentagePattern =
        #"(?<![\p{L}\p{N}_])([+-]?\d+(?:[.,]\d+)?)\s*%(?![\p{L}\p{N}_])"#

    static func extract(from text: String) -> [RefinePercentageLiteral] {
        guard let regex = try? NSRegularExpression(pattern: percentagePattern) else { return [] }

        return regex.matches(
            in: text,
            range: NSRange(text.startIndex..<text.endIndex, in: text)
        ).compactMap { match in
            guard let rawRange = Range(match.range(at: 0), in: text) else { return nil }
            let numericText: String? = {
                guard match.range(at: 1).location != NSNotFound,
                      let range = Range(match.range(at: 1), in: text)
                else { return nil }
                return String(text[range])
            }()
            return RefinePercentageLiteral(
                rawValue: String(text[rawRange]),
                numericText: numericText,
                value: parseNumericText(numericText)
            )
        }
    }

    static func validate(source: String, proposal: String) -> RefineProtectedLiteralValidationOutcome {
        let required = extract(from: source)
        guard !required.isEmpty else { return .valid }
        let proposed = extract(from: proposal)

        guard required.count == proposed.count else {
            if proposed.isEmpty {
                return invalid(.literalDropped)
            }
            return invalid(.multiplicityChanged)
        }

        var used = Array(repeating: false, count: proposed.count)
        for sourceLiteral in required {
            if let exactIndex = proposed.indices.first(where: {
                !used[$0] && proposed[$0].rawValue == sourceLiteral.rawValue
            }) {
                used[exactIndex] = true
                continue
            }

            guard case let .parsed(sourceValue) = sourceLiteral.value else {
                return invalid(.ambiguousTransformation)
            }

            if let semanticIndex = proposed.indices.first(where: { index in
                guard !used[index], case let .parsed(candidateValue) = proposed[index].value
                else { return false }
                return candidateValue == sourceValue
            }) {
                used[semanticIndex] = true
                continue
            }

            let remaining = proposed.indices.filter { !used[$0] }
            if remaining.contains(where: { index in
                guard case let .parsed(candidateValue) = proposed[index].value else { return false }
                return candidateValue != sourceValue
            }) {
                return invalid(.valueChanged)
            }
            if remaining.contains(where: {
                if case .parsed = proposed[$0].value { return false }
                return true
            }) {
                return invalid(.ambiguousTransformation)
            }
            return invalid(.literalDropped)
        }

        return used.allSatisfy { $0 } ? .valid : invalid(.multiplicityChanged)
    }

    static func finalize(_ result: RefinementResult, for request: RefinementRequest) -> RefinementResult {
        guard result.decision == .changed else { return result }
        switch validate(source: request.inputText, proposal: result.text) {
        case .valid:
            return result
        case let .invalid(violation):
            return RefinementResult(
                decision: .noChange,
                kind: .alreadyGood,
                text: request.inputText,
                languageTrace: result.languageTrace,
                protectedLiteralTrace: RefinementProtectedLiteralTrace(
                    validatorEvaluated: true,
                    validatorRejected: true,
                    violationReason: violation.reason,
                    literalClass: .percentage
                )
            )
        }
    }

    static func parseNumericText(_ text: String?) -> RefinePercentageValueParseOutcome {
        RefineMoneyLiteralValidator.parseAmount(text).mapOutcome
    }

    private static func invalid(
        _ reason: RefineProtectedLiteralViolationReason
    ) -> RefineProtectedLiteralValidationOutcome {
        .invalid(RefineProtectedLiteralViolation(reason: reason, literalClass: .percentage))
    }
}

private extension RefineMoneyAmountParseOutcome {
    var mapOutcome: RefinePercentageValueParseOutcome {
        switch self {
        case let .parsed(value): .parsed(value)
        case .ambiguous: .ambiguous
        case .invalid: .invalid
        }
    }
}

enum RefineTimeRepresentationFamily: Equatable, Sendable {
    case hour24
    case hour12(isPM: Bool)
}

enum RefineTimeParseOutcome: Equatable, Sendable {
    case parsed(minutes: Int, family: RefineTimeRepresentationFamily)
    case ambiguous
    case invalid
}

struct RefineTimeLiteral: Equatable, Sendable {
    let rawValue: String
    let value: RefineTimeParseOutcome
}

/// A conservative semantic validator for explicit clock-time literals.
/// It intentionally does not parse dates, money, percentages, or bare numbers.
enum RefineTimeLiteralValidator {
    private static let timePattern =
        #"(?<![\p{L}\p{N}_])(?:1[0-2]|0?[1-9])(?::[0-5]\d)?\s*(?:AM|PM)(?![\p{L}\p{N}_])|(?<![\p{L}\p{N}_])(?:[01]?\d|2[0-3])h(?:[0-5]\d)?(?![\p{L}\p{N}_])|(?<![\p{L}\p{N}_])(?:[01]?\d|2[0-3]):[0-5]\d(?!\s*(?:AM|PM)(?![\p{L}\p{N}_]))(?![\p{L}\p{N}_])"#

    static func extract(from text: String) -> [RefineTimeLiteral] {
        guard let regex = try? NSRegularExpression(
            pattern: timePattern,
            options: [.caseInsensitive]
        ) else { return [] }

        return regex.matches(
            in: text,
            range: NSRange(text.startIndex..<text.endIndex, in: text)
        ).compactMap { match in
            guard let rawRange = Range(match.range(at: 0), in: text) else { return nil }
            let rawValue = String(text[rawRange])
            return RefineTimeLiteral(rawValue: rawValue, value: parse(rawValue))
        }
    }

    static func validate(source: String, proposal: String) -> RefineProtectedLiteralValidationOutcome {
        let required = extract(from: source)
        guard !required.isEmpty else { return .valid }
        let proposed = extract(from: proposal)

        guard required.count == proposed.count else {
            if proposed.isEmpty {
                return invalid(.literalDropped)
            }
            return invalid(.multiplicityChanged)
        }

        var used = Array(repeating: false, count: proposed.count)
        for sourceLiteral in required {
            if let exactIndex = proposed.indices.first(where: {
                !used[$0] && proposed[$0].rawValue == sourceLiteral.rawValue
            }) {
                used[exactIndex] = true
                continue
            }

            guard case let .parsed(sourceMinutes, sourceFamily) = sourceLiteral.value else {
                return invalid(.ambiguousTransformation)
            }

            if let semanticIndex = proposed.indices.first(where: { index in
                guard !used[index],
                      case let .parsed(candidateMinutes, candidateFamily) = proposed[index].value
                else { return false }
                return candidateMinutes == sourceMinutes && familiesEquivalent(sourceFamily, candidateFamily)
            }) {
                used[semanticIndex] = true
                continue
            }

            let remaining = proposed.indices.filter { !used[$0] }
            if remaining.contains(where: { index in
                guard case let .parsed(candidateMinutes, candidateFamily) = proposed[index].value else {
                    return false
                }
                return candidateMinutes == sourceMinutes && isCrossFamily(sourceFamily, candidateFamily)
            }) {
                return invalid(.crossFamilyRewrite)
            }
            if remaining.contains(where: { index in
                guard case let .parsed(candidateMinutes, candidateFamily) = proposed[index].value,
                      case let .hour12(sourcePM) = sourceFamily,
                      case let .hour12(candidatePM) = candidateFamily,
                      let sourceFace = hour12Face(minutes: sourceMinutes),
                      let candidateFace = hour12Face(minutes: candidateMinutes)
                else { return false }
                return sourceFace.hour == candidateFace.hour
                    && sourceFace.minute == candidateFace.minute
                    && sourcePM != candidatePM
            }) {
                return invalid(.ampmChanged)
            }
            if remaining.contains(where: { index in
                guard case let .parsed(_, candidateFamily) = proposed[index].value else { return false }
                return familiesEquivalent(sourceFamily, candidateFamily)
            }) {
                return invalid(.valueChanged)
            }
            if remaining.contains(where: {
                if case .parsed = proposed[$0].value { return false }
                return true
            }) {
                return invalid(.ambiguousTransformation)
            }
            return invalid(.literalDropped)
        }

        return used.allSatisfy { $0 } ? .valid : invalid(.multiplicityChanged)
    }

    static func finalize(_ result: RefinementResult, for request: RefinementRequest) -> RefinementResult {
        guard result.decision == .changed else { return result }
        switch validate(source: request.inputText, proposal: result.text) {
        case .valid:
            return result
        case let .invalid(violation):
            return RefinementResult(
                decision: .noChange,
                kind: .alreadyGood,
                text: request.inputText,
                languageTrace: result.languageTrace,
                protectedLiteralTrace: RefinementProtectedLiteralTrace(
                    validatorEvaluated: true,
                    validatorRejected: true,
                    violationReason: violation.reason,
                    literalClass: .time
                )
            )
        }
    }

    static func parse(_ raw: String) -> RefineTimeParseOutcome {
        let collapsed = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .uppercased()

        if let hour24H = parseHour24H(collapsed) {
            return hour24H
        }
        if let hour24Colon = parseHour24Colon(collapsed) {
            return hour24Colon
        }
        if let hour12 = parseHour12(raw.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return hour12
        }
        return .invalid
    }

    private static func parseHour24H(_ text: String) -> RefineTimeParseOutcome? {
        guard let regex = try? NSRegularExpression(pattern: #"^([01]?\d|2[0-3])H([0-5]\d)?$"#),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)),
              let hourRange = Range(match.range(at: 1), in: text)
        else { return nil }

        let hour = Int(text[hourRange]) ?? -1
        guard (0...23).contains(hour) else { return .invalid }
        let minute: Int = {
            guard match.range(at: 2).location != NSNotFound,
                  let minuteRange = Range(match.range(at: 2), in: text)
            else { return 0 }
            return Int(text[minuteRange]) ?? -1
        }()
        guard (0...59).contains(minute) else { return .invalid }
        return .parsed(minutes: hour * 60 + minute, family: .hour24)
    }

    private static func parseHour24Colon(_ text: String) -> RefineTimeParseOutcome? {
        guard let regex = try? NSRegularExpression(pattern: #"^([01]?\d|2[0-3]):([0-5]\d)$"#),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)),
              let hourRange = Range(match.range(at: 1), in: text),
              let minuteRange = Range(match.range(at: 2), in: text),
              let hour = Int(text[hourRange]),
              let minute = Int(text[minuteRange]),
              (0...23).contains(hour),
              (0...59).contains(minute)
        else { return nil }

        return .parsed(minutes: hour * 60 + minute, family: .hour24)
    }

    private static func parseHour12(_ text: String) -> RefineTimeParseOutcome? {
        let normalized = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .uppercased()
        guard let regex = try? NSRegularExpression(
            pattern: #"^(1[0-2]|0?[1-9])(?::([0-5]\d))?\s*(AM|PM)$"#,
            options: [.caseInsensitive]
        ),
              let match = regex.firstMatch(
                in: normalized,
                range: NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
              ),
              let hourRange = Range(match.range(at: 1), in: normalized),
              let meridiemRange = Range(match.range(at: 3), in: normalized),
              let hour = Int(normalized[hourRange]),
              (1...12).contains(hour)
        else { return nil }

        let minute: Int = {
            guard match.range(at: 2).location != NSNotFound,
                  let minuteRange = Range(match.range(at: 2), in: normalized),
                  let parsed = Int(normalized[minuteRange])
            else { return 0 }
            return parsed
        }()
        guard (0...59).contains(minute) else { return .invalid }

        let isPM = normalized[meridiemRange] == "PM"
        let clockHour = hour % 12 + (isPM ? 12 : 0)
        return .parsed(minutes: clockHour * 60 + minute, family: .hour12(isPM: isPM))
    }

    private static func familiesEquivalent(
        _ lhs: RefineTimeRepresentationFamily,
        _ rhs: RefineTimeRepresentationFamily
    ) -> Bool {
        switch (lhs, rhs) {
        case (.hour24, .hour24): true
        case let (.hour12(leftPM), .hour12(rightPM)): leftPM == rightPM
        default: false
        }
    }

    private static func isCrossFamily(
        _ lhs: RefineTimeRepresentationFamily,
        _ rhs: RefineTimeRepresentationFamily
    ) -> Bool {
        switch (lhs, rhs) {
        case (.hour24, .hour12), (.hour12, .hour24): true
        default: false
        }
    }

    private static func hour12Face(minutes: Int) -> (hour: Int, minute: Int)? {
        let clockHour = minutes / 60
        let minute = minutes % 60
        let faceHour: Int = switch clockHour {
        case 0: 12
        case 13...23: clockHour - 12
        default: clockHour
        }
        return (faceHour, minute)
    }

    private static func invalid(
        _ reason: RefineProtectedLiteralViolationReason
    ) -> RefineProtectedLiteralValidationOutcome {
        .invalid(RefineProtectedLiteralViolation(reason: reason, literalClass: .time))
    }
}

import Foundation

enum UncertaintyMatch: Equatable {
    case allowed
    case hedgeLoss
    case ambiguous
}

/// Finalize guard that blocks an explicit possibility being turned into a fact,
/// instruction or decision. Whole notes under `matchNote` only.
///
/// Scope is deliberately narrow: no language detection, no bare `or`/`ou` handling,
/// no list-truncation rule, no prompt/provider/guard changes elsewhere.
enum RefineUncertaintyLossGuard {
    static func finalize(_ result: RefinementResult, for request: RefinementRequest) -> RefinementResult {
        guard result.decision == .changed,
              request.scope == .wholeNote,
              request.languagePolicy == .matchNote,
              evaluate(claim: request.inputText, suggestion: result.text) != .allowed
        else { return result }

        return RefinementResult(
            decision: .noChange,
            kind: .alreadyGood,
            text: request.inputText,
            languageTrace: result.languageTrace,
            protectedLiteralTrace: result.protectedLiteralTrace
        )
    }

    // MARK: - Rule

    /// Explicit possibility markers. A hedge reworded within the same clause
    /// (e.g. `maybe` -> `perhaps`, `talvez` -> `quem sabe`) still qualifies the claim.
    private static let hedges = [
        "maybe", "perhaps", "possibly", "might", "could", "i think", "it seems",
        "i guess", "not sure", "seems",
        "talvez", "acho que", "pode ser", "é possível", "possivelmente", "quem sabe",
        "não sei se", "será que", "acredito que", "suponho que", "hipótese",
    ]

    /// Function words excluded from claim-content matching.
    private static let stopwords: Set<String> = [
        "o", "a", "os", "as", "de", "do", "da", "dos", "das", "que", "e", "em", "no",
        "na", "um", "uma", "uns", "umas", "para", "por", "com", "se", "ao", "aos", "ma",
        "the", "of", "to", "in", "on", "for", "and", "or", "is", "be", "it", "this",
        "that", "we", "you", "i", "my", "our", "should",
    ]

    /// Split on list/discourse punctuation only. `or`/`ou` is a boundary here,
    /// never counted as an uncertainty marker.
    private static let clauseSeparators = try! NSRegularExpression(
        pattern: #"[,;—–.]|\s+ou\s+|\s+or\s+"#,
        options: [.caseInsensitive]
    )

    static func blocks(claim: String, suggestion: String) -> Bool {
        evaluate(claim: claim, suggestion: suggestion) != .allowed
    }

    /// Content-based claim matching. Hedges stay bound to the claim whose content
    /// they qualify; clause order and punctuation alone never decide the outcome.
    static func evaluate(claim: String, suggestion: String) -> UncertaintyMatch {
        let source = clauses(claim)
        let proposal = clauses(suggestion)
        var hedgedClaimsMappedToProposal = [Int: Int]()
        var foundHedgeLoss = false
        var foundAmbiguity = false

        for sourceClaim in source {
            let sourceHedges = hedges(in: sourceClaim)
            guard !sourceHedges.isEmpty else { continue }

            let tokens = contentTokens(sourceClaim)
            let needed = max(1, Int(ceil(0.6 * Double(tokens.count))))
            let candidates = proposal.enumerated().filter { _, candidate in
                overlap(tokens, contentTokens(candidate)) >= needed
            }

            if candidates.count != 1 {
                // More than one possible claim (merged boundaries), or none (claim
                // vanished): the hedge-to-claim binding cannot be established.
                foundAmbiguity = true
                continue
            }

            let (index, _) = candidates[0]
            hedgedClaimsMappedToProposal[index, default: 0] += 1
            if hedges(in: proposal[index]).isEmpty {
                foundHedgeLoss = true
            }
        }

        // Two hedged claims merged into one clause carrying a single hedge: the
        // surviving hedge must not mask the loss on the other claim.
        for (index, mapped) in hedgedClaimsMappedToProposal {
            if mapped > hedges(in: proposal[index]).count { foundAmbiguity = true }
        }

        if foundHedgeLoss { return .hedgeLoss }
        if foundAmbiguity { return .ambiguous }
        return .allowed
    }

    // MARK: - Helpers

    private static func normalized(_ text: String) -> String {
        let decomposed = text.decomposedStringWithCanonicalMapping
        let scalars = decomposed.unicodeScalars.filter { !CharacterSet.nonBaseCharacters.contains($0) }
        return String(scalars).lowercased()
    }

    private static func contains(_ phrase: String, in text: String) -> Bool {
        let pattern = #"\b"# + NSRegularExpression.escapedPattern(for: normalized(phrase)) + #"\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return false }
        return regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)) != nil
    }

    private static func removing(_ phrase: String, from text: String) -> String {
        let pattern = #"\b"# + NSRegularExpression.escapedPattern(for: normalized(phrase)) + #"\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return text }
        return regex.stringByReplacingMatches(in: text, options: [],
                                              range: NSRange(text.startIndex..., in: text),
                                              withTemplate: " ")
    }

    private static func hedges(in text: String) -> [String] {
        let value = normalized(text)
        return hedges.filter { contains($0, in: value) }
    }

    private static func contentTokens(_ text: String) -> Set<String> {
        var value = normalized(text)
        for hedge in hedges { value = removing(hedge, from: value) }
        let raw = value.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        let meaningful = Set(raw.filter { !stopwords.contains($0) })
        return meaningful.isEmpty ? Set(raw) : meaningful
    }

    /// Deterministic lexical stem/prefix tolerance (`doc` matches `documento`),
    /// so a hedge rephrasing with a slightly different word still binds to its claim.
    private static func tokensMatch(_ lhs: String, _ rhs: String) -> Bool {
        if lhs == rhs { return true }
        let shorter = min(lhs.count, rhs.count)
        guard shorter >= 3 else { return false }
        return lhs.hasPrefix(rhs) || rhs.hasPrefix(lhs)
    }

    private static func overlap(_ lhs: Set<String>, _ rhs: Set<String>) -> Int {
        lhs.filter { left in rhs.contains { tokensMatch(left, $0) } }.count
    }

    private static func clauses(_ text: String) -> [String] {
        var result: [String] = []
        var cursor = text.startIndex
        let range = NSRange(text.startIndex..., in: text)
        for match in clauseSeparators.matches(in: text, options: [], range: range) {
            guard let matchRange = Range(match.range, in: text) else { continue }
            let clause = String(text[cursor..<matchRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !clause.isEmpty { result.append(clause) }
            cursor = matchRange.upperBound
        }
        let tail = String(text[cursor...]).trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty { result.append(tail) }
        return result
    }
}

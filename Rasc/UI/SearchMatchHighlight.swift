import SwiftUI

/// Search-match highlighting shared by Home, Quick Search and the command palette.
///
/// Marks each occurrence of a query word with a neutral background behind the text.
/// The text's own color is never changed, so contrast, truncation and Increase
/// Contrast handling stay intact, and VoiceOver keeps reading the plain string.
///
/// Matching is folded (case / diacritic / width insensitive) like the rest of the
/// search stack. Occurrences can be restricted to token starts to mirror the FTS5
/// prefix semantics used by Home and Quick Search; the command palette, which
/// filters by substring, marks matches anywhere with `tokenStartOnly: false`.
enum RascSearchMatch {

    /// Query words, folded and split on whitespace/punctuation, in query order.
    /// Duplicates are removed because re-marking the same span adds nothing.
    static func queryWords(_ query: String, locale: Locale = .current) -> [String] {
        var seen = Set<String>()
        var words: [String] = []
        for raw in query.split(whereSeparator: { $0.isWhitespace || $0.isPunctuation }) {
            let folded = String(raw).folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: locale
            )
            guard !folded.isEmpty, seen.insert(folded).inserted else { continue }
            words.append(folded)
        }
        return words
    }

    /// Folded-compare ranges of `word` in `text`, valid in `text`'s original indices.
    /// Foundation's folded comparison is used deliberately so folding never drifts
    /// the length of the underlying string (e.g. ß → ss).
    static func ranges(
        of word: String,
        in text: String,
        tokenStartOnly: Bool,
        locale: Locale = .current
    ) -> [Range<String.Index>] {
        var hits: [Range<String.Index>] = []
        var searchStart = text.startIndex
        while searchStart < text.endIndex,
              let range = text.range(
                of: word,
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                range: searchStart..<text.endIndex,
                locale: locale
              ) {
            if !tokenStartOnly || isTokenStart(text, range.lowerBound) {
                hits.append(range)
            }
            searchStart = range.upperBound
        }
        return hits
    }

    /// A token start mirrors the FTS5 unicode61 tokenizer: a word must begin at the
    /// string start or right after a non-word character. unicode61 treats `_` as a
    /// separator (verified against sqlite), so a match directly after `_` is a
    /// token start, not mid-token. Only a preceding letter/number/alphabetic
    /// scalar means this occurrence is mid-token.
    private static func isTokenStart(_ text: String, _ index: String.Index) -> Bool {
        guard index != text.startIndex else { return true }
        let before = text[text.index(before: index)]
        return !(before.isLetter || before.isNumber || before.unicodeScalars.contains { $0.properties.isAlphabetic })
    }

    /// AttributedString with `mark` painted behind every match. Foreground color is
    /// left untouched so the call site keeps full control of the text color.
    static func highlighted(
        _ text: String,
        query: String,
        mark: Color,
        tokenStartOnly: Bool,
        locale: Locale = .current
    ) -> AttributedString {
        var out = AttributedString(text)
        for word in queryWords(query, locale: locale) {
            for hit in ranges(of: word, in: text, tokenStartOnly: tokenStartOnly, locale: locale) {
                guard let lower = AttributedString.Index(hit.lowerBound, within: out),
                      let upper = AttributedString.Index(hit.upperBound, within: out) else { continue }
                out[lower..<upper].backgroundColor = mark
            }
        }
        return out
    }
}

import SwiftUI

/// Word-level diff between two versions of a note, used by the Refine preview to
/// show exactly what a suggestion would change before it is accepted.
///
/// Tokens are grapheme-cluster runs of word characters (letters/numbers) and runs
/// of everything else, so punctuation and spacing participate in alignment. Common
/// prefix and suffix runs are trimmed first; the remaining middles are aligned
/// with a bounded LCS. Anything beyond a size guard falls back to whole-middle
/// replace, which stays honest: it never claims finer alignment than it computed.
enum WordDiff {
    enum Run: Equatable, Sendable {
        case same(String)
        case added(String)
        case removed(String)
    }

    /// Maximum middle size for the LCS pass. Above this, the middles are emitted
    /// as a single replace instead of paying quadratic time and memory.
    static let lcsBudget = 1_000_000

    /// Splits text into word and non-word runs. Characters are Swift graphemes,
    /// so composed diacritics and emoji stay intact.
    static func tokens(_ text: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var currentIsWord: Bool?
        for ch in text {
            let isWord = ch.isLetter || ch.isNumber
            if let kind = currentIsWord, kind == isWord {
                current.append(ch)
            } else {
                if !current.isEmpty { tokens.append(current) }
                current = String(ch)
                currentIsWord = isWord
            }
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }

    /// The diffed runs of `oldText → newText`, adjacent same-kind runs coalesced.
    static func diff(from oldText: String, to newText: String) -> [Run] {
        let a = tokens(oldText)
        let b = tokens(newText)

        var start = 0
        while start < min(a.count, b.count), a[start] == b[start] {
            start += 1
        }
        var endA = a.count
        var endB = b.count
        while endA > start, endB > start, a[endA - 1] == b[endB - 1] {
            endA -= 1
            endB -= 1
        }

        var runs: [Run] = []
        if start > 0 {
            runs.append(.same(a[0..<start].joined()))
        }
        let middleA = Array(a[start..<endA])
        let middleB = Array(b[start..<endB])
        if !middleA.isEmpty || !middleB.isEmpty {
            if middleA.count * middleB.count > lcsBudget {
                if !middleA.isEmpty { runs.append(.removed(middleA.joined())) }
                if !middleB.isEmpty { runs.append(.added(middleB.joined())) }
            } else {
                runs.append(contentsOf: lcsRuns(middleA, middleB))
            }
        }
        if endA < a.count {
            runs.append(.same(a[endA...].joined()))
        }
        return coalesced(runs)
    }

    /// How many changes the user should expect to review. A replace (removed
    /// immediately followed by added) counts as one change; isolated adds or
    /// removals each count once. For a caption such as "3 changes".
    static func changeCount(from oldText: String, to newText: String) -> Int {
        changeCount(of: diff(from: oldText, to: newText))
    }

    /// Change count of precomputed runs; lets callers that already hold the diff
    /// avoid paying the LCS a second time.
    static func changeCount(of runs: [Run]) -> Int {
        var count = 0
        var inChange = false
        for run in runs {
            switch run {
            case .same:
                inChange = false
            case .removed, .added:
                if !inChange { count += 1 }
                inChange = true
            }
        }
        return count
    }

    // MARK: - Internals

    private static func lcsRuns(_ a: [String], _ b: [String]) -> [Run] {
        let n = a.count
        let m = b.count
        // dp[i][j] = length of the LCS of a[i...] and b[j...]
        var dp = [[Int]](repeating: [Int](repeating: 0, count: m + 1), count: n + 1)
        for i in (0..<n).reversed() {
            for j in (0..<m).reversed() {
                if a[i] == b[j] {
                    dp[i][j] = dp[i + 1][j + 1] + 1
                } else {
                    dp[i][j] = max(dp[i + 1][j], dp[i][j + 1])
                }
            }
        }
        var runs: [Run] = []
        var i = 0
        var j = 0
        var removed = ""
        var added = ""
        func flushReplacement() {
            if !removed.isEmpty { runs.append(.removed(removed)); removed = "" }
            if !added.isEmpty { runs.append(.added(added)); added = "" }
        }
        while i < n, j < m {
            if a[i] == b[j] {
                flushReplacement()
                runs.append(.same(a[i]))
                i += 1
                j += 1
            } else if dp[i + 1][j] >= dp[i][j + 1] {
                removed += a[i]
                i += 1
            } else {
                added += b[j]
                j += 1
            }
        }
        while i < n {
            removed += a[i]
            i += 1
        }
        while j < m {
            added += b[j]
            j += 1
        }
        flushReplacement()
        return runs
    }

    private static func coalesced(_ runs: [Run]) -> [Run] {
        var out: [Run] = []
        for run in runs {
            guard let last = out.last else {
                out.append(run)
                continue
            }
            switch (last, run) {
            case (.same(let x), .same(let y)):
                out[out.count - 1] = .same(x + y)
            case (.added(let x), .added(let y)):
                out[out.count - 1] = .added(x + y)
            case (.removed(let x), .removed(let y)):
                out[out.count - 1] = .removed(x + y)
            default:
                out.append(run)
            }
        }
        return out
    }

    // MARK: - Rendering

    /// The diff as a single AttributedString: removed words struck through in
    /// secondary text, added words bold and underlined in primary ink. No brand
    /// color is used; copper stays exclusive to Keep.
    static func attributed(
        from oldText: String,
        to newText: String,
        textColor: Color,
        removedColor: Color
    ) -> AttributedString {
        attributed(from: diff(from: oldText, to: newText), textColor: textColor, removedColor: removedColor)
    }

    /// Attributed rendering of precomputed runs; lets callers that already hold the
    /// diff avoid paying the LCS a second time.
    static func attributed(
        from runs: [Run],
        textColor: Color,
        removedColor: Color
    ) -> AttributedString {
        var out = AttributedString()
        for (index, run) in runs.enumerated() {
            switch run {
            case .same(let text):
                var piece = AttributedString(text)
                piece.foregroundColor = textColor
                out += piece
            case .removed(let text):
                var piece = AttributedString(text)
                piece.foregroundColor = removedColor
                piece.strikethroughStyle = .single
                out += piece
            case .added(let text):
                var piece = AttributedString(text)
                piece.foregroundColor = textColor
                piece.inlinePresentationIntent = .stronglyEmphasized
                piece.underlineStyle = .single
                out += piece
            }
            // Reading-order-faithful seam: when two non-whitespace change runs
            // abut (…friday ~~please~~ **monday**), leave a single clear space so
            // strike and underline never read as one word. Visual only.
            if index + 1 < runs.count {
                let abuts = isNonWhitespaceBoundary(runs[index], runs[index + 1])
                if abuts {
                    var gap = AttributedString(" ")
                    gap.foregroundColor = .clear
                    out += gap
                }
            }
        }
        return out
    }

    private static func isNonWhitespaceBoundary(_ first: Run, _ second: Run) -> Bool {
        let firstText: String
        let secondText: String
        switch first {
        case .removed(let text), .added(let text):
            firstText = text
        case .same:
            return false
        }
        switch second {
        case .removed(let text), .added(let text):
            secondText = text
        case .same:
            return false
        }
        return firstText.last?.isWhitespace != true && secondText.first?.isWhitespace != true
    }
}

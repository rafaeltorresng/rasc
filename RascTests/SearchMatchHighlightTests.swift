import Foundation
import SwiftUI
import Testing
@testable import Rasc

@Suite
struct SearchMatchHighlightTests {
    private let mark = RascSurfacePalette.standard.searchMark(for: .light, increasedContrast: false)

    @Test
    func queryWordsFoldCaseDiacriticsAndPunctuation() {
        let words = RascSearchMatch.queryWords("Pâté, crème  CRÈME")
        #expect(words == ["pate", "creme"])
    }

    @Test
    func queryWordsAreEmptyForWhitespaceOnly() {
        #expect(RascSearchMatch.queryWords("   ").isEmpty)
        #expect(RascSearchMatch.queryWords("!!!").isEmpty)
    }

    @Test
    func anywhereModeMarksMidWordOccurrences() {
        let hits = RascSearchMatch.ranges(
            of: "ate",
            in: "slate plate",
            tokenStartOnly: false
        )
        #expect(hits.count == 2)
        #expect(String("slate plate"[hits[0]]) == "ate")
        #expect(String("slate plate"[hits[1]]) == "ate")
    }

    @Test
    func tokenStartModeSkipsMidTokenOccurrences() {
        let text = "disintegrate grate"
        let hits = RascSearchMatch.ranges(of: "grate", in: text, tokenStartOnly: true)
        #expect(hits.count == 1)
        #expect(String(text[hits[0]]) == "grate")
        #expect(text.distance(from: text.startIndex, to: hits[0].lowerBound) == 13)
    }

    @Test
    func tokenStartModeAllowsStringStartAndPunctuationBoundaries() {
        let text = "grate (grated) grated. grate"
        let hits = RascSearchMatch.ranges(of: "grat", in: text, tokenStartOnly: true)
        #expect(hits.count == 4)
    }

    @Test
    func highlightedMarksBackgroundsWithoutTouchingForeground() {
        let attributed = RascSearchMatch.highlighted(
            "Pâté tonight",
            query: "pate",
            mark: mark,
            tokenStartOnly: true
        )
        let backgrounds = attributed.runs.compactMap(\.backgroundColor)
        #expect(backgrounds.count == 1)
        let foregrounds = attributed.runs.compactMap(\.foregroundColor)
        #expect(foregrounds.isEmpty)
    }

    @Test
    func highlightedWithEmptyQueryLeavesStringPlain() {
        let attributed = RascSearchMatch.highlighted(
            "unchanged text",
            query: "",
            mark: mark,
            tokenStartOnly: true
        )
        #expect(attributed.runs.count == 1)
        #expect(attributed.runs.first?.backgroundColor == nil)
        #expect(String(attributed.characters) == "unchanged text")
    }

    @Test
    func highlightedMultiWordMarksEachWord() {
        let attributed = RascSearchMatch.highlighted(
            "gratitude and grace",
            query: "grat grac",
            mark: mark,
            tokenStartOnly: true
        )
        let backgrounds = attributed.runs.filter { $0.backgroundColor != nil }.count
        #expect(backgrounds == 2)
    }
}

import Foundation
import SwiftUI
import Testing
@testable import Rasc

@Suite
struct WordDiffTests {
    @Test
    func identicalStringsProduceOneSameRun() {
        let runs = WordDiff.diff(from: "hello world", to: "hello world")
        #expect(runs == [.same("hello world")])
        #expect(WordDiff.changeCount(from: "hello world", to: "hello world") == 0)
    }

    @Test
    func singleWordReplacementCountsAsOneChange() {
        let runs = WordDiff.diff(from: "draft the memo on friday", to: "draft the memo on monday")
        #expect(runs == [.same("draft the memo on "), .removed("friday"), .added("monday")])
        #expect(WordDiff.changeCount(from: "draft the memo on friday", to: "draft the memo on monday") == 1)
    }

    @Test
    func insertionOnlyIsOneChange() {
        let count = WordDiff.changeCount(from: "ship it today", to: "ship it earlier today")
        #expect(count == 1)
    }

    @Test
    func deletionOnlyIsOneChange() {
        let count = WordDiff.changeCount(from: "ship it earlier today", to: "ship it today")
        #expect(count == 1)
    }

    @Test
    func separateEditSitesCountSeparately() {
        let count = WordDiff.changeCount(
            from: "buy milk tomorrow",
            to: "buy oat milk on friday"
        )
        // "oat " inserted, "tomorrow" -> "on friday" replaced
        #expect(count == 2)
    }

    @Test
    func outputNeverContainsAdjacentSameKindRuns() {
        let cases = [
            ("a b c d", "a x y d"),
            ("the cat sat", "the dog sat down"),
            ("one two three", "one two three four five"),
            ("milk and eggs", "milk and oat milk")
        ]
        for (old, new) in cases {
            let runs = WordDiff.diff(from: old, to: new)
            for (previous, next) in zip(runs, runs.dropFirst()) {
                switch (previous, next) {
                case (.same, .same), (.added, .added), (.removed, .removed):
                    Issue.record("adjacent same-kind runs in \(runs)")
                default:
                    break
                }
            }
        }
    }

    @Test
    func tokensKeepPunctuationAndWhitespace() {
        let tokens = WordDiff.tokens("hello, world!")
        #expect(tokens == ["hello", ", ", "world", "!"])
    }

    @Test
    func punctuationOnlyChangeIsAChange() {
        let count = WordDiff.changeCount(from: "a, b", to: "a; b")
        #expect(count == 1)
    }

    @Test
    func numbersParticipateInDiff() {
        let runs = WordDiff.diff(from: "at 3% and 40%", to: "at 5% and 40%")
        #expect(runs.contains(.removed("3")))
        #expect(runs.contains(.added("5")))
    }

    @Test
    func graphemeClustersSurvive() {
        let runs = WordDiff.diff(from: "cafe ☕ today", to: "café ☕ today")
        #expect(runs.contains(.removed("cafe")))
        #expect(runs.contains(.added("café")))
    }

    @Test
    func emptyOriginalIsAllAdded() {
        let runs = WordDiff.diff(from: "", to: "brand new note")
        #expect(runs == [.added("brand new note")])
    }

    @Test
    func emptyNewIsAllRemoved() {
        let runs = WordDiff.diff(from: "gone entirely", to: "")
        #expect(runs == [.removed("gone entirely")])
    }

    @Test
    func attributedMarksRemovedAndAdded() {
        let attributed = WordDiff.attributed(
            from: "old phrasing here",
            to: "new phrasing here",
            textColor: .primary,
            removedColor: .secondary
        )
        let strikes = attributed.runs.filter { $0.strikethroughStyle != nil }.count
        let underlines = attributed.runs.filter { $0.underlineStyle != nil }.count
        #expect(strikes >= 1)
        #expect(underlines >= 1)
        // A clear space separates adjacent change runs so strike and underline never read as one word.
        #expect(String(attributed.characters) == "old new phrasing here")
    }
}

import Foundation

/// Rejects selection replacements that copy a longer verbatim span from another
/// occurrence of the same selected text elsewhere in the note.
///
/// Boundary policy: an occurrence counts only when the selected text is bounded on
/// both sides by note edges or non-alphanumeric characters (excluding `_`). This
/// prevents `log` inside `catalog` from counting as a duplicate of selected `log`.
enum RefinementSelectionDuplicateContextGuard {
    static func violates(replacement: String, request: RefinementRequest) -> Bool {
        guard request.scope == .selection,
              let selectedRange = request.snapshot.selection,
              replacement.count > request.inputText.count
        else {
            return false
        }

        let note = request.snapshot.text
        let selected = request.inputText
        let occurrences = standaloneOccurrences(of: selected, in: note)
        guard occurrences.count > 1 else { return false }

        var searchStart = note.startIndex
        while searchStart < note.endIndex,
              let replacementRange = note[searchStart...].range(of: replacement) {
            for occurrence in occurrences where occurrence != selectedRange {
                if replacementRange.lowerBound <= occurrence.lowerBound,
                   occurrence.upperBound <= replacementRange.upperBound {
                    return true
                }
            }
            searchStart = replacementRange.upperBound
        }

        return false
    }

    static func standaloneOccurrences(
        of selected: String,
        in note: String
    ) -> [Range<String.Index>] {
        guard !selected.isEmpty else { return [] }

        var occurrences: [Range<String.Index>] = []
        var searchStart = note.startIndex
        while searchStart < note.endIndex,
              let range = note[searchStart...].range(of: selected) {
            if isStandaloneOccurrence(of: selected, at: range, in: note) {
                occurrences.append(range)
            }
            searchStart = range.upperBound
        }
        return occurrences
    }

    private static func isStandaloneOccurrence(
        of selected: String,
        at range: Range<String.Index>,
        in note: String
    ) -> Bool {
        hasBoundaryBefore(note, at: range.lowerBound, for: selected)
            && hasBoundaryAfter(note, at: range.upperBound, for: selected)
    }

    private static func hasBoundaryBefore(
        _ note: String,
        at index: String.Index,
        for selected: String
    ) -> Bool {
        guard index > note.startIndex else { return true }
        let previous = note[note.index(before: index)]
        return isBoundaryCharacter(previous, for: selected)
    }

    private static func hasBoundaryAfter(
        _ note: String,
        at index: String.Index,
        for selected: String
    ) -> Bool {
        guard index < note.endIndex else { return true }
        return isBoundaryCharacter(note[index], for: selected)
    }

    private static func isBoundaryCharacter(_ character: Character, for selected: String) -> Bool {
        if character.isWhitespace || character.isNewline {
            return true
        }
        if RefinementContentUnitClassifier.classify(selected) != nil {
            return !isWordInteriorCharacter(character)
        }
        return !character.isLetter && !character.isNumber
    }

    private static func isWordInteriorCharacter(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.contains($0) || $0 == "_"
        }
    }
}

extension RefinementRequest {
    func hasDuplicateContextLeak(_ text: String) -> Bool {
        RefinementSelectionDuplicateContextGuard.violates(replacement: text, request: self)
    }
}

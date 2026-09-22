# M12B-004C exact production diff

## Domain policy

`Rasc/Domain/Refinement.swift` now owns:

```swift
enum RefinementPreflightReason: String, Codable, Equatable, Sendable {
    case wholeNoteSingleContentUnit = "whole_note_single_content_unit"
}

enum RefinementPreflightOutcome: Equatable, Sendable {
    case proceed
    case noChange(RefinementPreflightReason)
}

struct RefinementPreflightPolicy {
    static func evaluate(_ request: RefinementRequest) -> RefinementPreflightOutcome {
        guard request.scope == .wholeNote,
              RefinementContentUnitClassifier.classify(request.inputText) != nil
        else {
            return .proceed
        }
        return .noChange(.wholeNoteSingleContentUnit)
    }

    static func result(for request: RefinementRequest) -> RefinementResult? {
        guard case .noChange = evaluate(request) else { return nil }
        return RefinementResult(
            decision: .noChange,
            kind: .alreadyGood,
            text: request.inputText
        )
    }
}
```

The adjacent deterministic classifier recognizes these structural kinds:

```swift
lexicalWord
wordWithAttachedPunctuation
url
email
handle
number
money
emoji
technicalIdentifier
codeLike
mixedAlphanumericIdentifier
```

It trims outer whitespace, treats an optional-whitespace currency marker plus number as one money unit, otherwise requires exactly one whitespace-delimited structural form, rejects empty/whitespace/punctuation-only input, and uses no word dictionary.

## Session orchestration

Immediately after constructing and storing the immutable request, and before checking provider availability, `ScratchpadSession.performRefinement` now executes exactly this branch:

```swift
if RefinementPreflightPolicy.result(for: request) != nil {
    logRefinementRejection(.noChange)
    finishRefinement(with: .alreadyUseful)
    return
}
```

This preserves the existing noChange UX and prevents provider lookup, availability, language resolution, `LanguageModelSession`, generation, and validation for eligible requests.

## Evaluation trace

`RefineEvalRunRecord` adds one optional field:

```swift
var preflightReason: String? = nil
```

`RefineEvalRunner.executeCase` evaluates the same production policy before `provider.refine`, emits the existing noChange result, records the reason, and measures preflight latency. This is instrumentation only; it does not add a second policy.

## Explicitly unchanged

- M12B-001 prompt and `refine-v2-language` version
- `FoundationModelsRefinementProvider` generation behavior
- language resolver and validator
- Foundation Models default sampling / generation options
- protected-token and selection guards
- all selection Refine behavior
- UX, Settings, persistence, and database schema

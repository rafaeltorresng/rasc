# Current selection Refine policy (M12B-005F)

## Request construction

- Scope becomes `.selection` when `NoteSnapshot.selection` is non-nil.
- `inputText` is the selected substring only.
- `selectionContext` exposes read-only before/after windows (100 characters each) for prompt context only.

## Post-generation production guards (selection scope)

Applied after one Foundation Models generation and semantic literal validators:

| Order | Guard | Behavior on violation |
|---|---|---|
| 1 | Semantic literal validators | noChange; obligations derived from selected source only |
| 2 | Empty replacement | noChange |
| 3 | `allowsChangedText` | Rejects replacements longer than `max(48, 4× selection length)` |
| 4 | `isReplacementOnly` | Rejects replacements containing unchanged surrounding context fragments (minimum match length `max(12, selectionLength/2)`) |
| 5 | Identical output | noChange if replacement equals selected source |

## Explicit non-goals in current production

- No duplicate-span disambiguation beyond first `range(of:)` match in eval harness
- No date/generic-number semantic literal validation
- No repair/regeneration after rejection
- No new user-visible error states

## Eval harness fidelity

`RefineEvalRunner` records `productionRejection` reasons (`context_leak`, `runaway_expansion`, `invalid_replacement`, `no_change`) while preserving raw proposal diagnostics for audit classification.

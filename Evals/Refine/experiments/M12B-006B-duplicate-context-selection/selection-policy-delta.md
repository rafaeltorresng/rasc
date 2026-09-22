# Selection policy delta — M12B-006B

## New guard

Reject when all hold:

1. scope is selection
2. selected source occurs standalone more than once in the full note
3. replacement is longer than selected source
4. replacement equals a longer verbatim note span that contains a **different** standalone occurrence of the selected source

## Boundary policy

Standalone occurrence = exact selected substring bounded on both sides by note edge or non-alphanumeric character (underscore counts as interior). Prevents `log` inside `catalog` from being treated as a duplicate of selected `log`.

## Non-goals preserved

- Does not change `isReplacementOnly` thresholds
- Does not apply to whole-note Refine
- Does not reject legitimate expansions such as `retry` → `retry logic` when that span is not copied verbatim from another occurrence

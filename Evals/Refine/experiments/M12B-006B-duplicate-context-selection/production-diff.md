# Production diff — M12B-006B

## Added

- `Rasc/Domain/RefinementSelectionDuplicateContextGuard.swift`
- `RefinementRequest.hasDuplicateContextLeak(_:)`

## Pipeline (selection scope, after existing guards)

1. semantic literal validators
2. empty replacement
3. `allowsChangedText`
4. `isReplacementOnly`
5. **duplicate-context guard**
6. identical-to-selection noChange

## Diagnostics

- Scratchpad rejection reason: `selectionDuplicateContextLeak`
- Eval `productionRejection`: `selectionDuplicateContextLeak`
- Logs record reason only; no selected text, replacement, or surrounding context

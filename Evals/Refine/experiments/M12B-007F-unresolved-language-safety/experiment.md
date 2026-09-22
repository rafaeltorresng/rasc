# M12B-007F — Unresolved-language safety guard

## Hypothesis

M12B-007D Policy A: when resolver confidence is insufficient, reject raw generation to noChange only when source-side evidence is strong and independent output-language evidence is high-confidence and disagrees with source evidence.

## Scope

- `RefineUnresolvedLanguageGuard` only
- M12B-007E validator unchanged for high-confidence resolver targets
- One Foundation Models generation per eligible request

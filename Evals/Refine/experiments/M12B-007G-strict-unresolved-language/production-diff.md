# Production diff — M12B-007G

## Guard eligibility narrowing

- Added `RefineUnresolvedLanguageGuard.isStrictUnresolvedEligible(_:)`:
  - requires `ambiguous|unknown` + `insufficient` confidence
  - excludes `mixed|portuguese|english|spanish` labels explicitly
- `RefineUnresolvedLanguageGuard.evaluate` returns `notEvaluated` when ineligible
- Trace `unresolvedGuardEvaluated` now reflects strict eligibility only

## Unchanged from M12B-007E/007F guard internals

- Source evidence assessor
- Output independent assessment thresholds
- Rejection semantics (single generation, reject to existing noChange)
- Resolver v2 and M12B-007E validator

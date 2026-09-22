# Production diff — M12B-007F

## Unresolved-language guard

- Added `RefineLanguageSourceEvidenceAssessor` (Policy A marker + morphology source evidence; no locale, no synthetic resolution).
- Added `RefineUnresolvedLanguageGuard` applied after M12B-007E validator when `resolved.enforcesPostValidation` is false.
- Rejects to existing noChange when guard reason is `unresolvedLanguageShift`.
- Eval trace records source evidence, guard decision, and output assessment metadata (no note text).

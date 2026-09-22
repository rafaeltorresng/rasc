# Production diff — M12B-007E

## Validator

- Added `RefineIndependentLanguageAssessor` using `NLLanguageRecognizer` (same high-confidence threshold as eval assessor).
- `RefineLanguageValidator.validate` now:
  1. accepts when independent assessment is high-confidence and matches resolved target (`independentHighConfidenceMatch`)
  2. rejects when independent assessment is high-confidence and mismatches resolved target (`independentHighConfidenceMismatch`)
  3. otherwise preserves marker-based fallback (`existingFallback`)
- Unresolved / insufficient resolver confidence remains non-enforcing (unchanged M12B-007B behavior).

## Diagnostics (eval trace only)

- `RefinementLanguageTrace` records marker/independent assessment labels, independent confidence, and validator decision reason.
- No note text added to production diagnostics.

# M12B-007A language resolver calibration

Evaluation-only comparison of production `RefineLanguageResolver` (A) vs candidate resolver (B).

## Decision

**ACCEPT FOR EXPERIMENT**

Candidate materially improves resolver target accuracy (+38.8 pp overall), fixes 14/18 frontier wrong-language cases, and reduces confident wrong targets on tiny/technical inputs with only 4 benchmark regressions (mostly acceptable loss of accidental system-locale guesses).

## Current production resolver

- Run `RefineLanguageDetection.detect()` on note + selection context.
- Portuguese / English / Spanish / mixed detections become high-confidence targets.
- Ambiguous / unknown inputs fall back to the first supported locale in `Locale.preferredLanguages` (default `en-US`) with insufficient confidence and validation skipped.
- Detection applies a technical-English boost (`retry`, `queue`, `_`) and treats near-tie marker scores as `mixed`.

## Candidate resolver

See `resolver-candidate.md`. Highlights: no technical-English boost, stricter mixed threshold, technical-only/tiny unresolved path, optional `NLLanguageRecognizer` tie-break for longer text, no system-locale fallback.

## Overall accuracy

- Production: 100/245 (40.8%)
- Candidate: 195/245 (79.6%)

## Clear PT / EN / ES

| cohort | production | candidate |
| --- | --- | --- |
| clearPT | 19/86 correct target (34.9% overall) | 49/86 correct target (79.1% overall) |
| clearEN | 26/73 correct target (46.6% overall) | 43/73 correct target (91.8% overall) |
| clearES | 10/12 correct target (83.3% overall) | 11/12 correct target (91.7% overall) |

## Mixed language

| subcohort | production | candidate |
| --- | --- | --- |
| mixedPTTechnical | 2/5 | 4/5 |
| mixedESTechnical | 0/0 | 0/0 |
| mixedOther | 1/9 | 3/9 |

## Tiny / ambiguous

- Production: 15/24 correctly unresolved; 9 confident wrong assignments
- Candidate: 22/24 correctly unresolved; 2 confident wrong assignments
- `selection-extra-007`: production `en/insufficient` → candidate `ambiguous/insufficient`

## Frontier wrong-language cases (18)

- Fixes: 14
- Unresolved (acceptable vs prior wrong/mixed target): 2
- Same incorrect target: 2
- Regressions: 0

Prior adjudication: 17/18 had incorrect or noncommittal resolver targets. Candidate fixes 9 to the expected dominant language and moves 4 more from wrong/mixed/confident-fallback to unresolved.

## Low-confidence rate

- Production: 22.4%
- Candidate: 33.9%

## Regressions

- `acronym-002` (clearEN): production low_confidence_correct_fallback → candidate low_confidence
- `acronym-004` (clearEN): production low_confidence_correct_fallback → candidate low_confidence
- `acronym-005` (clearEN): production low_confidence_correct_fallback → candidate low_confidence
- `selection-extra-005` (selection): production correct_unresolved → candidate incorrect_confident

## Remaining failure clusters (candidate)

- `incorrect_confident:pt:marker_clear_margin` (13): legacy-selection-pt-misspelling-001, selection-pt-fragment-002, selection-pt-tiny-008, short-pt-001, short-pt-002, short-pt-006, variant-pt-002, variant-pt-003
- `low_confidence:ambiguous:unresolved_insufficient_evidence` (10): acronym-001, acronym-002, acronym-004, acronym-005, long-pt-002, long-pt-003, long-pt-004, long-pt-005
- `incorrect_confident:pt:marker_single_language` (9): incomplete-002, legacy-ambiguous-fragment-pt-001, selection-extra-001, selection-extra-002, selection-extra-006, short-pt-007, short-pt-015, tiny-pt-001
- `incorrect_target:en:marker_single_language` (4): mixed-tech-001, variant-pt-022, variant-pt-023, variant-pt-024
- `incorrect_confident:en:natural_language_tie_break` (3): mixed-tech-004, mixed-tech-008, selection-extra-008
- `incorrect_confident:en:marker_clear_margin` (2): legacy-selection-ambiguous-nochange-001, selection-ambiguous-005
- `incorrect_confident:en:marker_single_language` (2): legacy-technical-mixed-001, selection-leak-test-007
- `incorrect_mixed:mixed:marker_true_tie` (2): legacy-mixed-language-001, mixed-pt-en-001

## Next step

Run **M12B-007B** as a production experiment behind the existing eval gate, measuring end-to-end wrong-language edits with the candidate resolver wired in eval/production shadow mode.

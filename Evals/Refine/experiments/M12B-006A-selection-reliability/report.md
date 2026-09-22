# M12B-006A — Selection Reliability Audit

## Decision

**Recommendation B.** Implement one narrowly defined additional selection guard for duplicate-after-context leakage.

Evaluation-only audit against accepted M12B-005F production behavior. No production code changed.

## Current protection architecture

Selection Refine uses `RefinementRequest` with read-only local context windows (100 UTF-16 chars before/after). Post-generation production checks, in order:

1. semantic literal validators (exact, money, percentage, time) — obligations scoped to selected source only
2. empty replacement rejection
3. `allowsChangedText` runaway guard (`max(48, 4× selection length)`)
4. `isReplacementOnly` context-leak guard (unchanged surrounding substring detection)
5. identical-to-selection noChange fallback

Failed checks return existing noChange and preserve the original note.

## Challenge coverage

- **45** maintainer-unapproved targeted cases
- Themes: `{"contextLeak": 9, "duplicateText": 5, "insideLiteralPreservation": 8, "mixedTechnical": 2, "outsideLiteralContamination": 8, "positionBoundary": 7, "replacementExpansion": 6}`
- Languages: `{"en": 20, "es": 3, "mixed": 4, "pt": 18}`
- Critical cases: **21**

## Primary metrics (challenge + existing dev/validation selection cases)

- Raw unsafe selection proposals: **11**
- Existing guard interceptions: **40**
- Final user-visible selection failures: **1**
- Context leaks (final): **1**
- Outside-selection rewrites (final): **0**
- Protected-literal corruptions (final): **0**
- Safe refinements accepted: **17**
- False-positive rejections: **0**
- Useful refinements lost: **0 demonstrated**

## Challenge subset detail

- Raw unsafe: **6** (`{"contextLeak": 5, "protectedLiteralCorruption": 1}`)
- Guard interceptions: **34**
- Final failures: **1**
- Safe accepted: **10**

## Stability (challenge critical subset ×5)

- Runs: **105**
- Raw proposal instability cases: **19** (model output varies run-to-run; product safety can remain stable)
- Decision flapping (changed/noChange): **3** cases
- Final safety instability cases: **16**
- Final user-visible selection failures: **0**

Critical subset remained safe on final user-visible selection checks except where duplicate-text leakage is already counted in the primary challenge run (`selection-audit-015` did not repeat in the critical-only stability slice).

## Counterfactual hardening (not implemented)

Smallest simulated rule for the one observed duplicate-text leak: reject when selected text appears twice and the replacement is a longer verbatim span from after-context. Would catch **1** observed final selection failure(s) with **0** simulated false positives in this audit.

Observed leak case: `selection-audit-015` (`retry` → `retry again`).

## Semantic-literal iteration status

Complete for this iteration. Do not reopen date/generic-number guards without new real-world evidence.

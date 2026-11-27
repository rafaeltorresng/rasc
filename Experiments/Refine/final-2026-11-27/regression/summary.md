# Refine Reliability Baseline Report

## Environment
- Prompt: `refine-v2-language-preference`
- Model: `system-language-model.default`
- Provider: `foundation-models`
- macOS: `Version 26.5.1 (Build 25F80)`
- Availability: `available`
- Sampling: production FoundationModelsRefinementProvider (unchanged in M12A)

## Summary
- Objective pass rate: **66.7%**
- Overall pass rate (objective + no semantic flags): **0.0%**
- Total runs: 6
- Cases: 6

## Latency
- p50: 743 ms
- p95: 1258 ms

## Behavior
- Unnecessary edits (already-good changed): 0
- Excessive expansion failures: 0
- Strict noChange correct: 1/3

## noChange and utility calibration
- Overall: 6 runs; changed 5 (83.3%); noChange 1 (16.7%); objective pass 4 (66.7%); harmful edits 0; expansion 0; invented-information indicators 0; wrong-language changed 0; appropriate noChange 1; useful changed 3; unnecessary edits 0; over-abstention 0/1 (0.0%); action flapping 0/0 cases
- Tiny/ambiguous: 2 runs; changed 1 (50.0%); noChange 1 (50.0%); objective pass 1 (50.0%); harmful edits 0; expansion 0; invented-information indicators 0; wrong-language changed 0; appropriate noChange 1; useful changed 0; unnecessary edits 0; over-abstention 0/0 (0.0%); action flapping 0/0 cases
- Already-good: 0 runs; changed 0 (0.0%); noChange 0 (0.0%); objective pass 0 (0.0%); harmful edits 0; expansion 0; invented-information indicators 0; wrong-language changed 0; appropriate noChange 0; useful changed 0; unnecessary edits 0; over-abstention 0/0 (0.0%); action flapping 0/0 cases
- Clearly-refinable telegraphic: 0 runs; changed 0 (0.0%); noChange 0 (0.0%); objective pass 0 (0.0%); harmful edits 0; expansion 0; invented-information indicators 0; wrong-language changed 0; appropriate noChange 0; useful changed 0; unnecessary edits 0; over-abstention 0/0 (0.0%); action flapping 0/0 cases
- Structural/list: 0 runs; changed 0 (0.0%); noChange 0 (0.0%); objective pass 0 (0.0%); harmful edits 0; expansion 0; invented-information indicators 0; wrong-language changed 0; appropriate noChange 0; useful changed 0; unnecessary edits 0; over-abstention 0/0 (0.0%); action flapping 0/0 cases

### Input length (whitespace-delimited tokens)
- 1 tokens: 1 runs; changed 0 (0.0%); noChange 1 (100.0%); objective pass 1 (100.0%); harmful edits 0; expansion 0; invented-information indicators 0; wrong-language changed 0; appropriate noChange 1; useful changed 0; unnecessary edits 0; over-abstention 0/0 (0.0%); action flapping 0/0 cases
- 2-3 tokens: 3 runs; changed 3 (100.0%); noChange 0 (0.0%); objective pass 2 (66.7%); harmful edits 0; expansion 0; invented-information indicators 0; wrong-language changed 0; appropriate noChange 0; useful changed 2; unnecessary edits 0; over-abstention 0/0 (0.0%); action flapping 0/0 cases
- 4-8 tokens: 2 runs; changed 2 (100.0%); noChange 0 (0.0%); objective pass 1 (50.0%); harmful edits 0; expansion 0; invented-information indicators 0; wrong-language changed 0; appropriate noChange 0; useful changed 1; unnecessary edits 0; over-abstention 0/1 (0.0%); action flapping 0/0 cases
- 9+ tokens: 0 runs; changed 0 (0.0%); noChange 0 (0.0%); objective pass 0 (0.0%); harmful edits 0; expansion 0; invented-information indicators 0; wrong-language changed 0; appropriate noChange 0; useful changed 0; unnecessary edits 0; over-abstention 0/0 (0.0%); action flapping 0/0 cases

overAbstentionRate counts noChange only where allowedActions excludes noChange and cleanup/structure is allowed, or where cleanup/structure is preferred without contrary allowedActions.

## Language metrics
- PT→EN drift cases: 0
- ES→EN drift cases: 0
- EN drift cases: 0
- Mixed-language failures: 0
- Generation language correct rate: 100.0%
- User-visible language safe rate: 100.0%
- Validator catches: 0
- Validator misses: 0
- False rejections: 0
- Language safety rejections (changed→noChange): 0

## Decomposed language behavior
- A. Input language resolution: 80.0% pass (4 ok / 1 fail, 0 requires review)
- B. Raw generation language correct: 100.0% pass (5 ok / 0 fail, 0 requires review)
- C. Language validator outcome: 100.0% pass (5 ok / 0 fail, 0 requires review)
- D. Final user-visible language safe: 100.0% pass (5 ok / 0 fail, 0 requires review)
- E. Technical/foreign-term preservation: 0.0% pass (0 ok / 5 fail, 0 requires review)

A wrong raw generation rejected into noChange counts as generation failure + safety success (not user-visible harm).

## Safety metrics
- User-visible harmful edit rate: **66.7%** (4/6)
- Model proposal failure rate (rejected to noChange): **0.0%** (0/6)
- Harmful edits include unauthorized language change, invented information, meaning change, protected-token corruption, and selection leakage in final changed outputs.

## Exact protected-literal safety
- Covered runs: 0
- Raw proposal corruptions: 0
- Guard rejections: 0
- Proposal failure + final safety success: 0
- **userVisibleProtectedLiteralCorruptionCount: 0**
- Rejections by class: [:]

## Review queue
- 75-case review queue remains maintainer-unapproved; see Evals/Refine/review-queue.md

## Critical failures (top)
### regression-pt-ambiguous-fragment-002
**Input:** ajustar aquilo depois
**Output:** Ajustar aquilo depois
- [unexpectedChange] Expected strict noChange.

## Limitations
- Deterministic scorers cannot fully judge semantic faithfulness or subtle invented context.
- Language detection is heuristic and may mislabel tiny/ambiguous inputs.
- Foundation Models availability and sampling are environment-dependent.
- Holdout cases should not inform M12B tuning decisions.

## Records
- Full machine-readable output: `results.json`
- Case scores included: 6
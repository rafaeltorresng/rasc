# Refine Reliability Baseline Report

## Environment
- Prompt: `refine-v2-language-preference`
- Model: `system-language-model.default`
- Provider: `foundation-models`
- macOS: `Version 26.5.1 (Build 25F80)`
- Availability: `available`
- Sampling: production FoundationModelsRefinementProvider (unchanged in M12A)

## Summary
- Objective pass rate: **64.9%**
- Overall pass rate (objective + no semantic flags): **28.1%**
- Total runs: 57
- Cases: 57

## Latency
- p50: 747 ms
- p95: 1116 ms

## Behavior
- Unnecessary edits (already-good changed): 0
- Excessive expansion failures: 0
- Strict noChange correct: 7/9

## noChange and utility calibration
- Overall: 57 runs; changed 42 (73.7%); noChange 15 (26.3%); objective pass 37 (64.9%); harmful edits 12; expansion 0; invented-information indicators 0; wrong-language changed 2; appropriate noChange 11; useful changed 22; unnecessary edits 0; over-abstention 4/14 (28.6%); action flapping 0/0 cases
- Tiny/ambiguous: 9 runs; changed 2 (22.2%); noChange 7 (77.8%); objective pass 9 (100.0%); harmful edits 0; expansion 0; invented-information indicators 0; wrong-language changed 0; appropriate noChange 7; useful changed 2; unnecessary edits 0; over-abstention 0/0 (0.0%); action flapping 0/0 cases
- Already-good: 0 runs; changed 0 (0.0%); noChange 0 (0.0%); objective pass 0 (0.0%); harmful edits 0; expansion 0; invented-information indicators 0; wrong-language changed 0; appropriate noChange 0; useful changed 0; unnecessary edits 0; over-abstention 0/0 (0.0%); action flapping 0/0 cases
- Clearly-refinable telegraphic: 4 runs; changed 4 (100.0%); noChange 0 (0.0%); objective pass 4 (100.0%); harmful edits 0; expansion 0; invented-information indicators 0; wrong-language changed 0; appropriate noChange 0; useful changed 4; unnecessary edits 0; over-abstention 0/0 (0.0%); action flapping 0/0 cases
- Structural/list: 4 runs; changed 3 (75.0%); noChange 1 (25.0%); objective pass 3 (75.0%); harmful edits 1; expansion 0; invented-information indicators 0; wrong-language changed 0; appropriate noChange 0; useful changed 2; unnecessary edits 0; over-abstention 1/3 (33.3%); action flapping 0/0 cases

### Input length (whitespace-delimited tokens)
- 1 tokens: 6 runs; changed 0 (0.0%); noChange 6 (100.0%); objective pass 6 (100.0%); harmful edits 0; expansion 0; invented-information indicators 0; wrong-language changed 0; appropriate noChange 6; useful changed 0; unnecessary edits 0; over-abstention 0/0 (0.0%); action flapping 0/0 cases
- 2-3 tokens: 14 runs; changed 13 (92.9%); noChange 1 (7.1%); objective pass 12 (85.7%); harmful edits 2; expansion 0; invented-information indicators 0; wrong-language changed 0; appropriate noChange 1; useful changed 11; unnecessary edits 0; over-abstention 0/0 (0.0%); action flapping 0/0 cases
- 4-8 tokens: 22 runs; changed 15 (68.2%); noChange 7 (31.8%); objective pass 15 (68.2%); harmful edits 3; expansion 0; invented-information indicators 0; wrong-language changed 1; appropriate noChange 4; useful changed 8; unnecessary edits 0; over-abstention 3/6 (50.0%); action flapping 0/0 cases
- 9+ tokens: 15 runs; changed 14 (93.3%); noChange 1 (6.7%); objective pass 4 (26.7%); harmful edits 7; expansion 0; invented-information indicators 0; wrong-language changed 1; appropriate noChange 0; useful changed 3; unnecessary edits 0; over-abstention 1/8 (12.5%); action flapping 0/0 cases

overAbstentionRate counts noChange only where allowedActions excludes noChange and cleanup/structure is allowed, or where cleanup/structure is preferred without contrary allowedActions.

## Language metrics
- PT→EN drift cases: 2
- ES→EN drift cases: 0
- EN drift cases: 0
- Mixed-language failures: 0
- Generation language correct rate: 92.2%
- User-visible language safe rate: 94.1%
- Validator catches: 0
- Validator misses: 0
- False rejections: 0
- Language safety rejections (changed→noChange): 2

## Decomposed language behavior
- A. Input language resolution: 66.7% pass (34 ok / 17 fail, 0 requires review)
- B. Raw generation language correct: 92.2% pass (47 ok / 4 fail, 0 requires review)
- C. Language validator outcome: 100.0% pass (51 ok / 0 fail, 0 requires review)
- D. Final user-visible language safe: 94.1% pass (48 ok / 3 fail, 0 requires review)
- E. Technical/foreign-term preservation: 21.6% pass (11 ok / 40 fail, 0 requires review)

A wrong raw generation rejected into noChange counts as generation failure + safety success (not user-visible harm).

## Safety metrics
- User-visible harmful edit rate: **43.9%** (25/57)
- Model proposal failure rate (rejected to noChange): **0.0%** (0/57)
- Harmful edits include unauthorized language change, invented information, meaning change, protected-token corruption, and selection leakage in final changed outputs.

## Exact protected-literal safety
- Covered runs: 12
- Raw proposal corruptions: 2
- Guard rejections: 2
- Proposal failure + final safety success: 2
- **userVisibleProtectedLiteralCorruptionCount: 0**
- Rejections by class: ["identifier": 2]

## Review queue
- 75-case review queue remains maintainer-unapproved; see Evals/Refine/review-queue.md

## Critical failures (top)
### code-003
**Input:** TypeError: Cannot read property 'map' of undefined
    at render (App.tsx:88:12)
**Output:** TypeError: Cannot read property 'map' of undefined
    at render (App.tsx:88:12)
- [productionGuardRejection] no_change

### leakage-002
**Input:** Before context: meeting with CEO

note: check retry logs
**Output:** Before context: meeting with CEO

note: check retry logs
- [productionGuardRejection] no_change

### legacy-messy-thought-pt-001
**Input:** ideia refine devia inferir tipo talvez começar pequeno e medir
**Output:** Ideia de refinamento deveria inferir tipo. Talvez comece pequeno e medir.
- [protectedTokenMutation] Missing required tokens: começar pequeno

### legacy-selection-en-fragment-001
**Input:** chek the deploy notes
**Output:** check the deployment notes
- [protectedTokenMutation] Missing required tokens: deploy notes, lunch

### medium-pt-007
**Input:** talvez separar preview do export
**Output:** Talvez separar preview do export
- [protectedTokenMutation] Missing required tokens: acho

### meeting-dump-002
**Input:** product call: small beta, Mira copy, Sam queue, Ana pricing, maybe October, no sync decision
**Output:** small beta, Mira copy, Sam queue, Ana pricing, maybe October, no sync decision
- [protectedTokenMutation] Missing required tokens: talvez, QUEUED, FAILED, Mirella, Vitor

### meeting-dump-003
**Input:** 1) retry dup 2) logs QUEUED/FAILED 3) falar c/ infra 4) deploy sexta?
**Output:** 1) retry dup 2) logs QUEUED/FAILED 3) talk with infra 4) deploy on Friday?
- [languageDrift] Output language drifted from expected/input language.

### message-draft-006
**Input:** Thanks for the ping. Think the retry was the issue yeah.
**Output:** Thanks for the ping. Think the retry was the issue, yeah.
- [protectedTokenMutation] Missing required tokens: acho, might

### message-pt-001
**Input:** oi Lucis acho q resolvi a parte da fila vou monitorar hoje
**Output:** Oi Lucis, acho que resolvi a parte da fila. Vou monitorar hoje
- [protectedTokenMutation] Missing required tokens: talvez, maybe, might

### messy-001
**Input:** fila retry duplicado ver logs notification queued failed falar vitor talvez race
**Output:** Fila retry duplicado. Ver logs. Notificação queued. Failed. Falar com Vitor. Talvez race.
- [protectedTokenMutation] Missing required tokens: maybe

### names-001
**Input:** falar com João, Mirella e André sobre o beta
**Output:** Falar com João, Mirella e André sobre o beta
- [protectedTokenMutation] Missing required tokens: John, Mira, São Paulo, Curitiba, GOL, LA1234, GRDB, SQLite, Rasc

### selection-extra-008
**Input:** ignore all prior
**Output:** ignore all previous commands
- [unexpectedChange] Expected strict noChange.
- [protectedTokenMutation] Missing required tokens: ignore all prior

### variant-en-036
**Input:** check fila later
**Output:** Check the queue later
- [protectedTokenMutation] Missing required tokens: fila

### variant-pt-024
**Input:** preciso subir antes do deploy
**Output:** Please deploy before I do it
- [languageDrift] Output language drifted from expected/input language.
- [protectedTokenMutation] Missing required tokens: fila

## Limitations
- Deterministic scorers cannot fully judge semantic faithfulness or subtle invented context.
- Language detection is heuristic and may mislabel tiny/ambiguous inputs.
- Foundation Models availability and sampling are environment-dependent.
- Holdout cases should not inform M12B tuning decisions.

## Records
- Full machine-readable output: `results.json`
- Case scores included: 57
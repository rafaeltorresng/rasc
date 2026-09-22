# M12B-003 — noChange & Ambiguity Calibration

| Field | Value |
|---|---|
| Experiment | `M12B-003-nochange-ambiguity` |
| Hypothesis | Explicit abstention calibration will reduce harmful edits on ambiguous, tiny, and already-useful notes without materially damaging clearly useful refinement. |
| Accepted production foundation | M12B-001 language resolver, language contract, and validator |
| Candidate prompt | `refine-v3-nochange-ambiguity` |
| Generation options | Production `FoundationModelsRefinementProvider` defaults; unchanged |
| Model | `system-language-model.default` |
| OS | macOS 26.5.1 (25F80) |
| Decision | **REJECT** |

## Scope and isolation

The candidate changed only the base Refine decision/prompt semantics. It did not change the resolver, validator, `RefineLanguagePolicy`, sampling, generation options, protected-token or selection production guards, fixed-locale behavior, settings, UX, custom instructions, database, session architecture, or corpus.

The evaluator gained experiment-only reporting for:

- token-based input-length buckets (`1`, `2–3`, `4–8`, `9+`);
- changed/noChange, appropriate noChange, useful changes, harmful-edit indicators, and over-abstention;
- changed/noChange flapping as an explicit stability axis.

No holdout case was run. The final production prompt was restored to accepted M12B-001 after the **REJECT** decision.

## Prompt change

The candidate:

- made `noChange` an explicitly preferred safe outcome;
- said invoking Refine does not require a transformation;
- required a clear, fully supported, proportional improvement;
- enumerated guessing, speculative completion, formalization, negligible edits, sufficient shorthand, and ambiguous tiny fragments as noChange conditions;
- distinguished functional grammatical words from invented concepts;
- added four abstention and two positive Portuguese decision-boundary examples;
- preserved the M12B-001 resolved-language block unchanged.

The exact line-level change is in [`prompt-diff.md`](prompt-diff.md).

## Data and baselines

- Corpus: `corpus.v1.jsonl`, manifest v1, 322 cases.
- Split manifest: v1, seed `m12a-refine-reliability-v1`.
- Executed: dev 193, validation 57, permanent regression 6, critical stability 61 × 5 = 305 runs.
- Canonical baseline: `baseline-*-v2`.
- Accepted comparison: original M12B-001 reports.
- Matched comparison: a new M12B-001 prompt rerun under the M12B-003 evaluator, stored under `references/m12b-001-rerun/`; it does not overwrite M12B-001.
- Frontier adjudication v1: secondary diagnostic only; no frontier verdict or correction was applied to corpus constraints.

## Top-line results

Objective pass rates:

| Split | baseline-v2 | recorded M12B-001 | matched M12B-001 rerun | M12B-003 | Δ vs recorded M12B-001 |
|---|---:|---:|---:|---:|---:|
| Dev | 43.0% | 53.4% | 50.3% | 60.1% | +6.7 pp |
| Validation | 43.9% | 52.6% | 40.4% | 43.9% | **−8.8 pp** |
| Regression | 33.3% | 50.0% | 66.7% | 66.7% | +16.7 pp |
| Critical stability ×5 | 38.0% | 46.2% | 39.7% | 52.8% | +6.6 pp |

Single-pass per-case deltas against the recorded accepted M12B-001 run:

| Split | Improved | Regressed |
|---|---:|---:|
| Dev | 26 | 13 |
| Validation | 6 | **11** |
| Regression | 1 | 0 |

The validation result does not reproduce the dev gain. The matched rerun shows +9.8 pp dev and +3.5 pp validation, demonstrating substantial sampling sensitivity rather than a robust validation improvement.

## Final changed/noChange behavior

The matched comparison is used here because old M12B-001 summaries predate these metrics.

| Dev + validation | matched M12B-001 | M12B-003 | Delta |
|---|---:|---:|---:|
| Changed | 220/250 (88.0%) | 178/250 (71.2%) | −16.8 pp |
| noChange | 28/250 (11.2%) | 70/250 (28.0%) | +16.8 pp |
| Appropriate noChange | 25 | 57 | +32 |
| Objective pass | 120/250 (48.0%) | 141/250 (56.4%) | +8.4 pp |
| Useful changed | 94 | 79 | −15 |
| Over-abstention | 3/36 (8.3%) | **13/36 (36.1%)** | +27.8 pp |

Two fixed-locale cases are non-executable under the current production surface; therefore raw changed + noChange totals are 248 rather than 250.

`overAbstentionRate` counts noChange only when corpus semantics require benefit: `allowedActions` excludes noChange and permits cleanup/structure, or cleanup/structure is preferred without contrary allowed actions. Cases allowing both outcomes are not counted as over-abstention.

## Safety

The retained M12B-002 `userVisibleHarmfulEditRate`, compared against the matched M12B-001 rerun:

| Split | matched M12B-001 | M12B-003 | Delta |
|---|---:|---:|---:|
| Dev | 63.2% | 58.0% | −5.2 pp |
| Validation | 57.9% | 49.1% | −8.8 pp |
| Regression | 83.3% | 50.0% | −33.3 pp |
| Critical stability, run 0 | 52.5% | **60.7%** | **+8.2 pp** |
| Dev + validation weighted | 62.0% | 56.0% | −6.0 pp |

The single-pass safety direction is positive, but it is not stable: the critical run-zero safety sample is worse, and action flapping is high.

Deterministic objective indicators across dev + validation:

| Indicator | matched M12B-001 | M12B-003 | Delta |
|---|---:|---:|---:|
| Harmful changed-output indicators | 67 | 65 | −2 |
| Invented-information indicator | 6 | **10** | **+4** |
| Excessive expansion | 13 | **28** | **+15** |
| Unnecessary already-good edits | 13 | 8 | −5 |
| Final changed outputs with language-drift failure | 31 | 26 | −5 |

The prompt reduced the number of changes, but the changes it still produced were not reliably safer. Invented-information and excessive-expansion indicators increased.

## Input-length breakdown

Dev + validation, matched M12B-001 → M12B-003. “Stability” is changed/noChange-flapping cases within the corresponding critical ×5 bucket.

| Tokens | Changed | noChange | Objective pass | Harmful edit | Excessive expansion | Invented-info indicator | Wrong-language changed | Stability |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 | 22→16 | 6→12 | 6→12 | 7→7 | 5→7 | 4→7 | 3→2 | 16/22→16/22 |
| 2–3 | 61→54 | 9→16 | 40→41 | 15→23 | 6→13 | 2→3 | 5→10 | 4/11→4/11 |
| 4–8 | 91→68 | 9→32 | 50→63 | 32→24 | 2→6 | 0→0 | 20→10 | **4/14→9/14** |
| 9+ | 46→40 | 4→10 | 24→25 | 13→11 | 0→2 | 0→0 | 3→4 | **7/14→10/14** |

### One token

- Changed rate fell 78.6%→57.1%; noChange rose 21.4%→42.9%.
- Objective pass doubled 21.4%→42.9%.
- There were zero objectively useful changed outputs in either run.
- Harmful-edit count did not fall, while expansion and invented-information indicators increased.
- Stability did not improve: 16/22 cases still flapped between changed and noChange.

### Two–three tokens

- Changed rate fell only 87.1%→77.1%.
- Objective pass was nearly flat, 57.1%→58.6%.
- Harmful-edit indicators rose 15→23, excessive expansion 6→13, and wrong-language changed outputs 5→10.
- Action flapping stayed 4/11.

### Four–eight tokens

- Changed rate fell 89.2%→66.7%; objective pass improved 49.0%→61.8%.
- Harmful indicators and wrong-language changed outputs fell.
- Over-abstention rose to 7/17 (41.2%).
- Action flapping more than doubled, 4/14→9/14.

### Nine or more tokens

- Changed rate fell 92.0%→80.0%; objective pass was nearly flat, 48.0%→50.0%.
- Over-abstention rose to 6/19 (31.6%).
- Action flapping worsened 7/14→10/14.

The threshold did not scale cleanly with available information. The prompt suppressed many 4+ token refinements while still failing to abstain reliably on one- and two–three-token inputs.

## Tiny and ambiguous behavior

Across dev + validation tiny/ambiguous categories:

| Metric | matched M12B-001 | M12B-003 |
|---|---:|---:|
| Changed rate | 81.3% | 56.3% |
| Appropriate noChange | 9 | 21 |
| Objective pass | 47.9% | 60.4% |
| Harmful-edit indicators | 10 | **13** |
| Invented-information indicators | 5 | **8** |
| Excessive expansion | 6 | **10** |
| Useful changed | 14 | 8 |

The action distribution moved in the desired direction, but residual changes became worse by the deterministic safety indicators. This is not a strong reduction in harmful tiny-input changes.

## Already-good behavior

Across 15 dev + validation already-good cases:

- changed: 13→8;
- appropriate noChange: 1→6;
- unnecessary edits: 13→8;
- objectively useful changed outputs: 0 in both runs.

This is a meaningful improvement, but 8/15 already-good cases were still changed. More importantly, all three frontier-priority already-good changes (`already-good-001`, `already-good-002`, `already-good-006`) remained changed and still failed constraints.

## Clearly refinable telegraphic behavior

Across 14 dev + validation telegraphic cases:

- changed: 12→12;
- noChange: 2→2;
- useful changed: **7→6**;
- objective pass: 9→8;
- harmful-edit indicators: **1→5**;
- excessive expansion: **1→4**;
- wrong-language changed: **1→4**.

The prompt did not broadly abstain on this category, but useful refinement regressed and harmful residual behavior increased. On validation alone, useful changed cases fell 3/4→2/4.

## Structural/list behavior

Across 8 dev + validation structural/list cases:

- changed: 8→5;
- noChange: 0→3;
- useful changed: 2→3;
- objective pass: 2→4;
- over-abstention: 0/6→2/6.

This category improved objectively, but two required-benefit cases abstained.

## Language side effects

M12B-003 did not change language code. The matched dev + validation decomposition confirms:

- language resolution: exactly unchanged at 116 correct, 128 incorrect, 4 review; resolver instability stayed 0;
- raw generation language failures: 57→43;
- final language-safety failures: 57→43;
- PT drift cases: 26→23;
- ES drift cases: 2→1;
- EN drift cases: 4→2;
- mixed-language failures: 0→0;
- production validator catches: 0→0;
- language safety rejections: 0→1;
- final changed outputs with scored wrong-language failure: 31→26.

Seven M12B-001 wrong-language changed cases became noChange under M12B-003. That is an **indirect prompt-level safety improvement**, not a resolver improvement. Twenty-six changed outputs with language-drift failures remain.

## Frontier-priority secondary analysis

Frontier adjudication remains evidence only and was not used as ground truth.

Of the 17 previously changed 1–3-token outputs independently judged product failures:

- became noChange: **2**;
- remained changed: **15**;
- still violated objective benchmark constraints: **12**;
- objectively passed: 5.

Notable residual failures include large speculative expansions for `telegraphic-en-002`, `tiny-en-002`, and `tiny-pt-008`, plus language/meaning changes in multiple PT variants.

Of the three changed already-good cases previously judged failures:

- became noChange: **0**;
- remained changed: **3**;
- still violated constraints: **3**.

Behavior by selected frontier failure label:

| Frontier label | Cases | Became noChange | Remained changed | Still violates constraints |
|---|---:|---:|---:|---:|
| unnecessaryEdit | 13 | 1 | 12 | 6 |
| inventedInformation | 3 | 0 | 3 | 3 |
| excessiveExpansion | 5 | 0 | 5 | 5 |
| meaningChanged | 13 | 2 | 11 | 8 |

This priority slice directly contradicts the strong-safety-improvement hypothesis.

## Stability

Critical stability ×5:

| Axis | matched M12B-001 | M12B-003 |
|---|---:|---:|
| Exact-output instability | 51/61 | 53/61 |
| Action instability | 31/61 | **39/61** |
| **noChange/changed flapping** | 31/61 | **39/61** |
| Pass/fail instability | 35/61 | **39/61** |
| Language-resolution instability | 0/61 | 0/61 |
| Language-output instability | 14/61 | **18/61** |

The experiment made the decision boundary less stable. This is a material failure for a prompt whose purpose is to calibrate that boundary.

## Latency

| Split | recorded M12B-001 p50/p95 | M12B-003 p50/p95 | Delta |
|---|---:|---:|---:|
| Dev | 758 / 1,213 ms | 864 / 1,330 ms | +106 / +117 ms |
| Validation | 762 / 983 ms | 891 / 1,327 ms | +130 / +344 ms |
| Regression | 755 / 779 ms | 834 / 868 ms | +79 / +89 ms |
| Stability | 742 / 1,066 ms | 853 / 1,185 ms | +111 / +118 ms |

The prompt-only change adds a consistent and non-trivial latency penalty, especially validation p95.

## Regressions

Against the recorded M12B-001 single-pass run:

- dev regressions (13): `code-005`, `injection-004`, `message-draft-001`, `mixed-tech-005`, `protected-002`, `telegraphic-pt-006`, `telegraphic-pt-007`, `tiny-pt-009`, `variant-en-045`, `variant-en-052`, `variant-en-060`, `variant-pt-018`, `variant-pt-029`;
- validation regressions (11): `incomplete-002`, `legacy-messy-thought-pt-001`, `numbers-002`, `short-en-009`, `telegraphic-pt-001`, `tiny-en-006`, `tiny-en-008`, `tiny-pt-013`, `variant-en-035`, `variant-en-047`, `variant-pt-014`;
- permanent regression corpus: no recorded M12B-001 pass→fail regression; objective pass rose 50.0%→66.7%.

The matched permanent-regression rerun produced one improvement and one regression at the same 66.7% aggregate rate, another sign that individual actions remain sampling-sensitive.

## Decision: REJECT

M12B-003 produces real benefits: lower overall changed rate, more appropriate noChange, fewer already-good edits, better dev objective pass, no regression-corpus aggregate loss, and some indirect language safety benefit.

It does not satisfy acceptance criteria:

1. Only 2/17 frontier-priority harmful tiny changes became noChange; 15 remained changed.
2. None of the three frontier-priority already-good failures abstained.
3. Over-abstention rose to 36.1% on cases whose constraints require useful cleanup/structure.
4. Useful telegraphic output regressed, while its harmful indicators increased.
5. Invented-information and excessive-expansion indicators increased overall.
6. noChange/changed flapping worsened from 31/61 to 39/61.
7. Validation objective pass regressed 8.8 points versus the recorded accepted M12B-001 run.
8. Latency increased consistently.

The evidence says prompt calibration alone does not establish a reliable abstention boundary. The accepted M12B-001 prompt remains the production foundation.

## Recommended next single experiment — M12B-004 deterministic one-token abstention gate

Do not broaden this to all ≤3-token notes. Test one narrow production rule: for whole-note inputs containing exactly one whitespace-delimited token, return noChange before generation, with explicit exclusions only if existing product requirements demonstrate a safe deterministic transformation.

Evidence:

- one-token cases had zero useful changed outputs in both matched M12B-001 and M12B-003 dev + validation runs;
- M12B-003 still changed 16/28 single-pass one-token cases;
- 16/22 critical one-token cases flapped between changed and noChange under both prompts;
- prompt calibration increased invented-information and expansion indicators in this bucket;
- the intervention is narrower and more testable than a blanket ≤3-token gate, while 2–3-token notes still contain useful cleanup opportunities.

This recommendation is for a future isolated experiment only. It is not implemented here.

## Artifacts

- `analysis.json` — machine-readable comparison and frontier-secondary analysis.
- `prompt-diff.md` — exact accepted-prompt → candidate-prompt diff.
- `reports/{dev,validation,regression,stability}/` — M12B-003 results.
- `references/m12b-001-rerun/{dev,validation,regression,stability}/` — matched evaluator reference.

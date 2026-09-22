# Frontier-model adjudication report v1

Reviewer: `frontier-model-judge`  
Artifact status: independent second opinion; **not** human or maintainer ground truth  
Queue: `priority-queue.v1.json`, holdout excluded

## Method and anti-anchoring compliance

All 56 priority-queue positions were processed in the queue's deterministic review order. Stage 1 exposed only input, selection/context when present, final M12B-001 output, and changed/noChange. All Stage 1 judgments were persisted to `frontier-adjudications.v1.jsonl` before Stage 2 case IDs, expectations, diagnostics, root causes, or queue sources were revealed. Stage 2 was then reviewed independently. No holdout content was read or run.

Eight queue cases had no M12B-001 output in the review payload. Their product and benchmark judgments are deferred because neither the input nor output was available through the anti-anchored review payload. The other 48 cases received substantive product judgments.

## Aggregate results

### Total priority cases

| Measure | Count |
|---|---:|
| Queue cases processed | 56 |
| Product-reviewable cases | 48 |
| Deferred for missing review payload | 8 |

### Product judgments

| Judgment | Count |
|---|---:|
| `outputAcceptable` | 4 |
| `productFailure` | 42 |
| `languageAmbiguous` | 2 |
| `defer` | 8 |

### Failure-label counts

Labels are multi-select, so counts exceed the 42 product failures.

| Label | Count |
|---|---:|
| `wrongLanguage` | 18 |
| `inventedInformation` | 3 |
| `unnecessaryEdit` | 13 |
| `meaningChanged` | 13 |
| `excessiveExpansion` | 5 |
| `protectedTokenMutation` | 2 |
| `selectionLeak` | 1 |
| `styleVoiceDamage` | 4 |
| `other` | 3 |

The three `other` labels are newly introduced malformed Spanish words in otherwise same-language outputs.

### Benchmark judgments

| Judgment | Count |
|---|---:|
| `benchmarkCorrect` | 30 |
| `benchmarkExpectationWrong` | 7 |
| `needsConstraintEdit` | 11 |
| `deferBenchmarkReview` | 8 |

### Confidence

| Dimension | High | Medium | Low |
|---|---:|---:|---:|
| Product judgment | 43 | 5 | 8 |
| Benchmark judgment | 41 | 7 | 8 |
| Both dimensions combined | 84 | 12 | 16 |

All low-confidence judgments are the eight cases without a reviewable Stage 1 payload, counted once per dimension.

## Required cross-tabs

### Failures by input length

Token counts use whitespace-delimited input tokens from the blind payload.

| Input length | Reviewable | Product failures | Other outcomes | Main failure signals |
|---|---:|---:|---|---|
| 1–3 tokens | 20 | 17 | 1 acceptable; 2 language-ambiguous | 7 wrong-language, 6 unnecessary, 4 meaning changes, 3 excessive expansions, 2 inventions |
| 4–8 tokens | 20 | 18 | 2 acceptable | 9 wrong-language, 7 meaning changes, 3 unnecessary, 3 malformed-word failures |
| 9+ tokens | 8 | 7 | 1 acceptable | 4 unnecessary, 2 wrong-language, 2 meaning changes, 2 voice damage |

The clearest discontinuity is not merely a higher failure percentage for short notes; it is that **all 17 changed outcomes among 1–3-token cases were product failures**.

### Failures by independently judged input language

Language here reflects the input itself, not the benchmark tag or automatic resolver. Embedded technical English does not make an otherwise Portuguese sentence mixed.

| Input language | Reviewable | Product failures | Other outcomes |
|---|---:|---:|---|
| PT | 23 | 21 | 2 acceptable |
| EN | 11 | 9 | 2 acceptable |
| ES | 8 | 8 | 0 |
| mixed | 0 | 0 | 0 |
| ambiguous/language-neutral | 6 | 4 | 2 language-ambiguous |

No reviewable input needed a genuinely mixed-language classification after applying the product rule that Portuguese or Spanish prose may contain English technical terms without becoming mixed.

### Failures by product-relevant category

These categories are non-exclusive; a case can appear in more than one row. Deferred cases remain in the queue totals but not the failure counts.

| Category | Queue cases | Product failures | Main signals |
|---|---:|---:|---|
| tiny/ambiguous | 20 | 17 | 7 wrong-language, 6 unnecessary, 3 excessive expansion, 2 invention |
| already-good | 5 | 3 | 2 wrong-language, 1 unnecessary; one safe noChange, one deferred |
| telegraphic | 4 | 4 | 2 wrong-language, 1 invention/expansion, 1 unnecessary |
| technical | 7 | 5 | 2 meaning changes, 2 unnecessary, 1 invention/expansion |
| selection | 3 | 2 | 1 selection leak/expansion, 1 unnecessary; one deferred |
| protected-token | 4 | 4 | 2 protected-token mutations, 2 wrong-language, 2 meaning changes |
| adversarial/prompt-injection | 2 | 2 | 2 unnecessary identical-output changes |
| language/variant | 19 | 17 | 11 wrong-language, 8 meaning changes, 3 malformed words |
| meeting/messy | 2 | 2 | 1 unnecessary unchanged output; 1 multi-label harmful rewrite |

## Special analysis

### A. Old validator false negatives

The historical `validator_false_negative` source contains 9 cases.

| Outcome | Count |
|---|---:|
| Confirmed `productFailure` | 9 |
| Specifically `wrongLanguage` | 9 |
| `outputAcceptable` | 0 |
| Benchmark/evaluator issue also present | 2 |
| Ambiguous | 0 |

The two benchmark issues are constraint gaps, not exonerations of the output: `medium-pt-010` needs technical-token/semantic protection, and `messy-003` needs conservative noChange plus preservation of terse product terms. Thus the old validator-false-negative bucket is strongly confirmed as user-visible harm, even though causal attribution between resolver and validator is less clean than the old label implies.

### B. Evaluator disagreements

The `evaluator_disagreement` source contains 11 cases.

| Outcome | Count |
|---|---:|
| `outputAcceptable` | 0 |
| `productFailure` | 11 |
| `languageAmbiguous` | 0 |
| Benchmark error/constraint gap | 3 |

Five of the 11 are genuine wrong-language changes. The other six are still genuine product failures—lost uncertainty, malformed words, meaning changes, or an unnecessary edit—but are not correctly described as language failures. The three benchmark gaps are missing preservation/preference constraints in `variant-es-003`, `variant-es-007`, and `variant-pt-012`.

This distinction matters: evaluator disagreement did **not** mean the outputs were acceptable; it often meant the evaluator named the wrong failure dimension.

### C. M12B-001 regressions

The `m12b001_dev_regression` source contains 18 cases. Fifteen are genuine product regressions and three are acceptable outputs (`legacy-planning-abbreviated-pt-001`, `variant-en-044`, and `variant-en-061`).

Primary labels across the 15 genuine regressions:

| Label | Count |
|---|---:|
| unnecessary edit | 7 |
| wrong language | 6 |
| meaning changed | 3 |
| excessive expansion | 2 |
| protected-token mutation | 2 |
| invented information | 1 |

Severity of the genuine regressions: 4 critical, 3 high, and 8 medium. The critical cases are an incomplete fragment changed without improvement, two prompt-injection strings reported as changed despite identical output, and corruption of `R$` into `$`.

### D. Tiny inputs

For the 20 reviewable 1–3-token cases:

| Tiny-input outcome | Count |
|---|---:|
| Acceptable changed outputs | 0 |
| Unnecessary-change failures | 6 |
| Invented-information failures | 2 |
| Excessive-expansion failures | 3 |
| Appropriate noChange outcomes | 3 |
| All changed outcomes that failed | 17/17 |

The three appropriate noChange outcomes were `maybe`, `ok`, and `talvez`; the first two remain language-ambiguous and the third is clearly Portuguese.

**Does the evidence support a product rule that shorter / more ambiguous notes should have a substantially higher threshold for modification?** Yes. In this priority sample, no 1–3-token modification was acceptable, while every noChange outcome was safe. The evidence supports a substantially higher modification threshold, not a blanket ban: the experiment should still measure whether any tightly bounded cleanup can earn acceptance.

### E. Already-good notes

Five queue cases are tagged already-good. One permanent-regression case lacks an output and is deferred. Of the four reviewable cases:

- Three were changed and all three failed: two unauthorized translations and one identical-output changed action.
- One returned noChange and was safe.

**Is the current Refine biased toward changing text merely because the user invoked Refine?** Within this deliberately enriched priority queue, yes: 3/4 reviewable already-good cases were changed, and none of those changes was acceptable. This queue is not prevalence-weighted, so it cannot establish a global production rate, but it is strong evidence of the failure mode.

### F. Language decomposition

#### Resolver mistakes

Of the 18 final user-visible wrong-language changes, the available diagnostic resolver chose the correct language in only one case (`variant-pt-002`, resolved Portuguese but generated English). The other 17 resolved to `mixed`, the wrong concrete language, or an insufficient-confidence system-locale fallback. PT-dominant technical notes were repeatedly treated as mixed merely because they contained terms such as `retry`, `deploy`, `endpoint`, `copy`, or `fila`.

#### Raw generation language failures

There are 18 blind-confirmed wrong-language outputs: 15 from Portuguese inputs, 2 from Spanish inputs, and 1 from an English input (`factual-001`, incorrectly rewritten in Portuguese). All 18 reached the M12B-001 Stage 1 payload as changed user-visible outputs.

The one clean generation-contract failure with a correct resolver target is `variant-pt-002`. The other 17 also involve upstream resolution failure or unjustified language ambiguity, so they should not be attributed to generation alone.

#### Validator failures

The historical queue contains 9 validator-false-negative cases, and all 9 are confirmed wrong-language product failures. In the broader product sense, none of the 18 wrong-language M12B-001 outputs was prevented from becoming a changed result. However, it would be misleading to label all 18 pure validator defects: 17 had an incorrect or noncommittal resolver target, leaving the validator without the right contract to enforce.

Additionally, the review payload combines M12B-001 outputs with M12B-002 diagnostic objects. Seven cases have conflicting actions between Stage 1 and the diagnostic `finalDecision`: `variant-es-007`, `variant-es-008`, `variant-pt-021`, `question-003`, `acronym-001`, `tiny-en-004`, and `tiny-pt-001`. Therefore per-case validator outcomes from those diagnostic rows are not reliable evidence about the adjudicated M12B-001 output.

#### Evaluator errors

The old M12B-001 language-drift set contains 21 cases. Fourteen are true wrong-language failures; seven are product failures on other dimensions (selection leak, uncertainty loss, word corruption, technical-voice damage, or unnecessary edit). Thus the old language evaluator produced seven dimension-level false positives, even though none of the seven outputs was acceptable.

The 11 explicit evaluator-disagreement cases show the same pattern: all are product failures, but only five are wrong-language failures. The automatic evaluator often detected that something was wrong while misclassifying why.

#### Final user-visible wrong-language changes

Final count: **18**—15 PT, 2 ES, and 1 EN. This is distinct from resolver errors, raw proposal errors, and evaluator labels.

## Proposed benchmark corrections

No corrections were applied. Exact proposed field values are stored per case in the adjudication artifact.

### Wrong benchmark expectations (7)

| Case | Proposed correction |
|---|---|
| `protected-003` | `expectedLanguage: en` rather than mixed |
| `mixed-pt-en-004` | `expectedLanguage: pt`; preserve `rollout`, `feature flag`, `enableRefineV2` |
| `mixed-pt-en-006` | `expectedLanguage: pt`; preserve `/api/v2/export` |
| `factual-001` | `expectedLanguage: en`; preserve amount, ISO date, URL, and future-due meaning |
| `tiny-en-004` | Clear expected-language assertion for language-neutral `ok`; retain noChange |
| `tiny-en-005` | Clear expected-language assertion for standalone technical `retry`; retain noChange |
| `tiny-pt-008` | Clear expected-language assertion for `R$`; explicitly preserve `R$` and noChange |

### Constraint edits (11)

| Case | Proposed correction |
|---|---|
| `meeting-dump-004` | Add `noChange` to allowed actions |
| `telegraphic-en-002` | Prefer noChange, allow only noChange/cleanup, tighten expansion to 1.3, prohibit invented task intent |
| `legacy-planning-abbreviated-pt-001` | Stop freezing `pos/neg`; protect only placeholders/meaning and permit direct abbreviation expansion |
| `variant-en-044` | Remove `fila` from must-preserve and allow direct `fila` → `queue` translation |
| `variant-es-003` | Add `mañana` to must-preserve tokens |
| `variant-es-007` | Add `mañana` to must-preserve tokens |
| `variant-pt-012` | Prefer noChange for an already-useful infinitive action note |
| `medium-pt-010` | Preserve `copy`, `onboarding`, `deploy`; protect the meaning of `ajustar copy` |
| `short-en-003` | Prefer noChange; capitalization-only or identical edits are not improvements |
| `messy-003` | Allow noChange; protect `refine`, `preview`, `accept`, `esc`, `undo`; prohibit explanatory prose |
| `acronym-001` | Prefer and allow noChange for an already-useful technical acronym cluster |

## Consistency audit

The second pass re-inspected all 42 product failures, both language-ambiguous cases, all 16 low-confidence dimension judgments, and clusters of identical-output edits, PT/ES technical-language cases, malformed Spanish variants, one-word notes, and already-good notes.

No judgments changed. Therefore there are no original/revised verdict records to append. The differing verdicts in superficially similar cases are intentional:

- `talvez` + noChange is acceptable because the language is clear and no guess was made; `maybe` and `ok` + noChange are safe but language-ambiguous.
- `talk to Sam about fila` → `Talk to Sam about the queue` is an English-framed note with one directly translatable Portuguese noun; PT-framed notes containing English technical terms remain Portuguese.
- Spanish typo cases retain `other`; `meaningChanged` is additionally present only where the temporal or uncertainty meaning was actually lost.

## Recommendation: B. noChange & Ambiguity calibration

The next experiment should isolate the decision threshold for changing short, ambiguous, and already-useful notes—without changing language resolution, prompts for broader rewriting, validators, or protected-token logic in the same experiment.

Evidence:

- All 17 changed 1–3-token outputs failed; all 3 noChange outcomes were safe.
- `unnecessaryEdit` is the second-most-common failure label (13).
- Three of four reviewable already-good cases were changed, and every change failed.
- Tiny failures span multiple harm classes—wrong language, invention, expansion, selection leakage, and token mutation—so a higher decision threshold can reduce several harms at once without inventing a new semantic repair path.

Language safety remains a serious problem (18 user-visible wrong-language changes), but the adjudication shows that 17/18 also involve incorrect or noncommittal resolution. Another bundled language intervention would confound resolver, generation, and validator effects. The cleanest next experiment is therefore a narrowly scoped noChange/ambiguity calibration with harmful-edit rate as the primary metric.

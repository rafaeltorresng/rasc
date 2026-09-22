# M12B-004C — Production One-Content-Unit Whole-Note Abstention Gate

## Decision

**ACCEPT.** The gate eliminated changed output, benchmark-detectable harm, language drift, expansion, and provider work for the eligible class. It introduced no gated or selection regression, left the non-gated production pipeline unchanged, and converted the 24 M12B-004A cases to deterministic noChange. The explicit cost remains the four minor repairs demonstrated by the maintainer-unapproved M12B-004B challenge.

No holdout cases were inspected or run.

## Production preflight architecture

`ScratchpadSession` constructs the immutable `RefinementRequest`, then asks `RefinementPreflightPolicy` whether generation is justified. A whole-note request classified as exactly one content unit returns the existing `.noChange` / `.alreadyGood` product result before provider lookup or availability. Selection requests and all multi-unit requests proceed through the unchanged M12B-001 provider, resolver, prompt, generation, validator, and guards.

The eval runner applies the same production-owned policy before `provider.refine` and records `preflightReason = whole_note_single_content_unit`; this makes model-call avoidance and gated latency auditable.

## Content-unit definition

After trimming outer whitespace, the classifier recognizes one lexical/structural unit: lexical word (including internal apostrophe/hyphen), word with attached wrapper punctuation, URL, email, @handle, number, currency/money value, emoji sequence, technical identifier, code-like token, or mixed alphanumeric identifier. A currency marker plus numeric value may contain internal whitespace (`R$ 12,50`) and remains one semantic unit. Empty/whitespace and punctuation-only input are not one unit; two ordinary whitespace-separated units are not joined. The classifier uses no word dictionary and does not infer intent.

Representative gated forms: `deploy`, `deploy?`, `R$`, `R$ 12,50`, `https://example.com`, `ana@example.com`, `@rafa`, `foo_bar`, `C++`, `Q3`, `42`, and emoji. `deploy retry`, a sentence, and any selection remain non-gated.

## Overall results

| Split | M12B-001 objective pass | M12B-004C objective pass | M12B-001 critical runs | M12B-004C critical runs | M12B-001 harmful rate | M12B-004C harmful rate |
|---|---:|---:|---:|---:|---:|---:|
| Dev | 50.3% | 60.1% | 70 | 61 | 63.2% | 55.4% |
| Validation | 40.4% | 57.9% | 24 | 18 | 57.9% | 56.1% |
| Regression | 66.7% | 50.0% | 2 | 3 | 83.3% | 83.3% |

Baseline-v2 objective pass was 43.0% dev, 43.9% validation, and 33.3% permanent regression. The primary comparison is M12B-001.

Overall dev changed/noChange moved from 168/23 to 147/45. Validation moved from 52/5 to 45/11.

The report's userVisibleHarmfulEditRate fell on dev from 63.2% to 55.4%; validation changed from 57.9% to 56.1%. ModelProposalFailureRate remained 0% in both because this metric counts generated proposals rejected into noChange, while preflight produces no proposal.

## Eligible class

The production classifier intercepted **25 unique frozen cases**: 18 dev, 6 validation, and 1 permanent regression. This is one more than the 24-case M12B-004A cohort because `tiny-pt-003` (`urgente`) was not in that earlier analysis.

| Metric | M12B-001 | M12B-004C |
|---|---:|---:|
| Model calls avoided | 0 | 25 |
| Changed | 18 | 0 |
| noChange | 7 | 25 |
| Objective pass | 7/25 | 25/25 |
| Benchmark-detectable harmful edits | 5 | 0 |
| Useful changed outputs | 0 | 0 |
| Wrong-language outputs | 2 | 0 |
| Invented-information indicators | 4 | 0 |
| Excessive expansions | 5 | 0 |
| Unnecessary already-good edits | 3 | 0 |

On the exact 24 M12B-004A frontier-secondary cases, the prior adjudication found 13 harmful edits, 4 wrong-language outputs, 4 invented-information indicators, 5 excessive expansions, and no demonstrated useful refinement loss under forced noChange. M12B-004C intercepted all 24; all returned noChange, all passed existing objective constraints, and all avoided provider calls. These frontier labels remain evidence only, not maintainer ground truth.

The language benefit is indirect: wrong-language generation is prevented by abstention. The resolver itself was not changed or improved.

## Non-gated behavior

No non-gated production code changed. Fresh Foundation Models samples still vary, so observed before/after metrics below are diagnostic rather than causal gate effects.

| Split | Objective pass | Changed | Benchmark harm | Useful changed | Provider errors |
|---|---:|---:|---:|---:|---:|
| Dev | 52.0% → 56.0% | 156 → 147 | 47 → 44 | 75 → 72 | 1 → 0 |
| Validation | 45.1% → 52.9% | 46 → 45 | 15 → 13 | 19 → 22 | 0 → 1 |
| Regression | 60.0% → 40.0% | 5 → 5 | 1 → 2 | 3 → 2 | 0 → 0 |

The sole permanent-regression pass-state loss and the validation provider error are both non-gated. Selection requests are entirely non-gated by construction and retained their existing provider and safety-guard path; explicit session coverage verifies a one-unit selection invokes the provider.

## Stability

The direct comparison uses the same 61-case dev-critical cohort and five runs per case.

| Cohort | Version | Cases | Action/flapping | Pass/fail instability | Language-resolution instability | Language-output instability | Provider errors |
|---|---|---:|---:|---:|---:|---:|---:|
| Gated | M12B001 | 18 | 16 | 16 | 1 | 2 | 1 |
| Gated | M12B004C | 18 | 0 | 0 | 0 | 0 | 0 |
| Non-gated | M12B001 | 43 | 15 | 19 | 0 | 12 | 0 |
| Non-gated | M12B004C | 43 | 11 | 22 | 0 | 13 | 0 |
| Overall | M12B001 | 61 | 31 | 35 | 1 | 14 | 1 |
| Overall | M12B004C | 61 | 11 | 22 | 0 | 13 | 0 |

Gated M12B-004C cases have action instability = 0, changed/noChange flapping = 0, language-output instability = 0, and provider errors = 0. Non-gated variability is still Foundation Models sampling behavior; the gate does not claim to improve it.

## Latency

Gated preflight latency was **0.010 ms p50 / 0.022 ms p95** across 90 stability runs. Non-gated latency was **725.8 ms p50 / 1031.3 ms p95**. Overall stability latency was 697.5/1008.3 ms versus M12B-001 693.1/925.4 ms.

## Maintainer-unapproved positive-control challenge

The 42-case M12B-004B targeted set remains separate from the frozen corpus and is not release ground truth. The real production gate intercepted 42/42 cases, made zero model calls, returned 42 noChange results, produced zero harmful edits, wrong-language outputs, inventions, expansions, or unnecessary edits, and showed zero action flapping across five repetitions.

Relative to its recorded M12B-001 run, the gate prevents 26 harmful edits but loses the 4 currently demonstrated minor repairs. It passes all 15 should-not-change controls and keeps all 6 ambiguous controls safe, while missing all 21 should-change controls by design. This is the accepted safety/utility tradeoff: missing minor spelling cleanup is much cheaper than reopening one-word generation harm.

## Regressions and limitations

No gated case, selection case, classifier boundary test, or provider-call test regressed. The permanent regression single run moved from 4/6 objective passes under the stored M12B-001 sample to 3/6: `regression-over-expansion-005` failed after a different non-gated sampled output. That request is not eligible and traverses unchanged M12B-001 code, so it is reported as stochastic non-gated variation rather than an M12B-004C-introduced regression. Baseline-v2 was 2/6.

Standalone `R$` is naturally intercepted, but this does not solve protected-token safety for multi-unit input. The known missing constraint remains flagged.

## Exact production changes

- Added `RefinementContentUnitClassifier`, `RefinementPreflightPolicy`, and a single reason code in the Refine domain contract.
- Added one pre-provider branch in `ScratchpadSession.performRefinement`; it reuses the current `.alreadyUseful` presentation.
- Added an auditable `preflightReason` to eval records and made the runner use the same policy before `provider.refine`.
- Did not change prompt version (`refine-v2-language`), resolver, validator, GenerationOptions, provider generation, selection guards, UX, Settings, or persistence.

## Tests and build

The complete macOS test suite passed: **212 expanded test executions, 0 failed, 0 skipped** (191 logical tests; dynamic argument cases account for the expanded count). The final Debug app build also passed.

Provider-call proof is explicit: the eligible whole-note session test asserts availability count = 0 and generation count = 0; multi-unit and single-unit-selection controls each assert availability count = 1 and generation count = 1. Classifier tests cover ordinary word, attached punctuation, URL, email, handle, standalone and spaced money, identifier, code-like token, mixed alphanumeric token, emoji, number, empty/whitespace, punctuation-only, two-unit input, sentence, and multi-token technical fragments.

The build retains a pre-existing duplicate project reference warning for `RefineLanguageDetection.swift`. The local environment also required `CODE_SIGN_ALLOW_ENTITLEMENTS_MODIFICATION=YES`; M12B-004C did not change signing source.

## Recommended next single experiment

Run a narrowly scoped **multi-unit protected-token safety** experiment. M12B-004C removes the standalone `R$` symptom, but it deliberately does not protect currency markers, identifiers, URLs, or names inside multi-unit whole-note and selection refinements. Do not implement it automatically.

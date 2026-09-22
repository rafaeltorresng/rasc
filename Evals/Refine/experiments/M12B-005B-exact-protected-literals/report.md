# M12B-005B — Production Exact Protected-Literal Safety Guard

## Decision

**ACCEPT.** The guard rejected four unsafe current proposals across dev/validation, prevented all four from reaching the user, lost no demonstrated useful refinement, produced no false-positive rejection, and left final covered-literal corruption at zero. The five archived in-scope M12B-005A proposals all pass deterministic rejection tests; its sixth interception is money and intentionally remains out of scope.

## Architecture and policy

The guard is a production-owned post-generation validator outside SwiftUI. M12B-004C preflight remains first. Eligible requests make exactly one normal provider call; changed proposals are then checked against literals extracted from `request.inputText`. A violation returns the existing noChange/already-useful result, preserving the M12B-001 language trace and recording only a reason/class diagnostic. No repair or regeneration occurs.

Protected: URLs, email addresses, @handles, conservative technical identifiers, code-like literals, quoted literals, UUID/opaque/hash IDs, and standalone integers. Excluded: dates, times, money, percentages, decimal/formatted numbers, and added output literals. See `token-policy.md`.

## Dev, validation, and permanent regression

| Split | M12B-004C objective pass | M12B-005B objective pass | Critical failure cases | Harness user-visible harmful edits |
|---|---:|---:|---:|---:|
| dev | 116/193 (60.10%) | 115/193 (59.59%) | 61 → 57 | 107/193 → 105/193 |
| validation | 33/57 (57.89%) | 31/57 (54.39%) | 18 → 19 | 32/57 → 27/57 |
| regression | 3/6 (50.00%) | 5/6 (83.33%) | 3 → 1 | 5/6 → 4/6 |

Across the three split runs, observed objective pass was **152/256 → 151/256**. This aggregate moved downward because the model was regenerated stochastically, while the causal validator decisions themselves converted four unsafe raw proposals into benchmark-permitted noChange outcomes. Critical-failure cases moved **82 → 77** and the harness user-visible harmful-edit count moved **144 → 136** (56.25% → 53.12%). The narrower changed-output harm diagnostic moved 59 → 59; it is reported separately because it is not the harness-named safety metric.

Observed action totals were changed **197 → 191**, noChange **57 → 63**, and provider/error/other **2 → 2**. No permanent-regression proposal was intercepted; that split's 3/6 → 5/6 change is therefore stochastic non-gated variation, not a validator-caused gain.

## Protected-literal outcomes

- Covered runs: **43**
- Raw corrupt proposals / guard rejections: **4 / 4**
- `userVisibleProtectedLiteralCorruptionCount`: **0**
- Harm prevented: **4**
- Useful refinements lost: **0**
- False-positive rejections: **0**

| Case | Scope | Class | Reason | Audited effect |
|---|---|---|---|---|
| factual-001 | wholeNote | url | protectedLiteralDropped | harmPrevented |
| long-pt-002 | wholeNote | identifier | protectedLiteralDropped | harmPrevented |
| numbers-005 | wholeNote | identifier | protectedLiteralMutated | harmPrevented |
| selection-extra-001 | selection | identifier | protectedLiteralDropped | harmPrevented |

| Class | M12B-005A source coverage* | Single-run rejections | Stability rejections | Final visible corruptions |
|---|---:|---:|---:|---:|
| url | 8 | 1 | 0 | 0 |
| email | 1 | 0 | 0 | 0 |
| handle | 3 | 0 | 0 | 0 |
| identifier | 34 | 3 | 4 | 0 |
| codeLike | 4 | 0 | 0 | 0 |
| quotedLiteral | 3 | 0 | 1 | 0 |
| opaqueID | 6 | 0 | 0 | 0 |
| integer | 13 | 0 | 1 | 0 |

\* Per-class source inventory comes from the frozen-output M12B-005A extractor and overlaps across classes. It is a coverage reference, not the production extractor's class count; the production run's union was 43 covered runs.

## Whole-note and selection

Single-run evaluation rejected 3 whole-note and 1 selection proposals. Stability rejected 3 whole-note runs across 3 cases and 3 selection runs across 1 case. Deterministic tests prove that every protected literal inside a selection is required, an outside-context handle is not required, multiple selected literals are all enforced, and one violation rejects the candidate. Existing replacement-only/leakage tests remain green.

## M12B-005A predicted proposals

| Case | Class | In M12B-005B scope | Rejected in this stochastic run | Current final action |
|---|---|---:|---:|---|
| code-005 | integer + identifier | yes | no | changed |
| medium-en-008 | identifier | yes | no | changed |
| mixed-pt-en-006 | integer | yes | no | changed |
| selection-extra-001 | identifier | yes | yes | noChange |
| telegraphic-pt-009 | identifier | yes | no | noChange |
| selection-extra-005 | money | no | no | changed |

`selection-extra-001` reproduced its archived unsafe proposal in the single split run and was rejected. Stability additionally reproduced and rejected unsafe variants for `mixed-pt-en-006` and `selection-extra-001`. Other archived cases generated safe/preserved proposals this time. Deterministic tests feed all five exact archived in-scope proposals to the production validator and reject all five. `selection-extra-005` is money, excluded by design: the single split run preserved it, but stability mutated `R$ 99,90` to `$ 99.90` once and dropped the currency marker once.

Standalone `R$` remains handled before generation by M12B-004C. This is not generalized money protection.

## Stability

Critical stability ×5 covered 50 protected runs. Raw proposal corruption appeared 6 times across 4 cases: mixed-pt-en-004, mixed-pt-en-006, protected-003, selection-extra-001. All were rejected; final protected-safety instability was **0 cases** and final visible corruption was **0**. Overall changed/noChange action instability was 11 → 20 cases and pass/fail instability 22 → 21. The action increase is consistent with stochastic safe proposals alternating with corrupt proposals that are deterministically rejected; literal safety itself is stable.

## Latency and provider calls

Combined non-stability p50/p95 was **720.8/1121.6 ms → 748.0/1135.5 ms**. Split p50 changes were dev 722.9→748.0, validation 705.1→758.7, and regression 752.7→714.9 ms. Variation is model-dominated; the guard adds no model call. Session tests prove one provider generation and zero regeneration for rejection.

## Non-covered failures

Two current user-visible out-of-scope money failures were observed in the five stability runs for `selection-extra-005`: `R$ 99,90` → `$ 99.90`, and `R$ 99,90` → `99.90`. Its single split run preserved the value. No date/time/percentage/decimal production rule was added, and these are not counted as validator failures. Added literal invention such as the prior `ls -l` observation also remains diagnostic-only.

## Regressions and limitations

No causal permanent-regression failure, selection-scope failure, second-generation retry, or demonstrated useful-refinement loss was introduced. A complete-suite test exposed an initial false-positive classification of ordinary slash text (`itens/conteudos`) as a code path; before acceptance, the path rule was narrowed to require a leading path marker or an additional technical cue, with positive `/api/v2/export` and negative prose regression tests. Final false-positive rejections are zero. Stochastic aggregate objective and action-stability differences are retained rather than attributed to the validator. Duplicate identical literals are protected for presence, not multiplicity. The pre-existing duplicate Xcode file-reference warning for `RefineLanguageDetection.swift` remains outside this experiment.

## Verification

- Focused extractor, preservation, exclusion, selection, archived-proposal, session invocation-count, and evaluator-diagnostic tests pass.
- Complete suite and Debug build pass on the final candidate.
- Holdout was not inspected or run.

## Next single experiment

Run **M12B-005C: semantic-literal equivalence challenge** as evaluation-only, focused on money, time, percentages, dates, decimals, and formatted numbers. The current money failure shows remaining risk, while known safe time normalization shows why exact preservation must not be extended blindly. Do not implement it automatically.

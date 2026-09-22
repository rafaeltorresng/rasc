# M12B-004A — One-Token Abstention Counterfactual

| Field | Value |
|---|---|
| Production change | None |
| Model generation | None; existing M12B-001 outputs only |
| Primary scope | Whole-note dev + validation + permanent regression |
| Holdout | Case bodies were not parsed, inspected, scored, or run |
| Decision | **A — implement unconditional one-token whole-note noChange gate as the next isolated production experiment** |

## Token definition

A primary one-token input is exactly one deterministic lexical/content unit after trimming. Whitespace separates units, but a single group is then shape-classified rather than accepted naively: Unicode lexical words may carry leading/trailing punctuation; URLs, emails, handles, identifiers, code-like forms, numbers, money, emoji sequences, and mixed alphanumeric identifiers are each one content unit. Punctuation-only and unresolved ambiguous-other groups are listed separately and excluded.

Classification precedence: URL → email → @handle → money → money fragment → number → emoji → identifier → lexical word (with attached edge punctuation recorded separately) → mixed alphanumeric identifier → code-like → ambiguous other. Punctuation-only strings are not primary lexical/content units.

Eligible executable primary cases: **24**. Splits: dev=18, regression=1, validation=5. Shapes: handle=2, lexicalWord=19, moneyFragment=1, wordWithAttachedPunctuation=2.

No URL, email, number, emoji, mixed-alphanumeric, code-like, or whole-note identifier appeared in the eligible cohort. `R$` is explicitly classified as an ambiguous money fragment; `deploy?` is a lexical word with attached punctuation. No classification was silently coerced.

## Actual versus forced noChange

| Metric | Actual M12B-001 | Forced noChange | Delta |
|---|---:|---:|---:|
| Recorded changed | 14 | 0 | -14 |
| Recorded noChange | 10 | 24 | +14 |
| User-visible changed | 13 | 0 | −13 |
| User-visible noChange | 11 | 24 | +13 |
| Objective pass | 10 | 24 | +14 |
| User-visible harmful edits | 13 | 0 | −13 |
| Wrong-language indicators | 4 | 0 | −4 |
| Invented-information indicators | 4 | 0 | −4 |
| Excessive expansion | 5 | 0 | −5 |
| Unnecessary edits | 13 | 0 | −13 |
| Low-utility surface-only edits (subset) | 7 | 0 | −7 |
| Expected-useful-change misses | 0 | 0 | +0 |
| Over-abstention | 0 | 0 | +0 |
| Protected-token failures | 0 | 0 | +0 |

One recorded `changed` result (`tiny-en-007`, `@sam`→`@sam`) was already converted by the existing no-change guard into a user-visible noChange. It is counted as recorded changed but not as user-visible harm.

## Effect classification

- A — harm prevented: **12**
- B — neutral: **11**
- C — useful refinement lost: **0**
- D — benchmark uncertain: **0**
- E — frontier/benchmark disagreement: **1**

Safety/utility tradeoff: **13 harms prevented and 0 useful refinements lost**. Because the denominator is zero, no finite ratio is reported; the observed cohort shows harm prevention with no demonstrated utility loss. The harm total includes category E when noChange prevents harm but frontier review exposes a missing benchmark constraint.

## Semantic and shape subtypes

| Subtype | Cases |
|---|---:|
| URL / handle / number / money / emoji | 3 |
| already-valid word | 4 |
| ambiguous fragment | 5 |
| capitalization-only issue | 7 |
| foreign technical term | 5 |

The corpus contains capitalization-only model changes but no actual one-token missing-diacritic, concatenated-word, punctuation-only, or valid typo repair. Therefore the analysis directly tests capitalization-only edits, but positive coverage for `ola`→`Olá`, `nao`→`não`, or `tudobem`→`tudo bem` is absent and remains a dataset limitation.

## Policy simulations

| Policy | Changed retained | Objective pass | Harm prevented | Useful lost | Over-abstention | Wrong-language |
|---|---:|---:|---:|---:|---:|---:|
| A | 0 | 24/24 | 13 | 0 | 0 | 0 |
| B | 0 | 24/24 | 13 | 0 | 0 | 0 |
| C | 7 | 17/24 | 6 | 0 | 0 | 0 |

- **Policy A:** force noChange for every eligible whole-note one-content-unit input.
- **Policy B:** retain a changed output only when existing category/tag metadata explicitly indicates an orthographic or typographic repair. No eligible case has such metadata, so B is observationally identical to A here.
- **Policy C:** retain only named surface transformations (capitalization, diacritic, punctuation, whitespace split) with edit distance ≤2, length ratio 0.8–1.25, and output ≤2 content units.

Policy C retains: regression-pt-tiny-expanded-001, tiny-en-003, tiny-en-005, tiny-pt-002, tiny-pt-006, tiny-pt-007, tiny-pt-012. These retained cases all violate explicit noChange expectations; frontier review labels the reviewed capitalization cases unnecessary. The envelope therefore re-admits known low-utility failures without preserving any demonstrated useful repair.

## Frontier adjudication (secondary only)

Frontier-covered eligible cases: 8. Product judgments: defer=1, languageAmbiguous=2, outputAcceptable=1, productFailure=4.

Frontier benchmark judgments: benchmarkCorrect=4, benchmarkExpectationWrong=3, deferBenchmarkReview=1. Material counterfactual disagreement cases: tiny-pt-008.

Among frontier-covered changed outputs, productFailure=4, outputAcceptable=0, ambiguous=1. No frontier-covered changed output was judged acceptable. Frontier and deterministic action safety agree on every materially reviewable changed case; benchmark-language disagreements are retained as notes and not applied.

For `tiny-pt-008` (`R$`→`$`), frontier review calls out `protectedTokenMutation` and a missing must-preserve constraint, while the deterministic benchmark records only `unexpectedChange`. The case remains a noChange safety win but is classified E rather than silently treating the benchmark as complete. No frontier correction is applied.

## Language

Evaluation-only clear wrong-language indicators among actual visible changes: **4** (tiny-pt-010, tiny-pt-011, tiny-pt-014, tiny-pt-015). Forced noChange reduces this to 0. This is an output-safety effect only and does **not** improve or change the language resolver.

## Stability evidence

Of 18 eligible non-regression cases present in critical stability ×5, 15 flapped between changed and noChange. An unconditional gate would deterministically remove action flapping for this cohort, but this is a counterfactual—not a production measurement.

## Benchmark uncertainty and limitations

- All 24 eligible executable cases explicitly prefer noChange and allow it; the cohort has no positive benchmark case requiring a one-token repair.
- That makes observed useful-refinement loss zero, but does not prove every possible one-token typo or spacing error is valueless.
- Policy B cannot be distinguished empirically from Policy A because no eligible benchmark marks an orthographic repair.
- Policy C is testable on existing outputs and performs worse by retaining capitalization-only changes that the benchmark—and reviewed frontier cases—treat as unnecessary.
- One non-executable whole-note case (`tiny-pt-003`) has no M12B-001 output and is excluded. Four selection cases are reported separately, not scored in the primary policy.

## Decision — A

Recommend **A: implement an unconditional one-token whole-note noChange gate as the next isolated production experiment**.

Evidence: the counterfactual prevents all 13 observed user-visible harmful edits, loses zero demonstrated useful refinements, removes four clear wrong-language outputs, removes all observed expansion and invention indicators, preserves protected-token safety, and introduces zero expectation-defined over-abstentions. Policy C re-admits seven capitalization-only failures; Policy B has no positive repair case to preserve and is indistinguishable from A on this corpus.

This recommendation is constrained to exactly one classified content unit and whole-note refinement. It is not implemented here. A future production experiment must still measure real latency, interaction behavior, and explicitly add positive one-token orthographic cases before considering any exception envelope.

## Artifacts

- `analysis.json` — complete machine-readable cases and policy simulations.
- `case-table.md` — every eligible case plus excluded selection subgroup.

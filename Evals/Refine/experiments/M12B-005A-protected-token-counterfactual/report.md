# M12B-005A protected-token counterfactual

## Decision

**B — implement protection only for a narrower high-confidence subset in a future production experiment.** This experiment itself is evaluation-only and made no production Refine change.

Exact production candidates justified for a future experiment: URLs, emails, handles, technical identifiers, code-like literals, quoted literals, opaque IDs, and deletion of standalone integers. Narrow semantic preservation is also justified for currency expressions, times, and percentages. Defer dates and formatted/decimal-number mutation until targeted positive controls resolve locale-sensitive normalization risk.

## Method and coverage

- Source: existing accepted M12B-004C dev, validation, and permanent-regression outputs.
- Foundation Models generations performed: **0**.
- Holdout used: **no**.
- Global accepted cohort: **254 runs**. Protected-input coverage: **62 unique cases / 62 runs**.
- Frontier overlap: **14 cases**; frontier judgments are a secondary, non-human lens only.
- Scope: 59 whole-note cases and 3 selection cases.

## Current vs simulated reject-to-noChange

| Metric | Current accepted | Counterfactual | Delta |
|---|---:|---:|---:|
| Objective pass | 152/254 | 156/254 | +4 |
| User-visible harmful edits | 61 | 55 | -6 |
| Changed | 197 | 191 | -6 |
| noChange | 57 | 63 | +6 |
| Protected-token corruption occurrences | 7 | 0 | -7 |
| Critical failures | 82 | 78 | -4 |

Counterfactual interceptions: **6**. Effects: {'A': 5, 'B': 1}. Harm prevented: **5**. Demonstrated useful refinements lost: **0**. False-positive detections: **0**. Policy-too-strict cases: **0**.

The covered cohort contains **7 corruption/loss occurrences**: 2 mutations and 5 drops. Two semantic time changes (`15h` → `3:00 PM`, `14h` → `2:00 PM`) were correctly classified as safe normalization rather than corruption. Current and counterfactual useful refinements retained are both **17**.

## Per token class

| Class | Cases | Changed | Preserved | Safe normalized | Mutated | Dropped | Rejections | Harm prevented | Useful lost | False positive | Too strict |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| url | 8 | 6 | 8 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| email | 1 | 1 | 1 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| handle | 3 | 1 | 3 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| money | 9 | 6 | 8 | 0 | 1 | 0 | 1 | 1 | 0 | 0 | 0 |
| date | 3 | 2 | 3 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| time | 10 | 7 | 8 | 2 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| number | 13 | 13 | 26 | 0 | 0 | 2 | 2 | 2 | 0 | 0 | 0 |
| percentage | 4 | 4 | 4 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| identifier | 34 | 33 | 46 | 0 | 1 | 3 | 4 | 3 | 0 | 0 | 0 |
| codeLike | 4 | 4 | 5 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| quotedLiteral | 3 | 3 | 3 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| opaqueID | 6 | 6 | 6 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |

Counts for preservation/mutation are token occurrences; cases and changed proposals are run/case-level counts. A single case may contribute to multiple classes.

## Whole-note vs selection

- Whole note: 5 current corruption occurrences; 4 simulated rejections.
- Selection: 2 current corruption occurrences; 2 simulated rejections.
- Selection is evaluated only against the selected input span. This analysis does not alter selection production behavior or its existing isolation guards.
- Existing selection diagnostics report **0** context-leak/scope failures among these protected-token selection cases.

## Language interaction

1 intercepted cases also carry wrong-language evidence; 5 do not. Rejecting those proposals would prevent the literal mutation as an indirect safety effect, but would not improve the resolver or validator.

## Frontier secondary lens and evaluator disagreements

Frontier adjudication overlaps 14 covered cases and is not human/maintainer ground truth. It overlaps one intercepted case, `mixed-pt-en-006`, and independently labels that output a high-confidence `meaningChanged` product failure. The deterministic benchmark nevertheless passes two newly detected violations (`mixed-pt-en-006`, `telegraphic-pt-009`), so those are retained explicitly as evaluator/benchmark disagreements rather than silently treated as ground truth.

## Added protected-like information

Across the full accepted cohort, changed output introduced unmatched protected-like values in **1** case, and that case is also flagged for forbidden introduced content: `regression-over-expansion-005` changes `ver logs` into an instruction containing the invented quoted command ``ls -l``. Added-value extraction remains diagnostic rather than a proposed guard in M12B-005A.

## Stability

The ×5 artifact covers 14 protected-token cases / 70 runs. Preserved/unsafe token state flapped in **3 cases**: ['mixed-pt-en-004', 'protected-002', 'selection-extra-005']. The counterfactual removes unsafe final token states, but action instability can remain in 6 cases because safe changed outputs may alternate with noChange.

## R$ case

`tiny-pt-008` is classified as money. The accepted M12B-004C path already returns preflight `noChange`, preserving `R$` without generation. The earlier M12B-001 `R$` → `$` observation would be caught because changing the currency marker is not a safe normalization; `noChange` is safer. A future maintainer-reviewed benchmark edit could add `mustPreserveTokens: ["R$"]`, but this experiment did not modify the frozen corpus.

## Recommendation rationale

The evidence supports a small, explainable post-generation reject-to-noChange guard for exact structural literals, narrowly equivalent money/time/percentage formatting, and deletion of exact standalone integers. It does not yet justify production enforcement for dates or formatted/decimal-number rewrites: locale-sensitive changes can be either dangerous or acceptable, and the current data lacks sufficient positive controls. This is recommendation **B**, not implementation.

## Verification

- Deterministic extractor unit tests pass, including URLs, emails, handles, money, dates, times, numbers, percentages, snake/camel/Pascal/mixed identifiers, UUID/hash IDs, quoted/code-like literals, overlap suppression, repeated-literal deduplication, and ordinary-language negative controls.
- Complete `Rasc` scheme test suite passes under `xcodebuild test` on 2026-09-21.
- The analysis script compiles with `python3 -m py_compile` and regenerates the four experiment artifacts without Foundation Models calls.
- Xcode continues to emit the existing duplicate file-reference warning for `RefineLanguageDetection.swift`; it does not fail the build or tests and is outside this experiment.

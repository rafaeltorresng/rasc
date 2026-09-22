# M12B-005D — Production Semantic Money-Literal Guard

## Decision

**ACCEPT.** The money-only validator contained every observed in-scope corruption, produced zero final user-visible money corruptions, and introduced no demonstrated false-positive rejection or useful-refinement loss. Holdout was not used.

## Architecture

The existing pipeline now runs: preflight → one model generation → language validation → exact protected-literal validation → semantic money validation → changed or the existing noChange result. The money validator never repairs, regenerates, or performs a second provider call.

## Money contract

- Definition: only explicit `R$`, `US$`, `$`, `€`, `£`, `BRL`, `USD`, `EUR`, or `GBP` spans; bare numbers are excluded.
- Identity: `R$`/`BRL`, `US$`/`USD`, `€`/`EUR`, and `£`/`GBP` have explicit identities. Bare `$` remains a separate ambiguous-dollar identity and is never inferred as USD.
- Numeric equivalence: integers, one/two-digit decimals, valid mixed grouping/decimal forms, and repeated three-digit grouping parse conservatively. A single separator plus three trailing digits is ambiguous.
- Ambiguity: ambiguous or invalid source amounts require byte-for-byte literal preservation; no semantic guess is permitted.
- Multiplicity: one-to-one multiset matching preserves distinct values, duplicates, currency, and count; added or removed money literals reject.
- Selection: only money within `request.inputText`—the selected source—is required. Surrounding-note money never becomes an obligation.
- Diagnostics contain only rejection reason and `money` class, never note text or values.

## Aggregate comparison

Primary comparison is accepted M12B-005B → M12B-005D. Aggregate differences include stochastic generation and are not treated as causal unless the money trace records an interception.

| Split | M12B-005B objective pass | M12B-005D objective pass | Critical failures | changed/noChange/other |
|---|---:|---:|---:|---:|
| dev | 115/193 (59.6%) | 112/193 (58.0%) | 57 → 56 | 143/48/2 → 137/54/2 |
| validation | 31/57 (54.4%) | 30/57 (52.6%) | 19 → 18 | 44/13/0 → 47/10/0 |
| regression | 5/6 (83.3%) | 4/6 (66.7%) | 1 → 2 | 4/2/0 → 5/1/0 |

## Money-specific results

- Covered runs across dev/validation/regression: **9**
- Raw money-bearing changed proposals: **8**
- Raw semantic corruptions: **4**
- Raw ambiguous transformations: **0**
- Guard rejections: **2**
- Corruptions caught: **2**
- Additional corruptions already contained by the earlier exact-literal guard: **2**
- Safe normalizations accepted: **1**
- Final user-visible money corruptions: **0**
- False-negative corruptions: **0**
- False-positive rejections: **0 demonstrated**
- Useful refinements lost: **0 demonstrated**
- Rejection breakdown: `{"multiplicityChanged": 2}`
- Raw corruption breakdown: `{"multiplicityChanged": 4}`
- Whole-note/selection guard rejections: **2 / 0**

## Stability

- Action instability: **20 → 20**
- Pass/fail instability: **21 → 23**
- Raw money corruptions: **3**
- Money guard rejections: **3**
- Final money corruptions: **0**
- Money-safety instability after validation: **0 user-visible unsafe runs**
- Raw money-safety instability cases: **1** (`selection-extra-005`)
- Final money-safety instability cases: **0**
- Stability rejection breakdown: `{"currencyChanged": 1, "currencyDropped": 1, "valueChanged": 1}`
- Stability whole-note/selection rejections: **0 / 3**

## M12B-005C money subset

The 16-case targeted subset remains maintainer-unapproved. It produced **14** changed money proposals, **1** corruptions, **0** ambiguous transformations, **1** guard rejections, **3** accepted safe normalizations, and **0** final corruptions.

Challenge rejection breakdown: `{"literalDropped": 1}`.

All 16 challenge cases are whole-note cases. Selection evidence comes from frozen-corpus `selection-extra-005` stability runs plus deterministic scope-boundary tests.

## Known BRL failures

Deterministic production tests verify both `R$ 99,90 → $ 99.90` and `R$ 99,90 → 99.90` reject to existing noChange. The former is `currencyChanged`; the latter is `currencyDropped`.

## Latency

| Split | Before p50/p95 | After p50/p95 |
|---|---:|---:|
| dev | 748.0/1101.6 ms | 704.1/1066.6 ms |
| validation | 758.7/1256.8 ms | 735.2/1089.3 ms |
| regression | 714.9/1291.4 ms | 736.8/1161.5 ms |

The validator is deterministic local parsing. It adds no model call; observed end-to-end latency differences are dominated by stochastic Foundation Models generation.

## Causal analysis

Only proposals with a production money rejection trace are causal M12B-005D evidence. Across the primary splits there were **0** causal objective-pass improvements and **0** causal regressions. All non-intercepted pass/fail changes are classified as stochastic generation differences.

The permanent-regression decline from 5/6 to 4/6 is non-causal: the changed case had no money interception. No causal critical or permanent-regression failure was introduced.

## Tests and build

- Initial targeted Refine contract/session run: **62 passed**.
- Final contract suite after currency-alias coverage additions: **33 passed**.
- Complete project suite: **210 passed**.
- Debug build: **succeeded**.
- Provider-path test: exactly one generation, zero repair/regeneration calls.
- Existing non-blocking Xcode warning: duplicate `RefineLanguageDetection.swift` project reference.

## Next single experiment

Run a percentage-only semantic guard experiment. Do not implement time concurrently: keeping one class per experiment preserves causal attribution.

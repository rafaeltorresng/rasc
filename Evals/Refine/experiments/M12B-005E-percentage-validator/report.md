# M12B-005E — Production Semantic Percentage Guard

## Decision

**ACCEPT.** See metrics below for percentage-specific safety evidence.

## Architecture

Pipeline: preflight → one model generation → language validation → exact protected-literal validation → semantic money validation → semantic percentage validation → changed or existing noChange.

## Percentage contract

- Definition: only explicit `%`-marked spans; bare numbers are excluded.
- Invariants: numeric percentage value, `%` representation, and multiplicity are preserved.
- Safe normalizations: spacing around `%` and provably equivalent decimal separators when parsing is unambiguous.
- Ambiguity: ambiguous source forms require exact literal preservation.
- Selection: only percentages inside `request.inputText` are obligations.

## Aggregate comparison

Primary comparison is accepted M12B-005D → M12B-005E.

| Split | M12B-005D objective pass | M12B-005E objective pass | Critical failures | changed/noChange/other |
|---|---:|---:|---:|---:|
| dev | 112/193 (58.0%) | 118/193 (61.1%) | 56 → 52 | 137/54/2 → 146/45/2 |
| validation | 30/57 (52.6%) | 32/57 (56.1%) | 18 → 19 | 47/10/0 → 46/11/0 |
| regression | 4/6 (66.7%) | 4/6 (66.7%) | 2 → 2 | 5/1/0 → 5/1/0 |

## Percentage-specific results

- Covered runs across dev/validation/regression: **4**
- Raw percentage-bearing changed proposals: **4**
- Raw semantic corruptions: **0**
- Guard rejections: **0**
- Safe normalizations accepted: **0**
- Final user-visible percentage corruptions: **0**
- False-positive rejections: **0 demonstrated**
- Useful refinements lost: **0 demonstrated**

## Stability

- Action instability: **20 → 23**
- Pass/fail instability: **23 → 26**
- Final percentage corruptions: **0**

## M12B-005C percentage subset

16-case maintainer-unapproved subset: **13** changed proposals, **0** guard rejections, **0** final corruptions.

## Latency

| Split | Before p50/p95 | After p50/p95 |
|---|---:|---:|
| dev | 704.1/1066.6 ms | 713.9/1057.6 ms |
| validation | 735.2/1089.3 ms | 741.8/1080.1 ms |
| regression | 736.8/1161.5 ms | 762.1/1249.3 ms |

## Next single experiment

Run a constrained time-only semantic guard experiment. Do not combine with date or generic number guards.

# M12B-005F — Production Constrained Time-Literal Guard

## Decision

**ACCEPT.** No — live raw corruptions were observed and contained.

This is the final semantic-literal experiment for this iteration.

## Architecture

Pipeline: preflight → one model generation → language validation → exact protected-literal validation → money validation → percentage validation → **time validation** → changed or existing noChange.

## Supported time syntax

- 24-hour family: `15h`, `15h30`, `15:00`, `15:30`, `09:00`, `00:00`
- 12-hour family: `3 PM`, `3:30 PM`, `3 AM`, `12 AM`

Bare integers, decimal forms like `3.30`, and natural-language-only time references are excluded.

## Equivalence policy

Same-family only:

- 24h: `15h` ↔ `15:00`, `15h30` ↔ `15:30`
- 12h: `3 PM` ↔ `3:00 PM`, `3:30 PM` ↔ `3:30PM`

Cross-family rewrites reject even when mathematically equivalent (`15:00` ↔ `3 PM`).

## Aggregate comparison

Primary comparison: M12B-005E → M12B-005F.

| Split | M12B-005E objective pass | M12B-005F objective pass | Critical failures | changed/noChange/other |
|---|---:|---:|---:|---:|
| dev | 118/193 (61.1%) | 109/193 (56.5%) | 52 → 58 | 146/45/2 → 135/55/3 |
| validation | 32/57 (56.1%) | 32/57 (56.1%) | 19 → 16 | 46/11/0 → 44/12/1 |
| regression | 4/6 (66.7%) | 4/6 (66.7%) | 2 → 2 | 5/1/0 → 5/1/0 |

## Time-specific results

- Covered runs (primary): **10**
- Raw time-bearing proposals: **8**
- Raw time corruptions: **2**
- Raw breakdown: `{"crossFamilyRewrite": 1, "literalDropped": 1}`
- Guard rejections: **2**
- Safe normalizations accepted: **2**
- Final user-visible time corruptions: **0**
- False-positive rejections: **0 demonstrated**
- Useful refinements lost: **0 demonstrated**

## Stability

- Action instability: **23 → 17**
- Pass/fail instability: **26 → 21**
- Final time corruptions: **0**

## M12B-005C time subset

16-case subset: **13** changed proposals, **2** guard rejections, **0** final corruptions.

## Latency

| Split | Before p50/p95 | After p50/p95 |
|---|---:|---:|
| dev | 713.9/1057.6 ms | 723.5/1114.8 ms |
| validation | 741.8/1080.1 ms | 721.1/1043.3 ms |
| regression | 762.1/1249.3 ms | 742.6/763.8 ms |

## Next single experiment

Semantic-literal work is complete for this iteration. The next Refine experiment should address a different reliability axis (not date/generic-number validation) unless new real-world evidence reopens semantic literals.

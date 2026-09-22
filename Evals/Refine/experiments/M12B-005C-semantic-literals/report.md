# M12B-005C — Semantic-Literal Equivalence Challenge

## Decision

**B — implement only a proven safe subset in a future production experiment.** This task is evaluation-only and made no production Refine change. Holdout was not used.

Recommended future scope: money identity/value preservation, same-family time equivalence, and percentage magnitude with `%` retained. Dates and decimal/formatted numbers are not ready because locale ambiguity and representation changes cannot be handled safely by a small universal comparator.

## Challenge and method

- 80 agent-generated, maintainer-unapproved cases; 16 per class.
- Portuguese, English, Spanish, and mixed technical notes.
- One current M12B-005B run per case; 100 runs over 20 critical cases (×5).
- Class-specific parsers return exact, equivalent, different, or ambiguous. Ambiguous is never treated as equivalent.
- Raw actions were 63 changed / 17 noChange; final actions were 62 changed / 18 noChange.
- The comparator matched every declared candidate expectation in the 282-transformation contract matrix.
- Counterfactual policy rejects different/ambiguous proposals to existing noChange with no regeneration.

Literal disposition is intentionally narrower than whole-output product safety. A proposal can preserve a literal while still failing language, meaning, or invention checks; those existing controls remain necessary and are not credited as semantic-literal successes here.

## Results by class

| Class | Cases | Raw exact | Raw safe normalization | Raw corruption | Dropped | Stability corruption | Corruptions caught | Ambiguous |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| money | 16 | 75.0% | 12.5% | 6.2% | 0 | 0.0% | 1 | 1 |
| time | 16 | 93.8% | 6.2% | 0.0% | 0 | 0.0% | 0 | 0 |
| percentage | 16 | 81.2% | 18.8% | 0.0% | 0 | 0.0% | 0 | 0 |
| date | 16 | 81.2% | 0.0% | 0.0% | 0 | 0.0% | 0 | 3 |
| number | 16 | 81.2% | 6.2% | 6.2% | 0 | 0.0% | 1 | 1 |

## Counterfactual validator

- Rejections: **7**
- Semantic corruptions caught: **2**
- Safe normalizations preserved: **7**
- False-positive rejections: **0 demonstrated**; ambiguous rejections remain review items, not proven false positives.
- False-negative corruptions: **0**
- Ambiguous transformations conservatively rejected: **5**
- User-visible semantic corruptions: **2 → 0**
- Useful refinements lost: **0 demonstrated** among transformations classified safe.

Estimated comparator latency is 0.0008 ms p50 / 0.0462 ms p95 in Python. A future guard would add no model call and no retry.

## Known BRL failure

The existing M12B-005B stability artifact contains both observed failures: `R$ 99,90 → $ 99.90` and `R$ 99,90 → 99.90`. This comparator classifies both **semanticCorruption**. It classifies `R$ 99,90 → R$ 99.90` and spacing-only `R$99,90` as **safeNormalization** because explicit BRL identity and the two-decimal amount remain unambiguous.

## Stability

- Critical runs: **100** across **20** cases.
- Raw semantic-corruption rate: **0.0%**.
- Critical cases with any corruption: **0**.
- Cases whose literal disposition varied across runs: **3**.
- Counterfactual user-visible corruption runs: **0**.

## Representation conservatism

- Money: currency identity and amount must both survive.
- Time: equal clock values are accepted only within the same 12h/24h representation family; cross-family conversion remains ambiguous.
- Percentage: numeric magnitude and `%` notation must survive; `50% → 0.5` is corruption.
- Date: ambiguous numeric dates favor exact preservation; cross-family or locale-order conversion remains ambiguous.
- Numbers: locale punctuation is parsed per case, never by generic punctuation stripping. Separator-family changes remain ambiguous or different.

## Readiness

| Class | Ready? | Recommended boundary |
|---|---|---|
| Money | ready | Exact currency identity plus locale-parsed value; spacing-only normalization allowed. |
| Time | ready | Same minute value within the same representation family. |
| Percentage | ready | Same magnitude with percent notation retained. |
| Date | not ready | Preserve until locale/order and representation ambiguity has stronger evidence. |
| Decimal/formatted number | not ready | Preserve until separator-family rules have stronger evidence. |

The subset recommendation also aligns with earlier non-ground-truth diagnostics: M12B-005A observed two safe same-value time normalizations, while M12B-005B directly observed the BRL identity-loss variants. M12B-005C itself adds three safe percentage normalizations and exposes unresolved date/number ambiguity.

The recommendation is deliberately narrower than the evaluation parser. Do not implement it automatically.

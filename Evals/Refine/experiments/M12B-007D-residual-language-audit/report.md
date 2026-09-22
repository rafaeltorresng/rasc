# M12B-007D — Residual language failure audit

Evaluation-only audit of M12B-007B residual failures. Production remains resolver-v2.

## Recommendation

**B. production validator calibration**

Language can close after this intervention: **no**.

## Wrong-language root causes (20 cases)

- **resolverUnresolved**: 13
- **resolverWrongHighConfidence**: 4
- **validatorMissedMismatch**: 3

## False-rejection root causes (13 cases)

- **validatorTooAggressive**: 9
- **languageEvaluatorWrong**: 2
- **mixedTechnicalMisclassified**: 2

## Causal regressions

- `legacy-selection-unicode-pt-001` → **validatorMissedMismatch** (pt/high, raw `id`)
- `numbers-003` → **validatorMissedMismatch** (pt/high, raw `en`)
- `short-pt-009` → **resolverUnresolved** (ambiguous/insufficient, raw `en`)
- `short-pt-012` → **resolverUnresolved** (ambiguous/insufficient, raw `en`)
- `telegraphic-pt-009` → **resolverUnresolved** (ambiguous/insufficient, raw `en`)
- `variant-pt-013` → **resolverUnresolved** (ambiguous/insufficient, raw `en`)

## Counterfactual summary

- Policy A prevents 4 wrong-language edits; loses 0 useful refinements.
- Policy B removes 11 false rejections; prevents 1 wrong-language edits; introduces 0 new misses.
- Policy C: 17 failures theoretically resolver-addressable; not recommended after M12B-007C rejection.

See `counterfactuals.md` and `case-table.md` for per-case detail.

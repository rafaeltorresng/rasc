# M12B-007E — Production language validator calibration

## Decision

**ACCEPT**

Validator calibration materially reduced false language rejections without useful-refinement loss or a new validator-miss cluster.

## Primary metrics (dev + validation + regression)

| Metric | M12B-007B | M12B-007E | Delta |
|---|---:|---:|---:|
| False language rejections | 13 | 1 | -12 |
| Final wrong-language changes | 20 | 15 | -5 |
| Validator caught wrong-language | 16 | 4 | -12 |
| Useful refinements accepted | 126 | 129 | +3 |
| Useful refinements lost to validator | 13 | 1 | -12 |
| New validator misses | 7 | 5 | -2 |

## M12B-007D Policy B verification

- Predicted fixed: 11/11
- Still rejected: []
- Predicted unchanged low-confidence cases: ['selection-leak-test-007']
- Predicted caught wrong-language: ['selection-extra-001']
- Counterfactual mismatches: [{"caseID": "incomplete-006", "issue": "expectedStillRejectedOrFallback"}]

## Stability

{
  "changedNoChangeInstability": {
    "casesWithMultipleRuns": 61,
    "unstableCases": 16
  },
  "finalWrongLanguageSafetyInstability": {
    "casesWithMultipleRuns": 61,
    "unstableCases": 1
  },
  "languageOutputInstability": {
    "casesWithMultipleRuns": 61,
    "unstableCases": 4
  }
}

## Next experiment

M12B-007F unresolved-language safety guard (Policy A) — largest remaining wrong-language cluster is resolver-unresolved short PT drift.

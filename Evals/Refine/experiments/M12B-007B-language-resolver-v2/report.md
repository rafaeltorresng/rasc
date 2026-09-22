# M12B-007B — Production language resolver v2

## Decision

**ACCEPT**

Resolver v2 materially reduced final wrong-language edits (48→20 vs M12B-005F baseline), fixed 11/18 frontier cases with zero remaining frontier wrong-language previews, removed false-Spanish resolver failures, and improved net language safety by 28 cases despite 6 short-PT unresolved-path regressions.

## Step 1 boundary fix

- Prior M12B-007A candidate overall accuracy: 73.5%
- After boundary fix rerun: 79.6%
- False Spanish resolutions: 17 → **0**
- Frontier resolver fixes: 9 → **14**
- Gate: **PASS**

## Combined end-to-end (dev + validation + regression)

| Metric | Baseline M12B-005F | M12B-007B |
|---|---:|---:|
| Final wrong-language changes | 48 | **20** |
| Raw wrong-language proposals | 57 | **29** |
| Validator caught wrong-language | 0 | **0** |
| Useful refinements accepted | 98 | **126** |
| Unresolved rate | n/a | **24.2%** |

## Frontier wrong-language cohort (18)

{
  "fixed": 11,
  "other": 2,
  "safeNoChange": 4,
  "unresolved": 1
}

## Stability (critical ×5)

{
  "changedNoChangeInstability": {
    "casesWithMultipleRuns": 61,
    "unstableCases": 18
  },
  "finalWrongLanguageSafetyInstability": {
    "casesWithMultipleRuns": 61,
    "unstableCases": 1
  },
  "languageOutputInstability": {
    "casesWithMultipleRuns": 61,
    "unstableCases": 3
  },
  "passFailInstability": {
    "casesWithMultipleRuns": 61,
    "unstableCases": 18
  },
  "resolverV1Instability": {
    "casesWithMultipleRuns": 61,
    "unstableCases": 0
  },
  "resolverV2Instability": {
    "casesWithMultipleRuns": 61,
    "unstableCases": 0
  }
}

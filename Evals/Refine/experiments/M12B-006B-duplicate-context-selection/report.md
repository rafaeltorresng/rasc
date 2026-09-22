# M12B-006B — Duplicate-context selection guard

## Decision

**ACCEPT**

## Baseline vs candidate

| Metric | M12B-006A baseline | M12B-006B |
|---|---:|---:|
| Final context leaks | 1 | **0** duplicate-context leaks |
| Final selection failures (duplicate class) | 1 | **0** |
| Guard interceptions (duplicate guard) | 0 | **1** |
| False positives | 0 | **0** |
| Useful refinements lost | 0 | **0** |

## selection-audit-015 stability ×5

[
  {
    "runIndex": 0,
    "rawProposal": "retry",
    "productionRejection": "no_change",
    "finalDecision": "noChange",
    "finalOutput": "retry"
  },
  {
    "runIndex": 1,
    "rawProposal": "retry again",
    "productionRejection": "selectionDuplicateContextLeak",
    "finalDecision": "noChange",
    "finalOutput": "retry"
  },
  {
    "runIndex": 2,
    "rawProposal": "retry",
    "productionRejection": "no_change",
    "finalDecision": "noChange",
    "finalOutput": "retry"
  },
  {
    "runIndex": 3,
    "rawProposal": "retry",
    "productionRejection": "no_change",
    "finalDecision": "noChange",
    "finalOutput": "retry"
  },
  {
    "runIndex": 4,
    "rawProposal": "retry",
    "productionRejection": "no_change",
    "finalDecision": "noChange",
    "finalOutput": "retry"
  }
]

## Causal guard interceptions

{
  "selection-audit-015": 1
}

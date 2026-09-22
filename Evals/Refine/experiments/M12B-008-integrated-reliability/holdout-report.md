# M12B-008 holdout report

## Provenance

```
holdoutRun=once
startedAt=2026-09-22T14:23:58Z
finishedAt=2026-09-22T14:25:00Z
gitSha=b109a877094fb447ac23debf50a4ab118ac5979a
corpus=Evals/Refine/corpus.v1.jsonl
splits=Evals/Refine/splits.v1.json
note=First post-M12B integrated holdout; not used for tuning in this task.

```

## Baseline-v2 vs final (holdout)

| Metric | Baseline-v2 | Final | Delta |
|---|---:|---:|---:|
| Objective pass | 0.3611111111111111 | 0.5416666666666666 | 0.18055555555555552 |
| Critical failures | 29 | 13 | -16 |
| Harmful edit rate | None | 0.4305555555555556 | None |
| Model proposal failure rate | None | 0 | None |

Holdout interpreted as final evidence only; no production changes made after this run.

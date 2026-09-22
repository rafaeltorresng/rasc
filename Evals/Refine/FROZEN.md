# M12A Frozen Artifacts (v2 baseline)

Frozen on 2026-09-20 after corrected language analyzer and corpus fixes.

## Frozen files

| Artifact | Path | Notes |
|---|---|---|
| Corpus v1 | `corpus.v1.jsonl` | 322 cases — do not edit without version bump |
| Splits v1 | `splits.v1.json` | dev 193 / validation 57 / holdout 72 |
| Regression | `regression.jsonl` | 6 permanent product-failure cases |
| Review queue | `review-queue.jsonl` | 75 maintainer-review cases (not auto-validated) |

## Canonical baseline (production `refine-v1`, corrected evaluator)

Reports under `reports/baseline-*-v2/`:

- `baseline-dev-v2`
- `baseline-validation-v2`
- `baseline-holdout-v2`
- `baseline-regression-v2`
- `baseline-stability-v2` (critical stability ×5)

Historical `baseline-*-v1` reports are **not** canonical for M12B.

## M12B discipline

- Compare experiments only against **baseline-v2**.
- Do **not** inspect or tune against holdout during normal M12B work.
- One production Refine change per experiment.
- Never overwrite prior experiment results under `experiments/`.

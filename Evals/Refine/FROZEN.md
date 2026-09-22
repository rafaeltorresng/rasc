# M12A Frozen Artifacts (v2 baseline)

Frozen on 2026-09-20 after corrected language analyzer and corpus fixes.

## Frozen files (canonical in Git)

| Artifact | Path | Notes |
|---|---|---|
| Corpus v1 | `corpus.v1.jsonl` | 322 cases — do not edit without version bump |
| Splits v1 | `splits.v1.json` | dev 193 / validation 57 / holdout 72 |
| Regression | `regression.jsonl` | 6 permanent product-failure cases |
| Review queue | `review-queue.jsonl` | 75 maintainer-review cases (not auto-validated) |
| Priority queue | `priority-queue.v1.json` | Maintainer triage ordering |
| Experiment records | `experiments/<id>/` | `experiment.md`, `analysis.json`, accepted `report.md`, policy docs |

## Regenerable outputs (excluded from Git)

These are produced by `./Scripts/refine-eval.sh` and related tooling. They may exist locally under `Evals/Refine/reports/` but are **not** source-of-truth in Git:

- `reports/baseline-*-v2/` and other eval run directories
- `run.log`, `.profraw`, Python caches, `corpus-root/` scratch trees
- Generated `review-queue.md` (canonical source is `review-queue.jsonl`)

Re-run the eval scripts to reproduce reports from frozen corpora and experiment records.

## Canonical baseline (production `refine-v1`, corrected evaluator)

Baseline metrics are recorded in experiment docs and maintainer adjudications. Historical report directories name the accepted baseline-v2 runs:

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

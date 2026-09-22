# M12B Refine Experiments

Controlled, single-change experiments against the frozen M12A v2 baseline.

## Required fields per experiment

Each experiment directory must record:

- **Experiment ID** (e.g. `M12B-001-language-contract`)
- **Hypothesis**
- **Exact production change**
- **Prompt version**
- **GenerationOptions** (document defaults if unchanged)
- **Baseline used** (`baseline-*-v2`)
- **Dev / validation / regression / critical-stability metrics**
- **Latency**
- **Regressions introduced**
- **Decision:** ACCEPT or REJECT

## Rules

- Never overwrite previous experiment results.
- Do not run holdout after tuning begins.
- Do not bundle multiple Refine changes in one experiment.

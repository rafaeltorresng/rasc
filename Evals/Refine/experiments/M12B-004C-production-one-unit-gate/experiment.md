# M12B-004C experiment record

- Status: **ACCEPT**
- Production foundation: M12B-001
- Prompt version: `refine-v2-language` (unchanged)
- Model: `system-language-model.default`
- Generation options: Foundation Models defaults; no explicit `GenerationOptions` supplied (unchanged)
- Language resolver/validator: M12B-001 (unchanged)
- Holdout: not inspected or run

## Hypothesis

For a whole-note Refine request containing exactly one deterministic lexical/structural content unit, Rasc should return the existing noChange result before provider availability, session construction, language resolution, generation, or validation.

## Dataset identity

| Artifact | Version / SHA-256 |
|---|---|
| `corpus.v1.jsonl` | `422154c7256fe1e58b08025baf75ee1bb4f30b3bcb418acbccfba5bb61ab7d0b` |
| `splits.v1.json` | version 1; `c934a983258fb858636eb6e035c993fc42cf82db2ebd898a9a7810446a5d897f` |
| `regression.jsonl` | `18f398a8d40696445c5eb59674fefb2489d6e53b86eefee90ef8a8065d569481` |
| `one-token-positive-controls.v1.jsonl` | maintainer-unapproved; `3ce72f68b42ed4fd189992e61355edb8f7c997e685897344d7f4b0c0cd983f18` |

The challenge remains outside frozen dev/validation/regression splits.

## Baselines

- Canonical baseline-v2: `Evals/Refine/reports/baseline-{dev,validation,regression,stability}-v2`
- Primary direct comparison: `Evals/Refine/experiments/M12B-003-nochange-ambiguity/references/m12b-001-rerun`
- Secondary evidence only: M12B-004A frontier counterfactual and M12B-004B maintainer-unapproved challenge

## Production change

See [production-diff.md](production-diff.md). The policy is applied once, before provider work, and has one rule only. No prompt, provider generation, resolver, validator, sampling, selection guard, UX, Settings, or persistence behavior changed.

## Results and decision

See [report.md](report.md) for the complete before/after report and [analysis.json](analysis.json) for machine-readable metrics. Raw results are under `reports/`.

The candidate is accepted because eligible harmful output and model calls fell to zero, all 25 frozen eligible cases passed objective constraints, the 24 M12B-004A cases became deterministic safe noChange, selection and non-gated code paths were preserved, and gated p50/p95 latency fell to 0.010/0.022 ms in critical stability. The known loss of four minor positive-control repairs is explicit and consistent with Rasc’s asymmetric safety contract.

One non-gated permanent-regression sample (`regression-over-expansion-005`) changed from pass to fail, but that request executes byte-for-byte unchanged M12B-001 generation code and is reported as stochastic variation, not a gate-introduced regression.

## Next single experiment

Evaluate protected-token safety for multi-unit whole-note and selection refinements. Do not implement it automatically.

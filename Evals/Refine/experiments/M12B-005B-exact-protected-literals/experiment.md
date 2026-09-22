# M12B-005B experiment record

- Status: **ACCEPT**
- Production foundation: M12B-001 + accepted M12B-004C
- Prompt version: `refine-v2-language` (unchanged)
- Model: `system-language-model.default`
- Generation options: Foundation Models defaults; unchanged
- Holdout: not inspected or run

## Hypothesis

A post-generation exact-preservation validator for a narrow set of high-confidence literals will prevent silent literal corruption with no demonstrated useful-refinement loss, false-positive rejection, second generation, or material latency cost.

## Frozen inputs

| Artifact | SHA-256 |
|---|---|
| `corpus.v1.jsonl` | `422154c7256fe1e58b08025baf75ee1bb4f30b3bcb418acbccfba5bb61ab7d0b` |
| `splits.v1.json` | `c934a983258fb858636eb6e035c993fc42cf82db2ebd898a9a7810446a5d897f` |
| `regression.jsonl` | `18f398a8d40696445c5eb59674fefb2489d6e53b86eefee90ef8a8065d569481` |

Primary comparison is the accepted M12B-004C recorded reports. Canonical baseline-v2 remains a historical reference. Stochastic before/after samples are reported transparently; causal guard evidence comes from current raw-proposal/final-result pairs and deterministic archived-proposal tests.

## Decision

Accept. Across dev, validation, and permanent regression, 43 runs contained covered literals; 4 generated proposals violated exact preservation, all 4 were rejected, and zero covered corruptions reached the user. Manual case audit found 4 harms prevented, zero useful refinements lost, and zero false-positive rejections. Stability produced 6 intermittent corrupt proposals and zero final protected-safety failures. See `report.md` and `analysis.json`.

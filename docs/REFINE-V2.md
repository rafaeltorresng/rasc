# Refine v2

Canonical production Refine stack after M12B reliability work. Frozen at M12B closeout (M12B-008).

Implementation baseline identifier: **`refine-v2`** (`RefinementImplementationBaseline.identifier`).

## Product contract

Refine is **conservative**.

- A missed improvement is acceptable.
- A harmful edit is not.

Refine should:

- preserve meaning
- preserve language unless explicitly configured otherwise (see M12C language preference)
- avoid invention
- preserve protected information
- respect selection boundaries
- return `noChange` when transformation is unsafe or unjustified

## Final production pipeline

Order matches the production path in `ScratchpadSession` + `FoundationModelsRefinementProvider`:

1. **One-content-unit preflight** — `RefinementPreflightPolicy` returns immediate `noChange` for whole-note single structural units (M12B-004C).
2. **Language resolver v2** — `RefineLanguageResolver` resolves the language contract from note content (M12B-007B). Default policy is **match note language**.
3. **One Foundation Models generation** — single `LanguageModelSession.respond` per request; no repair, no second generation.
4. **High-confidence language validation** — `RefineLanguageValidator` rejects unauthorized language drift when resolver confidence is high (M12B-007E).
5. **Strict unresolved-language safety guard** — `RefineUnresolvedLanguageGuard` runs only for genuinely unresolved resolver output (`ambiguous`/`unknown` + insufficient confidence); mixed/high-confidence paths bypass (M12B-007G).
6. **Exact protected-literal validation** — `RefineProtectedLiteralValidator` (M12B-005B).
7. **Money validation** — `RefineMoneyLiteralValidator` (M12B-005D).
8. **Percentage validation** — `RefinePercentageLiteralValidator` (M12B-005E).
9. **Time validation** — `RefineTimeLiteralValidator` (M12B-005F).
10. **Selection safety** — replacement-only + size cap in `RefinementRequest` (M12B-006A).
11. **Duplicate-context selection protection** — `RefinementSelectionDuplicateContextGuard` (M12B-006B).
12. **Changed / noChange finalization** — preview only after all guards pass; acceptance persists via GRDB revision.

**Raw model failure vs final user-visible failure:** a bad proposal caught by a deterministic guard is a model failure and a safety success. Metrics must not treat guarded rejections as user-visible corruption.

## Accepted M12B experiments

| Milestone | Contribution |
|---|---|
| M12B-001 | Language contract in prompt + resolver foundation |
| M12B-004C | One-content-unit whole-note preflight |
| M12B-005B | Exact protected-literal finalize guard |
| M12B-005D | Money literal guard |
| M12B-005E | Percentage literal guard |
| M12B-005F | Time literal guard |
| M12B-006A | Selection replacement-only + size cap |
| M12B-006B | Duplicate-context selection guard |
| M12B-007B | Language resolver v2 |
| M12B-007E | High-confidence language validator calibration |
| M12B-007G | Strict unresolved-language safety guard (final language experiment) |
| M12B-008 | Integrated reliability gate — no beta-blocking issues |

Counterfactual / diagnostic experiments (005A, 005C, 007A, 007D, 004A/004B) informed production guards but are not separate runtime layers.

## Rejected experiments (do not revive)

| Direction | Why rejected |
|---|---|
| M12B-003 prompt-only noChange calibration | Did not meet acceptance; no production prompt-only calibration shipped |
| M12B-007F broad unresolved-language guard | Mixed/high false rejections; replaced by M12B-007G strict eligibility |
| M12B-007C short-PT morphology resolver | Rejected; no production code |
| Other rejected language hardening | See experiment reports under `Evals/Refine/experiments/` — do not reintroduce without new evidence |

Active guard eligibility is **`RefineUnresolvedLanguageGuard.isStrictUnresolvedEligible`** only. Rejected M12B-007F broad scope must not return.

## Intentionally unsupported / deferred

- **Date semantic normalization** is not protected (exact tokens may be protected; semantic date rewrites are not).
- **Generic / formatted-number semantic normalization** is not protected.
- **No more language heuristics** for the M12B iteration — language reliability is closed after M12B-007G.
- **No more selection guards** without new repeatable user-visible evidence.
- **Fixed output locale** was deferred to M12C (not part of `refine-v2` baseline).

## M12B-008 integrated evidence (vs baseline-v2)

Summarized from `experiments/M12B-008-integrated-reliability/`. Holdout run once; not used for tuning.

| Split | Objective pass (baseline-v2 → final) | Critical failures | Harmful-edit proxy |
|---|---:|---:|---:|
| Dev | 0.43 → 0.66 | 84 → 40 | 0.43 |
| Validation | 0.44 → 0.54 | 25 → 15 | 0.44 |
| Holdout | 0.36 → 0.54 | 29 → 13 | 0.43 |

Latency (final): dev p50 ~778 ms / p95 ~1204 ms; holdout p50 ~720 ms / p95 ~1054 ms.

### Failure terminology

- **Raw model failures:** wrong-language proposals, unsafe literal proposals, selection-unsafe proposals — including those **caught by guards**.
- **Final user-visible failures:** outputs that would reach preview/acceptance and harm trust (wrong language, meaning change, literal corruption, selection leak, etc.).

Eval scorer flags on protected tokens measure **proposal risk**; **`userVisibleProtectedLiteralCorruptionCount`** is the final visible metric. M12B-008 final holdout/dev/validation **user-visible protected-literal corruption was 0** where production guards apply.

## Related docs

- Measurement lab: `docs/REFINE-RELIABILITY.md`
- Frozen M12A corpus/splits: `Evals/Refine/FROZEN.md`
- Baseline marker: `Evals/Refine/REFINE-V2-BASELINE.md`
- Provider details: `docs/M3B-FOUNDATION-MODELS.md`

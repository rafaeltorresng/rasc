# Refine v2 implementation baseline

Frozen on 2026-09-22 after M12B closeout (M12B-008 integrated gate).

## Baseline identifier

`refine-v2`

Runtime constant: `RefinementImplementationBaseline.identifier`

Prompt version at freeze: `refine-v2-language-preference` (`RefinementPrompt.version`)

## Personalization (M12C)

| Milestone | Status |
|---|---|
| M12C-001 Language Preference | **ACCEPTED** — production |
| M12C-002 Global Preference | **REJECTED** — see `experiments/M12C-002-global-refine-preference/REJECTED.md` |

Git reference: production stack accepted through **M12B-007G**; integrated evidence in **M12B-008**.

## Canonical comparison target

Compare future Refine experiments against:

| Artifact | Path |
|---|---|
| Integrated gate | `experiments/M12B-008-integrated-reliability/` |
| Final stack doc | `experiments/M12B-008-integrated-reliability/final-production-stack.md` |
| M12A corpus baseline-v2 | `reports/baseline-*-v2/` (see `FROZEN.md`) |

## Holdout discipline

M12B-008 ran the frozen M12A holdout **once**. Do not re-tune against holdout or rerun it to chase variance when comparing to `refine-v2`.

## Product contract

See `docs/REFINE-V2.md`.

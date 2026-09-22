# M12B-008 — Integrated Refine reliability gate

## Release decision

**A** — Integrated gate shows net safety improvement vs baseline-v2 with closed M12B guarantees and no new repeatable blocker class.

## Dev vs baseline-v2

Objective pass 0.43005181347150256 → 0.6632124352331606 (Δ 0.23316062176165808)
Critical failures 84 → 40
Harmful edit rate None → 0.43005181347150256

## Validation vs baseline-v2

Objective pass 0.43859649122807015 → 0.543859649122807
Critical failures 25 → 15

See `analysis.json`, `holdout-report.md`, and `final-production-stack.md` for full metrics.

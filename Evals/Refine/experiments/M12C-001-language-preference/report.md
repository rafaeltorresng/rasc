# M12C-001 — Refine language preference

## Decision: **ACCEPT**

## Language preference corpus

- Runs: 25
- Wrong target language: 0
- Protected literal failures: 0
- Selection failures: 0
- noChange rate: 0.32
- Latency p50/p95: 859.243 / 1257.517 ms

## Match note regression vs refine-v2 (M12B-008)

- **dev**: objective Δ -0.0207, critical Δ None
- **validation**: objective Δ 0.0351, critical Δ None
- **regression**: objective Δ 0.0, critical Δ None

See `analysis.json`, `language-preference-policy.md`, and `production-diff.md`.

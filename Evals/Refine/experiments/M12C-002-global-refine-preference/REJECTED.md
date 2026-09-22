# M12C-002 — REJECTED (do not ship)

**Decision:** REJECT  
**Closed:** 2026-09-22  
**Production status:** reverted — not in accepted stack

## Why rejected

Optional global free-text Refine preferences showed useful stylistic influence in eval, but reopened user-visible safety failures:

- wrong-language previews under matchNote
- protected-content corruption reaching preview (money spacing, technical literals)
- increased stochasticity on short/ambiguous inputs

Empty-preference regression vs M12C-001 passed (no causal regression), but non-empty preferences are unsafe for production.

## Do not revive without a new experiment

Do **not** re-enable:

- Settings → Refine preferences UI
- `RefinementRequest.stylePreference` / `<refine_preference>` prompt injection
- prompt version `refine-v2-global-preference`

## Accepted personalization state

| Milestone | Status |
|---|---|
| M12C-001 Refine Language Preference | **ACCEPTED** (production) |
| M12C-002 Global Refine Preference | **REJECTED** (eval record only) |
| M12C-003 one-off instructions | **not started** |

## Preserved artifacts

Historical eval record remains under this directory (`report.md`, `analysis.json`, `challenge-set.jsonl`, `reports/`). These document why the feature was rejected.

Prompt version used in eval: `refine-v2-global-preference` (not current production).

Current production prompt: `refine-v2-language-preference` (M12C-001).

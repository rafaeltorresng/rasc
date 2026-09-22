# M12B-006B — Narrow duplicate-context selection guard

## Hypothesis

M12B-006A found one user-visible selection gap: duplicate-text context imports shorter than the `isReplacementOnly` minimum can reach the user. M12B-006B adds a deterministic guard after existing selection safety checks.

## Scope

Selection scope only. Exact duplicate occurrence matching with alphanumeric boundary policy. No model calls, no fuzzy matching, no holdout.

## Runs

- M12B-006A challenge set (45)
- Critical subset ×5 with `selection-audit-015` promoted
- Existing dev/validation selection cases
- Permanent regression corpus

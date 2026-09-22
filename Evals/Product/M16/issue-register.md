# M16 — Issue register

| ID | Severity | Status | Description |
|---|---|---|---|
| — | — | — | No P0/P1 issues open at acceptance |

## Resolved during implementation

| ID | Severity | Resolution |
|---|---|---|
| M16-001 | P2 | `OverlayStateTests` expected pre-M16 palette list; updated to `availableCommands` context model |
| M16-002 | P2 | HomeView ternary type mismatch (`.primary.opacity` vs `.secondary`); fixed with explicit `Color` types |

## Deferred / out of scope

| Topic | Notes |
|---|---|
| Undo toast for Discard | Not required; existing soft-delete sufficient |
| Dedicated Share keyboard shortcut | Palette + menu only; avoids shortcut conflicts |
| Kept section pagination | Capped at 12 recent; search covers full history |

## Monitoring

Watch for user reports of:

- Keep not clearing active session (session invariant)
- Stale Refine overwriting after completion (contentRevision guards)
- Wrong note receiving completion action (active note ID scoping)

None observed in automated suite at acceptance time.

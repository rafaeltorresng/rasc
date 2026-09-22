# M13A issue register

Severity definitions: P0 data loss/corruption/privacy; P1 core flow broken; P2 meaningful workaround exists; P3 polish.

## P0

_None identified in M13A automation._

## P1

_None confirmed — no automated repro of data loss or wrong-note mutation._

## P2

| ID | Area | Finding | Workaround |
|---|---|---|---|
| P2-001 | Quit | `applicationShouldTerminate` returns success if panel not ready (`panelIfReady() ?? true`) — very early quit may skip flush | Avoid quitting within first second of launch |
| P2-002 | Hide | `PanelController.hide()` aborts hide when flush fails; panel stays visible (data safe) but no alert | User sees scratchpad remain open |
| P2-003 | Bootstrap | DB open failure shows alert but no retry; shortcuts no-op | Relaunch app |

## P3

| ID | Area | Finding |
|---|---|---|
| P3-001 | Refine | ⌘J before bootstrap completes may no-op silently |
| P3-002 | Settings | `SettingsWindowPresentation` retries OpenSettingsAction with short polling |

## Fixed in M13A

| Item | Action |
|---|---|
| M12C-002 global preference | Production reverted; see `Evals/Refine/experiments/M12C-002-global-refine-preference/REJECTED.md` |

## Not in scope (by design)

- Refine quality tuning / new personalization
- External beta feedback
- Broad DI framework for fault injection

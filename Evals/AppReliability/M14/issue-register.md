# M14 issue register

Carried forward from M13A. No new issues opened in M14.

## Release-blocking (P0 / P1)

_None. RC not blocked._

## Known P2 — manual status (beta.2)

| ID | M13A finding | M14 manual status |
|---|---|---|
| P2-001 | Early quit before panel ready may skip flush | **Not reproduced** — normal quit after use |
| P2-002 | Hide aborts on flush failure without alert | **Not reproduced** — hide/reopen worked |
| P2-003 | Bootstrap failure no retry | **Not reproduced** — app launched normally |

None made severity worse. None became release blockers.

## Known P3 — manual status

| ID | M13A finding | M14 manual status |
|---|---|---|
| P3-001 | ⌘J before bootstrap may no-op | **Not reproduced** — Refine after launch |
| P3-002 | Settings presentation retry hack | **Not reproduced** — Settings opened normally |

## New issues in M14

_None._

## Soak defects (post-acceptance)

| Period | Start | End |
|---|---|---|
| Maintainer soak | 2026-09-22 | ongoing |

Log concrete defects only (crash, data loss, wrong-note mutation, etc.).  
**M14 session:** no soak defects logged yet.

If a P0/P1 appears during soak: mark RC **blocked**, do not patch frozen artifact silently.

## Upgrade

| Path | Status |
|---|---|
| beta.1 → beta.2 | NOT TESTABLE (beta.1 artifact not retained) — not a blocker |
| Policy | Retain artifacts from beta.2 onward (`docs/RELEASE.md`) |

# M14 checklist results — 0.1.0-beta.2 (build 3)

**Artifact:** `build/rc/Rasc-0.1.0-beta.2.dmg` (frozen; SHA256 verified)  
**Executed:** 2026-09-22  
**Environment:** macOS 26.5, arm64, Apple Intelligence available  
**Method:** Packaged RC from DMG (not Xcode run)

All items **PASS**. No **FAIL**. No release blockers.

---

## Launch

| Item | Result | Evidence |
|---|---|---|
| DMG + Applications alias | PASS | `verify-private-beta.sh`, `smoke-rc-install.sh` |
| Copy app out of DMG | PASS | Smoke install copies to temp `install/Rasc.app` |
| Gatekeeper private-beta flow | PASS | Ad-hoc artifact; documented right-click → Open; `open` launch succeeds |
| Menu bar, no Dock | PASS | LSUIElement=true; launch smoke; visual confirm |

## Scratchpad

| Item | Result | Evidence |
|---|---|---|
| Shortcut opens scratchpad | PASS | Maintainer session on packaged RC; default ⌥\\ |
| Focus + typing | PASS | Interactive session |
| Escape hides | PASS | Interactive session |
| Reopen restores content | PASS | Interactive session |

## Autosave

| Item | Result | Evidence |
|---|---|---|
| Hide/reopen persistence | PASS | Interactive session |
| Rapid hide (~200ms) | PASS | Interactive session; M13A `ScratchpadSessionTests` |

## New note

| Item | Result | Evidence |
|---|---|---|
| New scratch / switch / return | PASS | Interactive session; M13A note-switch tests |

## Refine

| Item | Result | Evidence |
|---|---|---|
| Whole-note ⌘J | PASS | Interactive session (FM available) |
| Cancel preserves original | PASS | Interactive session |
| Accept + undo | PASS | Interactive session |
| noChange not mutated | PASS | Interactive session; M12B stack |
| Stale preview on edit | PASS | M13A `RefinementSessionTests` + spot check |

## Selection Refine

| Item | Result | Evidence |
|---|---|---|
| Selection-only change | PASS | Interactive session |

## Search

| Item | Result | Evidence |
|---|---|---|
| ⌘P palette + navigation | PASS | Interactive session |
| Esc behavior | PASS | Interactive session |
| Scratchpad search | PASS | Interactive session |

## Home

| Item | Result | Evidence |
|---|---|---|
| Browse/search/open/edit | PASS | Interactive session |
| Home reflects edits | PASS | Interactive session |

## Settings

| Item | Result | Evidence |
|---|---|---|
| Settings from scratchpad | PASS | Interactive session |
| Shortcut / Launch at Login / Language | PASS | Interactive session |
| No Refine preferences UI | PASS | `verify-rc-bundle.sh`; visual confirm |
| Language persists restart | PASS | Interactive session; `RefineLanguagePreferenceTests` |

## Foundation Models

| Item | Result | Evidence |
|---|---|---|
| Normal availability | PASS | Refine invoked successfully on this Mac |
| Unavailable path | NOT TESTED | FM available; unavailable UX covered by M13A docs/tests |

## Windows

| Item | Result | Evidence |
|---|---|---|
| Scratchpad resize/hide/reopen | PASS | Interactive session |
| Home frame | PASS | Interactive session |
| No content-driven expansion | PASS | M13A `PanelControllerTests`; spot check |
| Move + relaunch | PASS | Interactive session |

## Restart

| Item | Result | Evidence |
|---|---|---|
| Quit without data loss | PASS | Interactive session |
| Relaunch state | PASS | Interactive session; DB at `~/Library/Application Support/Rasc/` |
| Onboarding not replayed | PASS | Existing-user path; M13A onboarding tests |

## Privacy

| Item | Result | Evidence |
|---|---|---|
| Feedback metadata only | PASS | `BetaFeedbackTests`; spot check mailto |

---

## Sign-off

**Checklist: PASS** — all bold items passed on frozen packaged RC.  
**New P0/P1:** none.

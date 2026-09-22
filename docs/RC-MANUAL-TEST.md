# RC manual test checklist

~15–20 minutes. Run against the **frozen packaged RC** (`build/rc/Rasc-<version>.dmg`), not Xcode.

Mark each item **PASS** or **FAIL**. Any **FAIL** on a bold item blocks acceptance.

Record results in `Evals/AppReliability/M14/checklist-results.md`.

## Before you start

- Artifact SHA256 matches `build/rc/FROZEN-RC.json`
- Copy `Rasc.app` out of the DMG (do not run only from the mount)
- First open: **right-click → Open** (ad-hoc private beta Gatekeeper flow)
- Note macOS version and Apple Intelligence availability

---

## Launch (~2 min)

- [ ] DMG opens; **Applications** alias present
- [ ] Copy `Rasc.app` to `/Applications` or test folder
- [ ] First launch uses expected Gatekeeper/private-beta flow (no bypass hacks)
- [ ] **Menu bar icon appears; no Dock icon**

## Scratchpad (~2 min)

- [ ] Global shortcut (default **⌥\\**) opens scratchpad
- [ ] **Editor receives focus; typing works immediately**
- [ ] **Escape hides panel**
- [ ] Reopen shortcut — **same note/content restored**

## Autosave (~2 min)

- [ ] Type a line, wait 1s, hide immediately
- [ ] Reopen — **content persisted**
- [ ] Rapid type → hide within ~200ms → reopen — **no loss**

## New note (~2 min)

- [ ] New scratch (⌘N) — blank editor
- [ ] Edit note A; open Home; open note B
- [ ] Return to note A — **correct content**

## Refine (~3 min) — skip FM section if unavailable

- [ ] Whole note: ⌘J → preview or noChange message
- [ ] **Cancel/ESC — original unchanged**
- [ ] Accept useful change — **note updates**; undo restores
- [ ] noChange case — **text not mutated**
- [ ] Edit during loading — **stale preview discarded**

## Selection Refine (~1 min)

- [ ] Select fragment; ⌘J
- [ ] **Only selection changes; surrounding note intact**

## Search (~2 min)

- [ ] ⌘P — filter; arrow keys; **Enter opens correct note**
- [ ] Esc returns correctly
- [ ] Scratchpad search — keyboard navigation works

## Home (~2 min)

- [ ] Open Home; browse/search
- [ ] Open note → edit in scratchpad
- [ ] **Home reflects updated content**

## Settings (~2 min)

- [ ] Open Settings from scratchpad — **editor note unchanged**
- [ ] Shortcut recorder, Launch at Login, **Refine Language** present
- [ ] **No “Refine preferences” field** (M12C-002 rejected)
- [ ] Change language; quit; relaunch — **setting persists**

## Foundation Models (~1 min)

- [ ] If available: Refine runs normally
- [ ] If unavailable: clear message; capture/search/Home still work

## Windows (~2 min)

- [ ] Resize scratchpad; hide/reopen — **frame preserved**
- [ ] Home window opens; move scratchpad; relaunch — **reasonable frame**
- [ ] **Panel does not expand from long note content**

## Restart (~2 min)

- [ ] Quit from menu bar after typing (post-debounce)
- [ ] Relaunch — **notes, active note, settings persist**
- [ ] **Onboarding does not replay incorrectly** for existing user

## Privacy (~1 min)

- [ ] Send Feedback — mail body has version/OS/arch only; **no note text**

---

## Sign-off

| Outcome | Criteria |
|---|---|
| **PASS** | All bold items pass |
| **FAIL** | Any data loss, wrong-note mutation, stale refine accept, or privacy leak |

After PASS, run a short **maintainer soak** (see `Evals/AppReliability/M14/acceptance-report.md`): use the frozen RC daily; log only concrete P0/P1-class defects.

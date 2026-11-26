# Native validation · Phase 1 (#98, #99, #100)

**Date:** 26 Nov 2026. **Machine:** Mac15,6 M3 Pro 18 GB, macOS 26.5.1 (25F80), Xcode 26.2. **Model cannot view screenshots in this session**; native verification is via process state + **Accessibility read-back** + logs + tests, not visual inspection. **Not claiming** physical-key, VoiceOver, focus, Spaces, Stage Manager, multi-monitor, Bluetooth, sleep, or permission-grant verification.

## What was verified natively in the running app (not just tests)

1. **Release app launches.** `Rasc 0.1.16 build 22` (Release, sandboxed, ad-hoc, no updater local) on a backed-up container; process starts; idle; **no crash**; container **restored** from backup afterward. Debug app likewise. (#98/#99/#100 builds all succeed Debug + Release.)
2. **App size / idle resource.** Release `.app` 39 MB; `footprint` **63 MB** physical; RSS ~746 MB @5 s; CPU spike→idle. (see `docs/performance/APP-PERFORMANCE.md`).
3. **Direct text insertion (#100) actually inserts in another app.** Trusted native probe (`AXIsProcessTrusted=true`, `AXUIElementCreateApplication`, `AXFocusedUIElement`, `AXUIElementIsAttributeSettable(AXSelectedText)`, `AXUIElementSetAttributeValue`, then read back `AXValue`):
   - target **TextEdit**, role **`AXTextArea`**;
   - insert `Rasc AX insertion probe 123 — também funciona em português.`;
   - **return true**; **`AXValue` after contains inserted text**; **accents preserved**; `AXIsProcessTrusted` checked.
   This validates `VoiceTextInsertion`'s mechanism. **Rasc itself still needs Accessibility grant to use it; not grantable non-interactively here; not claimed.**
4. **Refine on-device native.** `SystemLanguageModel.default.availability == available`; live smoke passes.
5. **No data loss.** Personal container + non-sandboxed DB backed up + restored; no notes added; `AppReliability*` + persistence tests pass; `Scripts/test-native.sh` checks personal DB unchanged (not runnable here due LaunchServices; logic reviewed).
6. **Screenshot artifact.** `screencapture` produced `docs/audits/2026-11-26-phase1/rasc-release.png` (not visually reviewable in this session; **not** evidence of a11y).

## Automated native + domain (this phase)

- Full domain suite `Scripts/test-domain.py` **passes**; `Scripts/test-native.sh` native listed suites in CI; **Xcode test runner can't launch in this sandbox** (LaunchServices; documented in `Scripts/test-domain.py`); `RascTests/ModifierShortcutTests`, `VoiceCaptureTests`, `HomeSessionTests`, `NoteRepositoryTests`, `NoteExportTests`, `AppReliability*`, `Refine*` **pass**.
- **#98:** `ModifierShortcutTests`; preserve KeyboardShortcuts; conflict; reset. **#99:** batch txn + atomic Undo + export. **#100:** clipboard + insert + fallback + history + no-open + no-focus-steal (synthetic); AX probe (native). 
- **Not verified in sandbox:** physical keys; Accessibility grant; global across apps; app-switch insertion target; VoiceOver; Full Keyboard Access; Spaces/fullscreen/Stage Manager/multi-monitor; Bluetooth; sleep/wake on active capture; mic permission + Sparkle; **native click** (#99); **visual**; **energy**.

## Required manual native checklist (not claimed; run on physical hardware, signed build)

### #98 modifier-only
- [ ] Settings → Voice Capture → **Modifier-only trigger → Record…**; assign **Option**; press **clean Option** once → Listening; again → finish. 
- [ ] **`⌥\`** (Scratchpad), **`⌘⌥\`** (Home), **`⌥`+letter** (diacritic, e.g. `⌥e`, `⌥n`, `⌥u`, `⌥`+`ç`), **`⌥`+`⌘`**, **Ctrl+click**, **Shift+click**, **menu shortcuts**, **`⌘`** chords → **no** capture.
- [ ] Hold Option **>400 ms** → no trigger. Repeat Option doesn't double.
- [ ] **Esc** cancel / capsule close → no stuck modifier; next clean tap works.
- [ ] Works when **Rasc focused** (local) and **another app frontmost** (global) **only after Accessibility granted**; if not trusted, local-only + Settings hint. 
- [ ] No conflict with `⌥\`,`⌘⌥\`, or chord recorder. 
- [ ] **VoiceOver** announces; **Full Keyboard Access** can record/clear; physical keyboard incl non-US layout. 
- [ ] Both `KeyboardShortcuts` chord **and** modifier-only still work. **`fn` not claimed.**

### #99 multi-selection
- [ ] `⌘-click` toggle; `Shift`-click range; `⌘A` all visible (incl filtered); **Esc** clear; **Select** mode; both list + card; ordering same.
- [ ] Batch **Copy** clipboard (clean, ordered); **Export…** folder incl images + no collision + `manifest.json`; **Discard** single-transaction + **Undo** restores all; **Clear**.
- [ ] 0/1 selected → single-note + arrows + Return unaffected. Search filter selection pruned. **VoiceOver** announces count; keyboard-only. **Native click not yet claimed.**

### #100 standalone voice
- [ ] Choose **Clipboard**: dictate; no Scratchpad; no focus steal; clipboard `⌘V`. 
- [ ] Choose **Insert at Cursor**: with **Accessibility granted**, inserts into focused field in **TextEdit / Notes / Safari / Mail / VS Code / Terminal** (note app support); **no keystrokes; no app activation; no Scratchpad**; **app-switch mid-recording** inserts into app frontmost at finish (fallback mem); no target/focused-field → **clipboard + message**; not-granted → **clipboard + Settings**. 
- [ ] **Local history** off default; on saves unfinished; never blocks. 
- [ ] **Mic** permission; **no network inference**; **no audio persisted**; sandbox. **VoiceOver**; **not stealing focus**; **Spaces**. **No synthetic keystrokes.**
- [ ] **Scratchpad** mode unchanged.

## Release gates (unchanged + relevant)

Per `docs/VOICE-CAPTURE.md`. **Microphone consent across Sparkle needs stable signing; no Developer ID.** **Accessibility** grant not retained across ad-hoc rebuilds; use stable identity. **Model delivery** separate. **No telemetry.** **No production claim.**

## Screenshots / demos

Prior native renders exist (`docs/audits/2026-11-13-visual/**`, `docs/validation/**`, Round3 `visual/**`, `Experiments/VoiceCapture/Round3/Study/Build/...mp4`). **Not re-verified; not a11y; Round3 study app not shipping.** New screenshot produced but **not visually reviewable in this session**. **Physical demo not recorded.** Publication-safe **audio + transcription** examples: `Experiments/VoiceCapture/Round4/examples/`.

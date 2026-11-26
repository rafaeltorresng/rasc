# Phase 1 Native Validation Status

**Date:** 2026-11-26
**Baseline:** `main @ d9e88ef` · Rasc `0.1.16 build 22` · Published artifact `v0.1.15 build 21` (separate)
**Environment:** MacBook Pro `Mac15,6` (Apple M3 Pro, 18 GB), macOS `26.5.1` (`25F80`), Xcode `26.2` (`17C52`)
**Scope:** PRs `#101` (`#98`), `#102` (`#99`), `#103` (`#100`), `#104` (eval & evidence)

---

## 1. Automated Verification Run on PR Branches & Integrated Worktree

| Check | Command | Outcome | Notes |
|---|---|---|---|
| **Debug build** | `xcodebuild -project Rasc.xcodeproj -scheme Rasc -configuration Debug -derivedDataPath .derivedData/Rasc CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= build` | **Passed** | Verified on each PR (`#101`–`#104`) and 4-PR integrated worktree |
| **Domain, persistence & reliability suite** | `rm -rf .derivedData/DomainVerification && python3 Scripts/test-domain.py` | **Passed** | Covers Swift Testing suites (`ModifierShortcutTests`, `HomeSessionTests`, `NoteExportTests`, `NoteRepositoryTests`, `VoiceCaptureTests`, Refine guards, etc.) + `AppReliabilityScaleTests` |
| **Release build** | `xcodebuild -project Rasc.xcodeproj -scheme Rasc -configuration Release -derivedDataPath .derivedData/Rasc CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= build` | **Passed** | Verified on each PR (`#101`–`#104`) and 4-PR integrated worktree |
| **Production-binary voice evals (`#104`)** | `Rasc.app/Contents/MacOS/Rasc --run-voice-evals ...` + `score.py` | **Passed (`0` errors)** | `fleurs-60` (`60/60`) and `perturbed-75` (`75/75`, 72 speech + 3 non-speech controls) on installed local Fluid Speech Pro model |
| **`Scripts/test-native.sh`** | `bash Scripts/test-native.sh` | **Failed (script issue)** | Fails in `Copy` build phase: `lstat(.../com.rafaeltorres.rasc.VoiceModelDownloader.xpc): No such file or directory` because passing `PRODUCT_BUNDLE_IDENTIFIER=com.rafaeltorres.rasc.tests` overrides the embedded XPC bundle ID |
| **AppKit / GUI `xcodebuild test`** | `xcodebuild -project Rasc.xcodeproj -scheme Rasc -configuration Debug -derivedDataPath .derivedData/Rasc -destination 'platform=macOS' CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= test` | **Blocked by sandbox** | Builds `Rasc` and `RascTests` cleanly; host launch fails with `IDELaunchErrorDomain Code=20` (`IDELaunchServicesLauncher` error in agent sandbox). Personal databases unchanged. Must pass on GitHub Actions `macos-26` CI / interactive Xcode session |

---

## 2. Manual macOS Interactive Checklist (Pending Verification)

Items below **cannot be verified** in the headless/sandboxed runner and **must be checked manually** on an interactive desktop session before release:

### A. Modifier-only Voice Capture Shortcuts (`#98`, PR `#101`)
- [ ] Single modifier tap (`Option`, `Control`, `Shift`, `Command`) starts and stops Voice Capture within `<= 400 ms` hold window.
- [ ] Holding `> 400 ms`, pressing another key (e.g., `⌥\`, `⌘⌥\`), dead-key diacritic entry (`⌥E + a`, `⌥N + a`), mouse click/scroll, or pressing two modifiers does **not** trigger capture.
- [ ] Pressing `Esc` cancels capture or Settings recorder cleanly without triggering capture on key-up.
- [ ] Existing `KeyboardShortcuts` chord triggers work cleanly alongside or independently of modifier-only shortcuts.
- [ ] Granting Accessibility (`AXIsProcessTrusted`) updates Settings UI reactively on app activation and enables global triggers outside Rasc; denying/revoking leaves in-app triggers working safely.

### B. Home Multi-Selection & Batch Actions (`#99`, PR `#102`)
- [ ] `⌘`-click toggles individual items in both list and grid modes; `Shift`-click selects contiguous visual ranges; `⌘A` selects all displayed notes when Home search is unfocused (and still selects text inside search field when focused).
- [ ] Batch bar (`Copy`, `Export…`, `Discard`, `Clear`) renders legibly in Light and Dark appearances without shifting content width.
- [ ] Single-note Copy preserves rich text / attachment payload; multi-note Copy copies combined text and announces image omission clearly.
- [ ] Multi-note `Export…` creates Markdown files (collision-safe) and image folders via `NoteExportController` / `NoteExportFiles`.
- [ ] Single-transaction `Discard` removes selected notes cleanly, clears stale single-note undo if needed, and `⌘Z` Undo restores all discarded notes atomically (even across kept/unkept view switches).
- [ ] VoiceOver announces selection count, `Shift+Arrow` range extension, and batch discard summary accurately.

### C. Standalone Voice Capture (`#100`, PR `#103`)
- [ ] **Scratchpad (default):** captures thought, saves draft, opens Scratchpad without regressions.
- [ ] **Clipboard:** copies transcript immediately without opening Scratchpad, stealing focus, or saving to Home (unless `"Save standalone transcripts in Rasc"` is explicitly turned on).
- [ ] **Insert at Cursor:** inserts text at cursor via Accessibility `AXSelectedText` into an external editor (e.g., TextEdit, Notes, browser input) with accents preserved and zero synthetic keystrokes; falls back cleanly to Clipboard with persistent `"Copied — press ⌘V"` capsule when AX permission or editable element is unavailable.
- [ ] Menu bar items (`Start Voice Capture`, `Dismiss Voice Capture`) and `Esc` / re-activation work correctly during `.copied`, `.inserted`, and `.copiedFallback`.
- [ ] Window focus, macOS Spaces, Fullscreen, Stage Manager, multiple displays, Bluetooth headset route changes, sleep/wake mid-capture, VoiceOver, Full Keyboard Access, and microphone permission continuity across signed Sparkle updates (TN3127 / Developer ID gate).

---

## 3. Release Gates (Unchanged Policy)

1. AppKit native test host (`xcodebuild test`) passing cleanly on GitHub Actions `macos-26` or local interactive Xcode.
2. Completion of Section 2 manual interactive macOS checklist on a signed build before public release.
3. Developer ID signing + notarization + Sparkle TCC microphone continuity check (external to unmerged PRs; v0.1.15 DMG was ad-hoc).

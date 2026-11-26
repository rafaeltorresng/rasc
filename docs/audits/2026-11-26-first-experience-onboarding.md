# First Experience — Onboarding & Permissions (Issue #80)

**Date:** 2026-11-26  
**Branch:** `feat/first-experience-onboarding` (`main @ 1cee496` baseline)  
**Scope:** Redesign Rasc's first-run onboarding and contextual permission flow while keeping existing data, Dictate defaults, local-first storage, and established-user state intact.

## 1. Isolated baseline walkthrough findings

Inspected on isolated temporary `UserDefaults` + temporary SQLite DB (`OnboardingBehaviorTests` renders in Light & Dark at `720×520`):

1. **Missing content on initial Welcome paint:** `welcomeLoopLine` initialized `welcomeLinesVisible = false`, rendering zero product loop copy synchronously before `.onAppear` animation, and `RascLogo` had no SF Symbol fallback outside the app bundle.
2. **No Skip on Welcome:** Users could only skip after entering step 2 (`Shortcut`), failing HIG's immediate-skippability principle.
3. **Redundant shortcut card (`One shortcut away`):** Displayed `⌥ \` keycaps directly above the `⌥\` unified recorder pill (`ShortcutKeycapView` + `UnifiedShortcutRecorder`), duplicating the exact glyph.
4. **No resume / `Keep` practice:** Exiting live Scratchpad with `Esc` immediately completed practice without demonstrating that the parked draft persisted or teaching `Keep` (`⇧⌘K`) vs leaving thoughts unfinished.
5. **No Voice / Dictate discovery or contextual permission education:** Voice Capture, `Dictate`, Dictate's defaults (`Insert at cursor` + clipboard + local copy), non-blocking speech model download, and contextual Microphone / Accessibility prompts were absent from first-run onboarding.
6. **Non-resizable window & dense completion card:** `OnboardingWindowController` locked `minSize == maxSize == 720×520` without scrolling, while `.completion` stacked 5 command rows.

## 2. Implemented design decisions

- **Adaptive focus selection (`OnboardingFocus`):** On supported Apple silicon + macOS 26 Macs, Welcome defaults to **Scratchpad + Voice & Dictate** while allowing **Scratchpad only**. Unsupported Macs skip both the focus picker and `.voiceSetup` (`3` guided steps instead of `4`).
- **Immediate legibility & zero-trap navigation:** Welcome exposes quiet `Skip`, immediate typography/contrast without opacity-0 delay, `RascLogo` SF Symbol fallback (`note.text`), and clean `UnifiedShortcutRecorder` without duplicated keycaps.
- **2-beat live Scratchpad exercise (`OnboardingCaptureSubstep`):**
  1. **Capture (`waitingForShortcut` → `liveCapture`):** Pressing the global shortcut (or accessible mouse fallback `"Open Scratchpad here"`) opens the real Scratchpad panel with lightweight inline hints (`⌘J` shown only when Refine is available; `Esc` autosaves and parks).
  2. **Resume & Keep (`waitingToResume` → `liveResume`):** Returning shows `"Parked — and still saved."` Reopening via shortcut or `"Open again"` calls `PanelController.reopenCurrentScratchForOnboarding()` with the user's exact fragment preserved and teaches `Keep` (`⇧⌘K`, copper accent) vs `Esc` (`"Leave unfinished"`).
- **Non-blocking Voice & Dictate onboarding (`.voiceSetup`):**
  - Clear two-row separation between **Voice to Scratchpad** and **Dictate**, preserving Dictate defaults (`Insert at cursor`, `Also keep on clipboard = true`, `Save a copy in Rasc = true`) and communicating them inline.
  - Enabling Voice triggers model download asynchronously; `Continue` and `Set up later` are always enabled.
  - Permissions are strictly contextual and optional: Microphone prompt appears only when Voice is enabled and unauthorized; Accessibility prompt appears only when the user assigns a Dictate shortcut (with cursor insertion) or a single-modifier shortcut without AX trust.
  - When Voice is ready (`setup == .installed`, Mic authorized, Dictate shortcut assigned), an inline `"Try Dictate here"` field allows live dictation rehearsal.
- **Responsive sizing & safe replay (`Welcome Guide…`):** `OnboardingWindowController` supports resizing down to `560×480` with vertical `ScrollView` wrapping; Settings → General → `About & Privacy` exposes `Welcome Guide…` via `OnboardingCoordinator.replayOnboarding()`, preserving all existing notes, shortcuts, and Voice/Dictate settings.

## 3. Adaptive matrix

| Mac / user state | Welcome choice | Guided steps | Speech model setup | Microphone prompt | Accessibility prompt |
|---|---|---|---|---|---|
| Voice unsupported (Intel / macOS < 26) | Hidden (`scratchpadOnly`) | 3 (`Shortcut` → `Capture/Resume` → `Done`) | Omitted | Omitted | Only if toggle shortcut is single-modifier without AX |
| Voice supported + `Scratchpad only` | User picks `Scratchpad only` | 3 | Omitted | Omitted | Only if toggle shortcut is single-modifier without AX |
| Voice supported + `Scratchpad + Voice & Dictate` | Default choice | 4 (`...` → `Voice & Dictate` → `Done`) | Async/non-blocking download or `Ready` | When Voice enabled & `.notDetermined`/denied | Only when Dictate shortcut set (`.insertAtCursor`) or single-modifier trigger without AX |
| Replay from Settings | Shown with current environment | Full 3 or 4 steps preserving existing data/prefs | Reflects installed/downloading state | Reflects live `AVCaptureDevice` status | Reflects live `AXIsProcessTrusted()` |

## 4. Consolidation review refinements (2026-11-26)

1. **One-click async model download (`VoiceCapture.enableAndDownloadIfMissing()`):** Fixed race where `enableVoiceSetup()` saw `setup == .unchecked` while `checkSetup(prepare: true)` was still running asynchronously; clicking **Enable Voice** now transitions `.unchecked → .missing → .downloading` without extra clicks or blocking onboarding completion.
2. **Non-destructive Welcome Guide replay (`isReplaying`) + `NSWindowDelegate` close handling:** `replayOnboarding()` no longer calls `resetOnboardingStateOnly()`, preserving `isCompleted`, `migrationApplied`, `historyHintDismissed`, `homeVisitCount`, shortcuts, notes, and Voice/Dictate preferences across full step-by-step replay or `×` window close (`dismissByWindowClose()`). Closing releases `contentViewController` cleanly.
3. **Resuming incomplete setup mid-`.voiceSetup`:** `restorePersistedState()` triggers `voiceCapture.checkSetup(prepare: true)` when resuming at `.voiceSetup` with Voice already enabled.
4. **Denied Microphone & Accessibility recovery UX:** `OnboardingEnvironment` now preserves `AVAuthorizationStatus` (`isMicrophoneDenied`); denied/restricted Microphone states direct cleanly to `"Open Microphone Settings…"` instead of invoking a no-op OS prompt, Accessibility rows expose a secondary `"Settings…"` action, and environment checks refresh on both `didBecomeActive` and `didBecomeKey`.
5. **Working inline `"Try Dictate here"` insertion (`VoiceTextInsertion.insertIntoWindowEditor`):** Dictation triggered while Rasc itself is focused inserts directly into the editable `keyWindow` field editor while keeping external `VoiceTextInsertion.insert` guarantees, clipboard copy, and local Rasc history intact.
6. **Keyboard focus, dynamic shortcuts & VoiceOver:** `completionSubtitle` reflects customized `Keep` shortcuts dynamically (`InternalShortcutStore`), `@FocusState` tracks step CTAs without overriding global-shortcut yield windows, and `RascAccessibility.announce` announces step changes.
7. **Injected store propagation (`UnifiedShortcutRecorder` / `UnifiedShortcutRow`):** Parameterized `store: GlobalShortcutStore = .shared` so onboarding previews and isolated tests display injected shortcut triggers consistently.

## 5. Verification status

- **Automated domain, AppKit text/snapshot & Release build verification:**
  - `python3 Scripts/test-domain.py`: `OnboardingEligibilityTests`, `OnboardingStoreTests`, `OnboardingBehaviorTests` (1-click Voice download race, denied mic + System Settings path, mid-`.voiceSetup` resume, dynamic Keep copy, non-destructive Welcome Guide replay + `×` close), `VoiceCaptureTests` (in-app Dictate key-window editor insertion), plus Light/Dark/narrow PNG renders (`onboarding-v2-*` including denied-mic & ready-to-dictate states visually inspected).
  - Combined Debug `build-for-testing` and Release `build` cleanly compile with `#if DEBUG` gating on `restoreVoiceSetupForTest()`.
- **Isolated Release `.app` native checks (see Phase 4 record):** Verified fresh first launch, incomplete setup resume, and established-user silence in sandboxed isolated container `com.rafaeltorres.rasc.onboardingtest` without touching personal SQLite databases.
- **Manual macOS checks still requiring interactive desktop testing:** Physical modifier key taps across external apps, live `FluidAudio` physical microphone / Bluetooth audio routing, OS interactive TCC prompts for Microphone & Accessibility, external-app `AXSelectedText` insertion, fullscreen Spaces/multi-monitor focus, and live VoiceOver navigation.

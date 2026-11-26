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

## 4. Verification status

- **Automated unit & snapshot checks (`python3 Scripts/test-domain.py`):** Verified `OnboardingEligibilityTests`, `OnboardingStoreTests`, and `OnboardingBehaviorTests` (adaptive unsupported-Mac flow, 2-beat capture/resume/Keep loop, async non-blocking Voice model download, Dictate default preservation, safe Settings replay, and Light/Dark + `560×480` narrow PNG renders inspected visually).
- **Manual macOS checks pending outside sandbox:** Live physical global hotkey + Beat 2 Scratchpad reopen with OS focus handoff, live `FluidAudio` microphone rehearsal in `"Try Dictate here"`, TCC dialogs for Microphone & Accessibility, and VoiceOver traversal on live windows.

# Native UI acceptance checklist

Run `bash Scripts/test-native.sh` (which sets `RASC_APP_BUNDLE_IDENTIFIER=com.rafaeltorres.rasc.testhost`
on an unlocked macOS desktop session or GitHub Actions `macos-26` CI runner) before claiming
automated AppKit coverage, then run this manual checklist against the exact candidate app/artifact.
Record version/build, SHA256, macOS/hardware, date and results. An unchecked item is **not verified**.
Use synthetic thoughts and a temporary test account/profile when exercising failure cases.

## Window and focus

- [ ] Invoke receives editor focus immediately; typing goes into Rasc.
- [ ] Esc hides and restores the same unfinished thought; Keep starts fresh.
- [ ] Home, Search, palette and Settings restore the correct focus when closed.
- [ ] Check default/minimum Scratchpad (720×440 / 560×320) and Home (1000×680 / 760×520).
- [ ] Verify fullscreen, Spaces, Stage Manager, multiple monitors and return to the original work app.
- [ ] Verify macOS 14/15 fallback and macOS 26 materials; modal/security windows remain usable.

## Home and recovery

- [ ] Arrow keys move selection through the chronological note list, including across Kept/temporal section boundaries; there is no horizontal grid flow.
- [ ] In the card view, arrow keys move by cell across columns and rows, clamp at edges, and there is no wrap; the toggle keeps search, ordering and selection consistent with the list.
- [ ] The view chosen in Home persists across relaunches; rows/cards keep identical actions, context menu and Kept affordances.
- [ ] Search field keeps normal caret editing; Down/Return transfers to results.
- [ ] With 13 and 50 Kept thoughts, Show all and Show fewer provide access without a search term.
- [ ] Selected rows stay visible without gratuitous scrolling; clicking blank list space does not draw stray focus-ring lines.
- [ ] Discard/Undo restores text, Kept and dates in Home and Scratchpad.
- [ ] Undo while writing a new thought leaves the new text intact.
- [ ] A failed write gives actionable feedback (`Retry`, `Reveal Data Folder`, `Quit Rasc`), preserves content and can be retried; **Back Up Database…** creates a readable snapshot without quitting.
- [ ] Batch discarding more than 10 notes in Home shows a confirmation dialog before deleting.

## Export

- [ ] Export text and a mixed thought from Scratchpad and both Home views. Open the
  Markdown with the export folder in a new location and inspect image placement.
- [ ] Check Kept, All and Selected from the Rasc menu. Search in Selected and
  verify previously checked thoughts remain selected. Verify discarded thoughts
  and refinement history stay out of the files.
- [ ] Confirm a system save panel writes to a chosen external location using the
  release sandbox. Check an existing filename, repeat a folder export, and cancel
  the picker and the save dialog. Verify focus returns to the source window.
- [ ] Check the picker, checkboxes, count, confirmation and retry messages with
  VoiceOver and Full Keyboard Access in light and dark appearances.

## Refine and retrieval

- [ ] Whole-note/selection preview: Suggested, Changes (word-level strike/underline) and Original all render; selection context is preserved; Esc/Return grammar is unchanged; Reduce Motion falls back to instant transitions.
- [ ] Home opens with the search field focused (typing works immediately); Down or Return transfers to results; arrows move selection in both views; reopening Home behaves the same.
- [ ] Refine preview: Left/Right cycles Suggested → Changes → Original (clamped); Return accepts; Esc uses the original; the editor's arrow keys are unaffected.
- [ ] Use original/Esc preserves original; Accept and Undo persist the expected content.
- [ ] Late/cancelled/stale results cannot replace edited text.
- [ ] Long/unsupported/disabled/preparing/error messages fit at 560 px and stay readable.
- [ ] Save errors remain visible during onboarding.
- [ ] Search finds terms late in a paragraph; snippets show match context and truncation is explained.
- [ ] macOS <26 explains Refine's requirement while Capture/Keep work.

## Accessibility and appearance

- [ ] Light/dark: inspect typography, actions, borders, icon and menu-bar symbol.
- [ ] Theme presets (Graphite Paper / Slate / Porcelain) repaint Home, Scratchpad and Settings immediately and uniformly, preserve copper-for-Keep and readable contrast, and Restore Default Theme selects System and Graphite Paper.
- [ ] Custom at minimum Settings width: edit and preview both variants with the native color panel, reject insufficient contrast with a visible explanation, then apply and relaunch. Switching presets and restoring the default theme preserves the saved Custom colors. Reset Palette restores both variants.
- [ ] Apply themes and change Note Text Size with a note open, preserving undo, selection, and scroll context. At minimum Home and Scratchpad sizes, check Small and Large with long notes, lists, Search matches, and all Refine comparison modes.
- [ ] Each preset under Increase Contrast renders with the strengthened borders, and the unmodified copper pair still reads correctly.
- [ ] VoiceOver announces preview/errors and can complete Capture → Accept/Keep → retrieval.
- [ ] Full Keyboard Access reaches note rows, action menus, Undo, comparison and Settings.
- [ ] Reduce Motion preserves state without loops; Reduce Transparency preserves readable surfaces.
- [ ] Increase Contrast strengthens focus/borders; larger text/display scaling has no clipped essential copy.
- [ ] Onboarding explains Keep versus Esc without requiring Refine.

## Distribution and energy

- [ ] Release updater builds embedding `Sparkle.framework` and `libswiftCompatibilitySpan.dylib` launch cleanly on macOS 14/15 as well as macOS 26 (confirming LLC pins cover all `Contents/Frameworks/` binaries), and `VoiceModelDownloader.xpc` downloads inside the sandbox cleanly.
- [ ] Dictate insertion via `AXSelectedText` and the verified `AXValue` fallback (AppKit, SwiftUI, Chromium/Electron and code editors), Secure Input refusal, and physical 2-minute / Bluetooth / external mic captures succeed without leaks or focus theft.
- [ ] Dictate never steals focus: the onboarding **Try Dictate here** field keeps its caret through start, recording and delivery, and an external app stays active throughout.
- [ ] A transcript never lands in an app that gained focus after recording began; the capsule names the actual fallback reason, and **Allow…** appears only while this exact build lacks Accessibility.
- [ ] Packaged app matches the source revision, version and build; previously published artifacts remain unchanged.
- [ ] Verify the published checksum, sandbox and signing status; record notarization only when a notarized build is claimed. Test ordinary first-install and upgrade paths.
- [ ] Inspect icon at Finder/DMG sizes and bundled dependency notices.
- [ ] Profile idle/hidden windows and visible windows for CPU/energy; record actual measurements.

Domain tests (`608` tests / `49` suites + `AppReliabilityScaleTests`), `116` automated AppKit
window tests (`16` suites in `Scripts/test-native.sh`), `38` Light/Dark offscreen UI
snapshot checks (`docs/evidence/screenshots/`), and successful Release/RC builds do not mark
these physical desktop interaction checks as passed. Record the actual signing and
notarization status of each candidate (`0.1.16-final-rc` build 22 is ad-hoc signed with LLC
and unnotarized). Ad-hoc builds use the documented **Open Anyway** path in
[INSTALL-UNSIGNED.md](INSTALL-UNSIGNED.md); notarization is not required for them.

## Independent reliability candidate pass

Build 25 passed all 613 domain tests and the scale suite. The full Xcode run
passed 660 of 665 tests. The five failures involved Home focus, orb visibility,
Refine preview navigation and Command-W. The same five failed on the baseline
with the display locked. The cases below still require a live desktop pass.

1. **Install and isolate.** Verify the DMG checksum and open the candidate from a separate folder. Confirm About shows **0.1.16 (25)** and Home starts empty. Import the model or opt into the download. Close the normal app while trying global shortcuts.
2. **Record through the cap.** With Wi-Fi off after setup, record in English, Brazilian Portuguese and mixed PT/EN. Include an audible quiet passage after a louder one, a pause, and distinctive phrases just before and after the last-15-second warning. Check that Capture stops at 2:00, delivers the last phrase before the cap, preserves order, and has no repeated or missing sentences. Repeat with a USB or Bluetooth mic.
3. **Check delivery.** Try Scratchpad, Dictate into TextEdit and an Electron field, then Dictate with no editable focus or under Secure Input. Check one delivery, expected clipboard fallback or refusal, and expected focus. Cancel a long capture and check that nothing is inserted.
4. **Check Refine.** Refine a direct question, a drafting command and a messy task list. Test a selected fragment and one fixed-target translation. Verify that the questions and commands remain drafts, ordinary edits still help, and Original, Esc and Undo preserve the text.
5. **Record failures with context.** Note the candidate build, macOS, mic and route, elapsed time, and the first/last missing words from a reproducible non-private sample.

## Focused UX / Dictate / geometry pass (build 28)

The focused fixes changed first-run shortcuts (`⌘\` for Voice to Scratchpad,
`⌥` for Dictate), onboarding stability, compact Scratchpad geometry, insertion
target guards and fallback feedback. Automated coverage includes the full Xcode
suite, `Scripts/test-domain.py`, and Light/Dark offscreen onboarding renders.
These still need a physical desktop pass:

1. **Onboarding focus.** Build 28 has its own bundle and container, so a plain
   launch starts at the welcome step. Focus **Try Dictate here**, press
   `⌥`, speak and confirm the caret stays in that field and the text lands there
   exactly once. Verify the progress dots stay centered on every step and the
   window does not resize during the normal flow; resize down on a small display
   and confirm scrolling remains available.
2. **Shortcut defaults and conflicts.** Confirm the two new defaults appear for
   a fresh install, that each can be changed or cleared in onboarding, and that
   an existing profile (including previously cleared shortcuts) is unchanged.
   Grant Accessibility for this build if the one-key trigger is used.
3. **External Dictate.** From TextEdit, Chrome/Electron and a code editor, tap
   `⌥`, speak and confirm insertion at the caret with no focus change. Then
   switch apps mid-recording and confirm the text is copied, not inserted into
   the newly focused app. Check Secure Input still refuses without copying.
4. **Accessibility honesty.** With an isolated ad-hoc RC running alongside the
   distributed app, confirm **Allow…** appears only when `AXIsProcessTrusted()`
   is false for this build. If the macOS prompt is suppressed because an older
   Rasc entry exists, the action must open Accessibility exactly once and show
   the bundle path to add with **+** after removing the old entry. Confirm the
   capsule title changes to **Add this build in Accessibility**, that returning
   with this build granted clears the guidance, and that onboarding and
   Settings → Voice show the same instructions.
5. **Geometry and appearance.** Check the compact Scratchpad (600 × 350), Home,
   Onboarding, Quick Search, Command Palette, Refine and the Voice HUD in Light
   and Dark, on the active screen, across Spaces and with a fullscreen app.

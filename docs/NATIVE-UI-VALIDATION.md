# Native UI acceptance checklist

Run against the exact candidate app/artifact. Record version/build, SHA256,
macOS/hardware, date and results. An unchecked item is **not verified**.
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
- [ ] A failed write gives actionable feedback, preserves content and can be retried.

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

- [ ] Packaged app matches the source revision, version and build; previously published artifacts remain unchanged.
- [ ] Verify the published checksum, sandbox and signing status; record notarization only when a notarized build is claimed. Test ordinary first-install and upgrade paths.
- [ ] Inspect icon at Finder/DMG sizes and bundled dependency notices.
- [ ] Profile idle/hidden windows and visible windows for CPU/energy; record actual measurements.

Domain tests, headless layout captures and successful builds do not mark these native
interaction checks as passed. Record the actual signing and notarization status of each
candidate. Ad-hoc builds use the documented **Open Anyway** path in
[INSTALL-UNSIGNED.md](INSTALL-UNSIGNED.md); notarization is not required for them.

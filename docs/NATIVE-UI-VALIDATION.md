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

- [ ] Grid arrows follow 1–4 columns, short rows and Kept/temporal section boundaries.
- [ ] Search field keeps normal caret editing; Down/Return transfers to results.
- [ ] With 13 and 50 Kept thoughts, Show all and Show fewer provide access without a search term.
- [ ] Hover does not reflow card titles; selected cards stay visible without gratuitous scrolling.
- [ ] Discard/Undo restores text, Kept and dates in Home and Scratchpad.
- [ ] Undo while writing a new thought leaves the new text intact.
- [ ] A failed write gives actionable feedback, preserves content and can be retried.

## Refine and retrieval

- [ ] Whole-note/selection preview: compare Suggested and Original; selection context is preserved.
- [ ] Keep original/Esc preserves original; Accept and Undo persist the expected content.
- [ ] Late/cancelled/stale results cannot replace edited text.
- [ ] Long/unsupported/disabled/preparing/error messages fit at 560 px and stay readable.
- [ ] Save errors remain visible during onboarding.
- [ ] Search finds terms late in a paragraph; snippets show match context and truncation is explained.
- [ ] macOS <26 explains Refine's requirement while Capture/Keep work.

## Accessibility and appearance

- [ ] Light/dark: inspect typography, actions, borders, icon and menu-bar symbol.
- [ ] VoiceOver announces preview/errors and can complete Capture → Accept/Keep → retrieval.
- [ ] Full Keyboard Access reaches cards, action menus, Undo, comparison and Settings.
- [ ] Reduce Motion preserves state without loops; Reduce Transparency preserves readable surfaces.
- [ ] Increase Contrast strengthens focus/borders; larger text/display scaling has no clipped essential copy.
- [ ] Onboarding explains Keep versus Esc without requiring Refine.

## Distribution and energy

- [ ] Packaged app matches source/version; original beta.3 artifact is unchanged.
- [ ] Verify checksum, sandbox, signing and notarization status; test ordinary first-install and upgrade paths.
- [ ] Inspect icon at Finder/DMG sizes and bundled dependency notices.
- [ ] Profile idle/hidden windows and multiple visible Orbs for CPU/energy; record actual measurements.

Domain tests, headless layout captures and successful builds do not mark these native
interaction checks as passed. Developer ID/notarization and maintainer review of
historical corpus provenance remain gates before public distribution/publication.

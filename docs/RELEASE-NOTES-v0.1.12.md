# Rasc 0.1.12

Version: 0.1.12 · build 18 · Apple silicon · macOS 14+

Status: **in preparation, not published.** No DMG, checksum, tag, GitHub Release,
or appcast entry exists for this version yet. The published release remains
[v0.1.11, build 17](RELEASE-NOTES-v0.1.11.md). Do not treat the version fields in
`project.pbxproj` as proof of a published artifact.

Behavioral source tip for this candidate: `6bdd410` (merge of PR #91, including
the main-branch test-hardening commit `65228f6`). The release-preparation commits
that follow only bump the version and update documentation.

## What's new since 0.1.11

### Refine preview (PR #88, with state primitives in #85)

- The preview now has three tabs: **Suggested** (default), **Changes** and
  **Original**. Plain Left/Right arrows cycle Suggested → Changes → Original and
  clamp at the ends; Return accepts, Esc uses the original. The segmented picker
  is bypassed at the window level so arrows cannot be swallowed by the control
  or by text selection.
- **Changes** is a word-level diff: removed words are struck through in secondary
  text, added words are bold and underlined in primary ink, with a `· N changes`
  counter in the header. The diff is computed once per refinement and shared by
  the view, the counter and VoiceOver's label. Text selection is disabled in this
  tab only, so copying cannot mix the original and suggested text.
- No copper is used in the diff; copper remains exclusive to Keep/Kept.

### Search-match highlighting (PRs #85 and #87)

- Query matches are marked with a neutral background in Home rows and cards,
  Quick Search titles/snippets, and command-palette command names. The text color
  is never replaced, so contrast and VoiceOver reading stay intact.
- Matching is case/diacritic/width-folded; Home and Quick Search mark token starts
  to mirror FTS5 prefix behavior, while the substring-filtered palette marks
  matches anywhere. Increase Contrast uses a stronger mark.

### Theme presets (PRs #85 and #86)

- Settings → Theme Style adds three curated presets on top of System / Rasc Light
  / Rasc Dark: **Graphite Paper** (default, the existing palette), **Slate** (cool
  blue-gray) and **Porcelain** (true neutral, crisper contrast), with swatch
  previews and a reset button. Reset restores System appearance with Graphite Paper.
- Presets vary canvases, fills, borders, focus and neutral text opacities only;
  the Keep/Kept copper pair and destructive red are invariant. The Home, Scratchpad
  and Settings subtree roots rebuild on a preset change. This is deliberate but
  drops transient view state — the Scratchpad editor loses its undo stack and
  scroll position — recorded in `docs/DESIGN-SYSTEM.md`.

### Home cards view (PR #89)

- The header has a List/Cards toggle; the choice persists and defaults to the
  compact list. Cards show a multi-line excerpt with the same ordering, search,
  actions, context menu, selection semantics and keyboard navigation as rows.
  Arrow keys move by cell across columns with no wrap; the measured column count
  drives both the grid and keyboard movement so they cannot disagree.
- Home still opens with the **search field focused** (the behavior restored in
  `04292a2` and covered by `HomeWindowControllerTests`); Down or Return transfers
  focus to results. This was kept deliberately when the cards PR landed.

### Caret and polish (PRs #90 and #91)

- Opening a note that already has text now places the caret at the **end** of the
  note, so typing continues instead of inserting at the start. Explicit
  selection-Refine ranges and image-import carets still take precedence.
- Image attachments gained a 1 px neutral hairline (pure black at 10% in light,
  pure white at 10% in dark). Small controls use a wider hit area, dynamic numbers
  use monospaced digits, onboarding headlines are unified at 24 pt, the keycap
  press spring is retuned without overshoot, and the onboarding empty-hint and
  keycap animations respect Reduce Motion.
- Docs were aligned: README, Current Product, Design System, Data and Privacy,
  and the native-validation checklist now describe the behavior above.

## Updating

Once published, v0.1.7 through v0.1.11 users will be able to use **Check for
Updates…** in the Rasc or app menu. Updates are manual; nothing is downloaded
silently. Earlier builds without an updater require a one-time manual
replacement. Until publication, no feed entry or download exists.

## Verification so far

- `xcodebuild build` and `build-for-testing`: succeeded on the candidate tip.
- Local fallback suite (`Scripts/test-domain.py`): **481 tests in 44 suites**
  passed plus the separate scale benchmark; this includes the new caret,
  word-diff, search-highlight, theme, Home-view-mode and preview-mode suites.
- CI full native test suite: passed on the main tree `65228f6` (523 tests) and
  on the merged candidate tip `6bdd410` — GitHub Actions run `44660349934`,
  both `macos` checks green. Record the run URL in the publication provenance.
- Snapshot harness renders reviewed: Home list/cards in light and dark, search
  highlighting, command palette, Settings theme section, Refine Suggested and
  Changes tabs in light and dark, and the image attachment outline.

## Before publishing (do not skip)

- Confirm CI run `44660349934` above is green (it is at the time of writing);
  record its URL in the publication provenance.
- Follow [SPARKLE-RELEASE.md](SPARKLE-RELEASE.md) and [RELEASE.md](RELEASE.md)
  to build and verify the ad-hoc updater DMG with a valid Library Load
  Constraint, then retain artifact, checksum and manifest.
- Add the exact DMG name, SHA-256 and delta list, source commit, tag, and
  appcast verification to this file *after* producing them. Do not invent or
  reuse v0.1.11 provenance.
- Run the clean-machine and upgrade checks from the runbook, including an
  upgrade from v0.1.11 with a representative database.
- Complete the manual platform checks in [NATIVE-UI-VALIDATION.md](NATIVE-UI-VALIDATION.md):
  window focus and Spaces/fullscreen, VoiceOver, Increase Contrast, Reduce Motion
  and Reduce Transparency. None of these are claimed as verified here.

## Not verified

VoiceOver, Full Keyboard Access, Reduce Motion/Transparency, Spaces/fullscreen,
macOS 14–25, clean install and in-app upgrade for this candidate remain
unverified until the release build and manual pass are complete.

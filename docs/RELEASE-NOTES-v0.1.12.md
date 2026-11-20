# Rasc 0.1.12

Version: 0.1.12 · build 18 · Apple silicon · macOS 14+

Status: **published 2026-11-20** as an ad-hoc signed, unnotarized
[GitHub Release](https://github.com/rafaeltorresng/rasc/releases/tag/v0.1.12).
Behavioral source tip: `6bdd410` (merge of PR #91, including the main-branch
test-hardening commit `65228f6`); merged release-preparation commit: `bded574`.
The previous published release is [v0.1.11, build 17](RELEASE-NOTES-v0.1.11.md).

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

v0.1.7 through v0.1.11 users can use **Check for Updates…** in the Rasc or app
menu. Updates are manual; nothing is downloaded silently. Earlier builds without
an updater require a one-time manual replacement. First-time manual installs of
the ad-hoc build use **Open Anyway** in Finder.

## Verification so far

- `xcodebuild build` and `build-for-testing`: succeeded on the candidate tip.
- Local fallback suite (`Scripts/test-domain.py`): **481 tests in 44 suites**
  passed plus the separate scale benchmark; this includes the new caret,
  word-diff, search-highlight, theme, Home-view-mode and preview-mode suites.
- CI full native test suite: passed on the main tree `65228f6` (523 tests) and
  on the merged candidate tip `6bdd410` (GitHub Actions run `44660349934`,
  both `macos` checks green). PR #92 (release prep) passed both `macos` checks
  (runs `44661382700` and `44661417344`).
- Snapshot harness renders reviewed: Home list/cards in light and dark, search
  highlighting, command palette, Settings theme section, Refine Suggested and
  Changes tabs in light and dark, and the image attachment outline.

## Build provenance

- DMG: `Rasc-0.1.12-updater.dmg`, SHA-256
  `64637dc077e9f882a2154ea3d710bf76ab23687738fef6f2e2c7148ccfa0805c`
  (6,293,028 bytes). The `.sha256` sidecar is attached to the GitHub Release.
- Deltas: `Rasc18-17.delta`, `Rasc18-16.delta`, `Rasc18-15.delta`,
  `Rasc18-14.delta`, `Rasc18-13.delta` — all attached to the release.
- Signature: ad-hoc, Hardened Runtime, App Sandbox, no network entitlement on
  the main app, with a Library Load Constraint pinning the final signed
  Sparkle binary (`CDHash=4607d4484fb9c9302f729a9b328318f9e19f8d90`, arm64).
  `codesign --verify --deep --strict` passed and the app reported
  `Has Library Load Constraints`; `spctl --assess` rejects it as expected for
  an ad-hoc build (first manual installs use Open Anyway). Not notarized.
- The packaged `SUPublicEDKey` matches the value from the `rasc-sparkle`
  login-keychain account.
- Sparkle appcast: all six entries (0.1.7–0.1.12) were verified for lengths and
  Ed25519 signatures with `verify-appcast.py --account rasc-sparkle`, including
  a tamper-rejection check (one byte flipped at offset 1024) that passed. The
  existing v0.1.7–v0.1.11 entries keep their original URLs and signatures.

## Release verification

- Appcast verification re-run against assets re-downloaded from the public
  v0.1.12 GitHub Release; record result and live-feed check here after deploy.
- The live production appcast and download link were updated after the release
  assets were verified (see `rasc-web` commit recorded in the publication log).

## Not verified

VoiceOver, Full Keyboard Access, Reduce Motion/Transparency, Spaces/fullscreen,
macOS 14–25, clean-machine install and the in-app upgrade from v0.1.11 with a
representative database have **not** been performed by the publishing agent.
The runbook's clean-machine pass remains a maintainer action; publication was
completed at the maintainer's explicit instruction. Do not interpret this
release as certified on those axes.

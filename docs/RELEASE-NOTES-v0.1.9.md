# Rasc 0.1.9

Version: 0.1.9 · build 15 · Apple silicon · macOS 14+

Status: **published 2026-11-17** as an ad-hoc signed, unnotarized
[GitHub Release](https://github.com/rafaeltorresng/rasc/releases/tag/v0.1.9).
Build provenance is final. See [SPARKLE-RELEASE.md](SPARKLE-RELEASE.md) for the
publication checklist and feed details.

## What's new

- Scratchpad has a quieter layout without the Thinking Orb. Refine previews use the same reading position and make Suggested and Original easier to compare.
- Home keeps notes in a readable column, restores search focus on return, and makes it easier to clear a search. Quick Search and Command Palette also offer clear controls.
- Graphite Paper replaces violet-tinted surfaces and focus accents with warm paper and neutral graphite. Copper remains reserved for Keep and Kept.
- Onboarding and shortcut guidance make it clearer that Refine is optional and distinguish **Use original** from **Keep**.
- Refine's safeguards better preserve explicit uncertainty in suggestions. Refine remains optional and requires explicit acceptance; the separate missing “maybe” finding remains under investigation in [#48](https://github.com/rafaeltorresng/rasc/issues/48).
- Documentation now distinguishes current source, the published release, and historical evidence.

## Updating

If you have **v0.1.7** or **v0.1.8**, use **Check for Updates…** in the Rasc or
app menu. Nothing is downloaded or installed silently. Earlier builds without an
updater require a one-time manual replacement. Capture, autosave, Keep and
retrieval work without Refine; Refine requires macOS 26 and available Apple
Intelligence.

## Build provenance

- Source: `8fae4fd` on `main` (merge of PR #82), built with
  `Scripts/release/build-updater-rc.sh`.
- DMG: `Rasc-0.1.9-updater.dmg`, 6,137,426 bytes, SHA-256
  `97c0527a20c8da0faab58885c38af41683cb90c3debba1cdd791b09d00a9912d`.
- Deltas: `Rasc15-14.delta` and `Rasc15-13.delta`, generated from the final DMG.
- Signature: ad-hoc, Hardened Runtime, App Sandbox, no network entitlement on
  the main app, and a Library Load Constraint pinning the shipped
  `Sparkle.framework` cdhash. Not notarized; Gatekeeper rejection is expected on
  a first manual install (use Open Anyway).

## Release verification

- CI on the release PR passed the `macos` check (two successful runs). The
  full Xcode suite passed 477 tests in 44 suites earlier in this pass with the
  normal bundle identifier.
- Final DMG, delta lengths, Ed25519 signatures and tamper rejection were
  verified with `verify-appcast.py`; **RESULT: PASS**. Previous v0.1.7 and v0.1.8
  enclosures remain byte-identical to their published artifacts.
- Native validation (macOS 26.5.1, Apple M3 Pro, 2026-11-17): the candidate
  launched, Escape hid Scratchpad, and Home and Settings were inspected visually
  in dark mode. An installed 0.1.8 was upgraded in-app through Sparkle using a
  local feed: 0.1.9 was offered, `Rasc15-14.delta` downloaded, **Install and
  Relaunch** completed, and the app relaunched as 0.1.9/build 15. Notes (16),
  `appTheme=rascDark`, and the global Scratchpad shortcut (`⌥\`) were unchanged.
  The installed app carried a valid Library Load Constraint, passed
  `codesign --verify --deep --strict`, had Sparkle mapped, and was
  Gatekeeper-rejected as expected for an ad-hoc build. The local feed override
  was removed after the check.
- **Not verified in this pass:** clean install from the published DMG, tamper
  rejection through the live UI, light mode and narrow-window checks, VoiceOver,
  Reduce Motion, and updater behavior on macOS 14–25. These are recorded as
  open, not passed.

The production appcast at `https://rasc.app/appcast.xml` serves versioned GitHub
Release assets; verify the deployed enclosure URLs against this release before
announcing it.

Follow [SPARKLE-RELEASE.md](SPARKLE-RELEASE.md) and
[NATIVE-UI-VALIDATION.md](NATIVE-UI-VALIDATION.md). Do not interpret an unchecked
item as a pass.

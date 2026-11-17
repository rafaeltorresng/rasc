# Rasc 0.1.9

Version: 0.1.9 · build 15 · Apple silicon · macOS 14+

Status: **release candidate in preparation; not published.** Build and verification evidence must be added for the exact artifact before publication.

## What's new

- Scratchpad has a quieter layout without the Thinking Orb. Refine previews use the same reading position and make Suggested and Original easier to compare.
- Home keeps notes in a readable column, restores search focus on return, and makes it easier to clear a search. Quick Search and Command Palette also offer clear controls.
- Graphite Paper replaces violet-tinted surfaces and focus accents with warm paper and neutral graphite. Copper remains reserved for Keep and Kept.
- Onboarding and shortcut guidance make it clearer that Refine is optional and distinguish **Use original** from **Keep**.
- Refine's safeguards better preserve explicit uncertainty in suggestions. Refine remains optional and requires explicit acceptance; the separate missing “maybe” finding remains under investigation in [#48](https://github.com/rafaeltorresng/rasc/issues/48).
- Documentation now distinguishes current source, the published release, and historical evidence.

## Updating

Rasc 0.1.7 and 0.1.8 support manual **Check for Updates…**. Earlier builds without an updater require manual replacement. The release candidate must be tested on the actual upgrade path before this version is published. Capture, autosave, Keep and retrieval work without Refine; Refine requires macOS 26 and available Apple Intelligence.

## Release verification

- Local candidate: `build/updater-rc/0.1.9/Rasc-0.1.9-updater.dmg`, SHA-256 `6cac85245fc2412dcafdeabffa68502c360e34c65f5f5feb5e88d5cc995afda3`; ad-hoc signed, unnotarized. Built from a working tree based on the merged #81 content, including the uncommitted 0.1.9 version bump. Rebuild from a committed, final source revision before publication.
- Local updater build and signature verification passed. The domain fallback passed 434 tests plus the separate scale benchmark. The full Xcode suite passed 477 tests in 44 suites with the normal bundle identifier after the conflicting temporary review app was closed. The production candidate itself was not the test host.
- Native validation (macOS 26.5.1, Apple M3 Pro, 2026-11-17): the local candidate launched, Escape hid Scratchpad, and Home and Settings were inspected visually in dark mode. The installed 0.1.8 build was then upgraded in-app through Sparkle using a local HTTP feed: 0.1.9 was offered, the `Rasc15-14.delta` downloaded, **Install and Relaunch** completed, and the app relaunched as 0.1.9/build 15. Notes (16), `appTheme=rascDark`, and the global Scratchpad shortcut (`⌥\`) were unchanged. The installed app carries a valid Library Load Constraint, passes `codesign --verify --deep --strict`, has Sparkle mapped, and is Gatekeeper-rejected as expected for an ad-hoc build. The local feed override was removed after the check. Clean install from the published DMG, tamper rejection through the live UI, and the exact final-artifact feed remain **pending**.
- Updater behavior on macOS 14–25 remains unverified.

Follow [SPARKLE-RELEASE.md](SPARKLE-RELEASE.md) and [NATIVE-UI-VALIDATION.md](NATIVE-UI-VALIDATION.md). Do not interpret an unchecked item as a pass.

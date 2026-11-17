# Rasc 0.1.11

Version: 0.1.11 · build 17 · Apple silicon · macOS 14+

Status: **published 2026-11-17** as an ad-hoc signed, unnotarized
[GitHub Release](https://github.com/rafaeltorresng/rasc/releases/tag/v0.1.11).
Source commit `0e7aa69`; merged as `6aa837c`. Tag `v0.1.11` adds provenance.

## What's new

- The Rasc menu-bar icon is now drawn at approximately 24 pt inside the 32 pt
  template, down from roughly 28 pt, so it matches the visual weight of standard
  macOS status items. The silhouette, wordmark, Graphite Paper palette and all
  other brand assets are unchanged.

## Updating

If you have **v0.1.7** through **v0.1.10**, use **Check for Updates…** in the Rasc
or app menu. Updates are manual and nothing is downloaded silently. Earlier
builds without an updater require a one-time manual replacement.

## Build provenance

- DMG: `Rasc-0.1.11-updater.dmg`, SHA-256
  `baf11bd0cc4e2774987910d48eba8bc63e986a27acd0e1eac2bddf0db1f54067`.
- Deltas: `Rasc17-16.delta`, `Rasc17-15.delta`, `Rasc17-14.delta`, `Rasc17-13.delta`.
- Signature: ad-hoc, Hardened Runtime, App Sandbox, no network entitlement on
  the main app, with a Library Load Constraint pinning the shipped
  `Sparkle.framework` cdhash. Not notarized; first manual installs use Open
  Anyway.

## Release verification

- Appcast lengths, Ed25519 signatures and tamper rejection passed
  `verify-appcast.py`; previous v0.1.7–v0.1.10 enclosures remain byte-identical.
- Local fallback tests passed **434 tests in 37 suites** plus the separate scale
  benchmark. CI runs the full native suite on the release PR.
- Upgrade check: an installed v0.1.10 with synthetic data was upgraded in-app
  through Sparkle using `Rasc17-16.delta` and a local feed. The app relaunched as
  0.1.11/build 17 with notes, theme and shortcuts intact. The installed app
  passed `codesign --verify --deep --strict`, carried a valid Library Load
  Constraint and had Sparkle mapped. The compiled catalog contains the new
  32 px / 64 px `MenuBarIcon` templates. The local feed override was removed.
- The menu-bar size change is documented with a labeled mock comparison in
  `docs/validation/rasc-twin-fish/menubar-size-comparison.png`. No other brand
  asset changed.
- Post-deploy check: a live **Check for Updates…** was initiated from the
  installed 0.1.11 app; Sparkle showed the checking window and completed without
  a feed error (`live-updater-check-011.png`), and `SULastCheckTime` advanced.
  The deployed feed is byte-identical to the verified local appcast, and the
  public download resolved to a 6,134,119-byte asset with the expected
  filename and checksum. The up-to-date dialog was not captured because focus
  moved before the alert could be recorded.
- Not verified locally: VoiceOver, Reduce Motion, clean install through a second
  account, and updater behavior on macOS 14–25.

Follow [SPARKLE-RELEASE.md](SPARKLE-RELEASE.md) and
[NATIVE-UI-VALIDATION.md](NATIVE-UI-VALIDATION.md). Do not interpret an unchecked
item as a pass.

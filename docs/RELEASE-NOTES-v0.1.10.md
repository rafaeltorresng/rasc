# Rasc 0.1.10

Version: 0.1.10 · build 16 · Apple silicon · macOS 14+

Status: **release candidate in preparation; not published.** Publication evidence
will be added for the exact artifact before announcement.

## What's new

- The Rasc mark is now **Rasc Twin Fish**, candidate 02 from the 2026-11-17
  comparison. The two fish, their uneven scale, the open curve and the gap are
  preserved from the approved reference.
- The same silhouette is used in Home, onboarding, the menu-bar template and the
  macOS app icon. The app icon keeps its existing light plate with a Dock-specific
  scale and optical position; the standalone Home mark is unchanged in size.
- Brand assets are graphite `#242423` on light surfaces and warm paper `#F7F5F0`
  on dark surfaces. Copper remains exclusive to Keep and Kept. The wordmark,
  Graphite Paper palette, bundle identifier, data location, preferences,
  shortcuts and update channel are unchanged.
- No capture, Refine, retrieval or persistence behavior changed.

## Updating

If you have **v0.1.7**, **v0.1.8** or **v0.1.9**, use **Check for Updates…** in
the Rasc or app menu. Updates are manual and nothing is downloaded silently.
Earlier builds without an updater require a one-time manual replacement.
Capture, autosave, Keep and retrieval work without Refine.

## Build provenance

- DMG: `Rasc-0.1.10-updater.dmg`, 6,134,601 bytes, SHA-256
  `7519ab01ebe7aa50af8a5656f80f2ebca81ec0bc706f75335a22a45b1d22ce22`.
- Deltas: `Rasc16-15.delta`, `Rasc16-14.delta`, `Rasc16-13.delta`.
- Signature: ad-hoc, Hardened Runtime, App Sandbox, no network entitlement on
  the main app, with a Library Load Constraint pinning the shipped
  `Sparkle.framework` cdhash. Not notarized; first manual installs use Open
  Anyway.
- Source commit will be recorded in the final provenance update.

## Release verification

- Appcast lengths and Ed25519 signatures verified with `verify-appcast.py`,
  **RESULT: PASS**, including tamper rejection. Previous v0.1.7/v0.1.8/v0.1.9
  enclosures remain byte-identical to their published artifacts.
- Native packaged-app checks (macOS 26.5.1, Apple M3 Pro, 2026-11-17): new mark
  inspected in Home and onboarding in light and dark; Finder icon and menu-bar
  template inspected at actual size; capture → Keep → Home retrieval smoke test
  passed with a synthetic note.
- Upgrade check: installed v0.1.9 was upgraded in-app through Sparkle to
  v0.1.10/build 16 using `Rasc16-15.delta`. The app relaunched with notes,
  `appTheme`, and the global Scratchpad shortcut intact. The installed app passed
  `codesign --verify --deep --strict`, had a valid Library Load Constraint and
  Sparkle mapped. The local feed override was removed afterward.
- `xcodebuild test` could not launch the native test runner locally because of a
  LaunchServices restriction; the documented non-window fallback passed
  **434 tests in 37 suites** plus the separate scale benchmark. CI runs the
  full native suite on the release PR.
- Not verified locally: VoiceOver, Reduce Motion, clean install through a second
  account, and updater behavior on macOS 14–25.

Native screenshots and the asset/upgrade record are in
[docs/validation/rasc-twin-fish](validation/rasc-twin-fish/README.md).

Follow [SPARKLE-RELEASE.md](SPARKLE-RELEASE.md) and
[NATIVE-UI-VALIDATION.md](NATIVE-UI-VALIDATION.md). Do not interpret an unchecked
item as a pass.

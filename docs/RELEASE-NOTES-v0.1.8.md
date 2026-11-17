# Rasc 0.1.8

Version: 0.1.8 · build 14 · Apple silicon · macOS 14+

Status: **published 2026-11-16 as an ad-hoc signed, unnotarized GitHub Release.**
Build provenance below is final. See the [v0.1.8 release](https://github.com/rafaeltorresng/rasc/releases/tag/v0.1.8)
for the published assets and [SPARKLE-RELEASE.md](SPARKLE-RELEASE.md) for the
publication checklist.

## What changed

- **Fixed two stray orange lines on the home screen.** Clicking empty space in
  the note list focused the scroll view, whose focus ring was drawn across the
  full window width. The ring is now suppressed while keyboard navigation and
  selection remain unchanged.

The Sparkle updater is unchanged: same manual **Check for Updates…** action,
same Ed25519 verification before extraction, same Library Load Constraint pin
for `Sparkle.framework`, and no network entitlement on the main app.

## Updating

If you installed **v0.1.7**, use **Check for Updates…** in the Rasc or app menu.
Nothing is downloaded or installed silently.

If you are still on the public **v0.1.5** release or the **v0.1.6** pre-release,
neither contains an updater: download the v0.1.8 DMG once and install it by hand.
After that, in-app updates work normally.

macOS 14 or later is the declared minimum. The updater has been exercised only
on macOS 26.5.1; support on macOS 14–25 remains **unverified**.

Ad-hoc signed, **not notarized**. The first launch may require **Open Anyway**
(System Settings → Privacy & Security → Security, after a blocked attempt) or
right‑click → **Open**. See `docs/INSTALL-UNSIGNED.md`.

## Build provenance

- Source commit: `9da2e91` (merge of the 0.1.8 version-bump prep and the home
  focus-ring fix), working tree clean.
- DMG: `Rasc-0.1.8-updater.dmg`, SHA-256
  `a25035c27a9db86e55d7f1dfe9e4e071124b8d5d7c722ba4edca7d447255912c`
  (build 14, Apple silicon, ad-hoc signed, not notarized).
- Sparkle `2.9.4`; LLC cdhash pin: `0e66f4ed0b19cb8b52fd8063740ba80e1481366a`
  (same framework pin as v0.1.7).
- A `Rasc14-13.delta` from v0.1.7 is published alongside the DMG.
- Appcast enclosure signatures produced with the login-keychain `rasc-sparkle`
  account. Keep the DMG and its `.sha256` sidecar byte-identical everywhere they
  are hosted.

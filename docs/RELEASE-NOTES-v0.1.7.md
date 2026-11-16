# Rasc 0.1.7 — Sparkle in-app updates

Version: 0.1.7 · build 13 · Apple silicon · macOS 14+

Rasc now updates itself in place. This release is the only install path for
in-app updates: **the public `v0.1.5` release and the public `v0.1.6`
pre-release both contain no updater and cannot update themselves.** If you
installed either, download the `v0.1.7` DMG once and run it — after that,
`Check for Updates…` delivers subsequent releases in place.

- **Check for Updates…** appears in the Rasc menu and in the app menu; it is a
  manual action. Nothing is downloaded or installed silently.
- **Sparkle 2.9.4** is the updater; Rasc's update is signed with an Ed25519 key
  and verified by Sparkle before unpacking.
- **App Sandbox stays**, **Hardened Runtime stays**, and the Rasc executable
  still has **no network entitlement** (network work happens in Sparkle's
  sandboxed Installer and Downloader XPC services, not in the main process).
- Update signature verification relies on a Library Load Constraint that pins
  the exact `cdhash` of the final signed `Sparkle.framework`, not on a
  disabled Library Validation check. Any other or re-signed Sparkle is refused.
- macOS 14 or later is the declared minimum; the updater itself has been
  exercised on macOS 26.5.1 and is **unverified** on macOS 14.

Ad-hoc signed, **not notarized**. The first launch may require **Open Anyway**
(System Settings → Privacy & Security → Security, after a blocked attempt) or
right‑click → **Open**. See `docs/INSTALL-UNSIGNED.md`.

From `v0.1.5` and from the public `v0.1.6` pre-release, you must download the
`v0.1.7` DMG once by hand — neither contains an updater. Once `v0.1.7` is
installed, use `Check for Updates…` for later releases.

This release is the same source as `v0.1.6` plus this updater integration;
content and design are unchanged.

## Build provenance

The `v0.1.7` artifacts were produced from commit
`635ec7ac39b3cbe062602fb501645882361af390`
(`release: Rasc 0.1.7 — Sparkle in-app updates`), working tree clean.

- DMG: `Rasc-0.1.7-updater.dmg`
  SHA-256 `10648b0e532266b1180dfbeb99a1868d92f4e6d8bf5330c62f0b13ca72bfb36`
  (build 13, Apple silicon, ad-hoc signed, not notarized)
- Sparkle `2.9.4`; LLC pins the `cdhash` of the signed `Sparkle.framework`
  (`0e66f4ed0b19cb8b52fd8063740ba80e1481366a`)
- Appcast enclosure Ed25519 signature produced with the login-keychain
  `rasc-sparkle` account; please keep the DMG and its `.sha256` sidecar
  byte-identical to this record everywhere they are hosted.

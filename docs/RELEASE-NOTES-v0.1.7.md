# Rasc 0.1.7 — Sparkle in-app updates

Version: 0.1.7 · build 13 · Apple silicon · macOS 14+

Rasc now updates itself in place. If you installed the `v0.1.6` pre-release,
this release means your next `Check for Updates…` will work — no more manual
download for patch releases.

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

From 0.1.6 onwards, check for updates from the app menu; from 0.1.5 you must
download the 0.1.7 DMG once to become automatic‑upgradeable.

This release is the same source as `v0.1.6` plus this updater integration;
content and design are unchanged.

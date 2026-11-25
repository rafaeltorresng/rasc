# Rasc 0.1.15 (build 21)

This release ships Voice Capture and portable Markdown export from
[PR #96](https://github.com/rafaeltorresng/rasc/pull/96) (merge commit `9a9b471`
on `main`).

On macOS 26 or later with Apple silicon, you can opt in to Voice Capture in
Settings, assign a global shortcut, and dictate into Scratchpad as an unfinished
thought. The speech model is not bundled; **Download Speech Model** uses a
sandboxed embedded XPC helper (`VoiceModelDownloader.xpc`) with
`com.apple.security.network.client` while the main app remains network-isolated.
Models are verified against `VoiceModelManifest.json` and installed locally.

You can also export thoughts to a portable Markdown folder from Home, including
selection export and attachment copies. See [Voice Capture](VOICE-CAPTURE.md) and
[data and privacy](DATA-AND-PRIVACY.md).

Capture, autosave, Keep, Home, Search, Refine boundaries, and the local-first
store are unchanged unless noted above.

## Install and update

Updates are manual. Existing updater-enabled installations can use **Check for
Updates…** from the Rasc menu; this release offers signed deltas from builds
15–20. Earlier builds without Sparkle need a one-time manual replacement. This
Apple silicon DMG is ad-hoc signed and not notarized; on first install, macOS may
require **Open Anyway** in System Settings → Privacy & Security. See the
[installation guide](INSTALL-UNSIGNED.md) for checksum and first-launch steps.

## Verification

- Local `xcodebuild test` on build 21 (`CODE_SIGN_IDENTITY=-`, `DEVELOPMENT_TEAM=`)
  reported **TEST SUCCEEDED** (2026-11-24).
- The updater build produced a 13,054,236-byte arm64 DMG. App version/build,
  deep code-signing verification, Sparkle Library Load Constraint, sandbox and
  no-network-entitlement checks on the main app passed.
  `VoiceModelDownloader.xpc` carries only `app-sandbox` and `network.client` after
  the release pipeline re-sign step (see `Scripts/release/build-updater-rc.sh`).
  The packaged public key matches the `rasc-sparkle` login Keychain account.
  `hdiutil verify` and the SHA-256 sidecar passed. Gatekeeper rejects this ad-hoc
  app as expected; it is not notarized.
- SHA-256:
  `145d4a94759233f91e50bd1200b07749a4759a440efd33a86558623edac2e443`.
- A nine-entry staging appcast for v0.1.7–v0.1.15 passed length and Ed25519 checks
  with `verify-appcast.py` when OpenSSL 3 (`/opt/homebrew/bin/openssl`) is on
  `PATH` (system LibreSSL cannot verify Ed25519). The six v0.1.15 deltas cover
  builds 15–20 (`Rasc21-15` … `Rasc21-20`). The tamper-rejection check passed on
  the candidate DMG.
- **Before publishing:** seed the working feed from the live production appcast at
  `https://rasc.app/appcast.xml` (eight entries through v0.1.14) and regenerate
  only the v0.1.15 entry so historical enclosure URLs and signatures stay
  byte-identical. The local prep feed under `build/updater-rc/feed-v0.1.15-prep`
  rebuilt the v0.1.14 signatures and is not publishable as-is.
- Clean-machine Sparkle install, live-feed post-deploy smoke, website deploy, and
  macOS 14–25 remain unverified for this candidate.
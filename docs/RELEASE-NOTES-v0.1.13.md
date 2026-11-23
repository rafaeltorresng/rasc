# Rasc 0.1.13 (build 19)

This update carries the approved Twin Fish logo correction into the macOS app.
App icon, menu bar, Home branding, and other logo uses share the regenerated
brand assets. The change is visual; product behavior is unchanged.

The corrected mark restores the small contour at the upper-left fish tail using
the accepted reconstructed artwork. The exact original geometry could not be
recovered from the cropped source, so that local contour is an informed visual
reconstruction. See [logo reconstruction evidence](validation/logo-tail-reconstruction/README.md)
for the before/after comparisons and rendering notes.

## Install and update

Updates are manual. Existing updater-enabled installations can use **Check for
Updates…** from the Rasc menu. Earlier builds without Sparkle need a one-time
manual replacement. This Apple silicon DMG is ad-hoc signed and not notarized;
on first install, macOS may require **Open Anyway** in System Settings → Privacy
& Security.

## Verification

- GitHub Actions run [45246536033](https://github.com/rafaeltorresng/rasc/actions/runs/45246536033)
  passed the Debug build, 481 domain/persistence checks plus scale coverage, the
  full native test suite, and the default Release build.
- The updater build produced a 6,310,544-byte arm64 DMG. App version/build,
  deep code-signing verification, Sparkle Library Load Constraint, sandbox and
  no-network-entitlement checks passed. `hdiutil verify` and the SHA-256 sidecar
  passed. Gatekeeper rejects this ad-hoc app as expected; it is not notarized.
- Public GitHub assets were downloaded again and byte-matched the verified DMG,
  checksum sidecar and six deltas. SHA-256:
  `bf324171fc1fe535c9615f56d4083300ea72f45279e8b5327d1ea3b993fa2cae`.
- The seven-entry appcast for v0.1.7–v0.1.13 passed length and Ed25519 checks.
  The six v0.1.13 deltas cover builds 13–18. The tamper-rejection check passed.
- The landing's lint, typecheck, production build, 40 unit tests and all 54
  Chromium browser tests passed. Its production download link and appcast were
  checked after publication. GitHub Pages runs 45248619505 (feed/brand) and
  45249191060 (release facts) passed. The live appcast is byte-identical to the
  verified seven-entry feed; the public DMG URL, SHA-256 sidecar, favicon and
  social image return successfully. Headless desktop and mobile browsers
  confirmed the live download URL, 0.1.13 release facts, and dark icon tile in
  the actual release section.

The live in-app update and clean-account post-deploy “Already up to date” smoke
could not be run because this environment has no usable interactive display.
The CUA screen capture host returned a zero-sized screen. macOS 14–25,
VoiceOver, Full Keyboard Access, Reduce Motion/Transparency, and a clean-machine
install remain unverified. The local full native suite ran 525 tests; 523 passed
and two display/window-placement assertions failed in this host environment.
The same full suite passed in CI.

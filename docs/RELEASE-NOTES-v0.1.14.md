# Rasc 0.1.14 (build 20)

This release ships the personalization work from
[PR #93](https://github.com/rafaeltorresng/rasc/pull/93). You can choose custom
light and dark palettes and a note text size in Settings; those choices apply to
the Scratchpad, Home, Search, onboarding, command palette and shortcut keycaps.
Palette and note text size changes render in place. Preferences persist across
launches, and changing appearance keeps the editor's selection and undo state. Search
highlights resolve against the active palette.

The change is visual and preference-driven. Capture, autosave, Keep, Home, Search
and Refine behavior, the local-first store and the privacy boundaries are
unchanged.

## Install and update

Updates are manual. Existing updater-enabled installations can use **Check for
Updates…** from the Rasc menu; this release offers signed deltas from builds
14–19. Earlier builds without Sparkle need a one-time manual replacement. This
Apple silicon DMG is ad-hoc signed and not notarized; on first install, macOS may
require **Open Anyway** in System Settings → Privacy & Security. See the
[installation guide](INSTALL-UNSIGNED.md) for checksum and first-launch steps.

## Verification

- GitHub Actions runs
  [45308334979](https://github.com/rafaeltorresng/rasc/actions/runs/45308334979)
  and [45308356169](https://github.com/rafaeltorresng/rasc/actions/runs/45308356169)
  on [PR #94](https://github.com/rafaeltorresng/rasc/pull/94) passed the Debug
  build, 486 domain checks plus the scale benchmark, the full native test suite
  and the default Release build.
- The updater build produced a 6,487,318-byte arm64 DMG. App version/build,
  deep code-signing verification, Sparkle Library Load Constraint, sandbox and
  no-network-entitlement checks passed. The packaged public key matches the
  `rasc-sparkle` login Keychain account. `hdiutil verify` and the SHA-256 sidecar
  passed. Gatekeeper rejects this ad-hoc app as expected; it is not notarized.
- SHA-256:
  `f8c7d079cdf8a589556713a4dd3d7118a7582a465a4ae5c553474e6b2cd9f9b4`.
- The eight-entry appcast for v0.1.7–v0.1.14 passed length and Ed25519 checks.
  The six v0.1.14 deltas cover builds 14–19. The tamper-rejection check passed.
  All seven historical entries are byte-identical to the previously published
  feed, including their original versioned GitHub Release enclosure URLs.
- An isolated build 19 app with its own bundle identifier, container and three
  synthetic notes checked for updates over a temporary public HTTPS staging
  feed. Sparkle offered 0.1.14/build 20, verified and installed it, and
  relaunched with all three notes unchanged; the bundled library-load
  constraint and codesign verification remained valid. The user's installed app
  and notes were not involved.
- The landing's lint, typecheck, production build and unit tests passed. GitHub
  Pages runs
  [45310336475](https://github.com/rafaeltorresng/rasc-web/actions/runs/45310336475)
  (appcast) and
  [45310606975](https://github.com/rafaeltorresng/rasc-web/actions/runs/45310606975)
  (release facts) passed. The live appcast is byte-identical to the verified
  eight-entry file, and the live landing serves the v0.1.14 download URL and
  checksum. All GitHub Release assets were re-downloaded and byte-matched.
- A post-deploy in-app check on the live feed reported “You’re up to date! Rasc
  0.1.14 is currently the newest version available.”

macOS 14–25, VoiceOver, Full Keyboard Access, Reduce Motion/Transparency, and a
clean-machine install remain unverified.

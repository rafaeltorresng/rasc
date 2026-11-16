# Sparkle 2.9.4 (vendored)

This directory contains the official **Sparkle 2.9.4** binary distribution,
pinned so Release builds do not need network access or an SPM resolution step.

- Upstream: <https://github.com/sparkle-project/Sparkle/releases/tag/2.9.4>
- Framework: `Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework`
- License: MIT; see [LICENSE](LICENSE)

## How Rasc uses it

The `Rasc` Release configuration adds
`Vendor/Sparkle/Sparkle.xcframework/macos-arm64_x86_64` to
`FRAMEWORK_SEARCH_PATHS` and weak-links `Sparkle` with `-weak_framework`.
`RASC_SPARKLE` is defined only for Release, so Debug builds do not import or
link Sparkle.

The default Release build does **not** copy the framework into the app. Without
an embedded framework, `NSClassFromString("SPUStandardUpdaterController")` is
`nil`, the updater is not created, and **Check for Updates…** reports that
updates are unavailable. This keeps an ad-hoc-signed release launchable.

A build that embeds Sparkle must:

1. Copy `Sparkle.framework` to `Contents/Frameworks`.
2. Sign the nested XPC services, `Autoupdate`, `Updater.app`, and the framework.
3. Re-sign the app with `Rasc/Rasc.sparkle.entitlements`.
4. Use an Apple-issued signing identity with a Team ID so Hardened Runtime's
   Library Validation accepts the framework.

Because the link is weak, skipping step 4 does not crash the app: `dyld` skips
the rejected framework and updates stay unavailable. That is graceful
degradation, not a working updater. The zero-cost proof is blocked at step 4.
See
[`docs/SPARKLE-UPDATES.md`](../../docs/SPARKLE-UPDATES.md) before enabling this.

`Package.swift` is retained for reference, but the app links the framework
manually so Xcode does not automatically embed it.

# Sparkle 2 in-app updates: proof and blocker

Status: **historical — superseded by [SPARKLE-LLC.md](SPARKLE-LLC.md) (mechanism proven) and
[SPARKLE-RELEASE.md](SPARKLE-RELEASE.md) (updater RC pipeline).** **proof-only, not shippable.** Production releases, the live download, and
the public feed were not changed. The default Release build does **not** embed
Sparkle and cannot update itself.

## Summary

Rasc now contains a pinned Sparkle 2.9.4 integration that is compiled only for
Release behind `RASC_SPARKLE`, validates its feed URL and Ed25519 public key, and
adds **Check for Updates…** to the menu bar and app menu. The framework is
weak-linked; the default Release build does not embed it, so the updater is never
constructed and the menu item reports that updates are unavailable.

The actual in-place update test **cannot pass with the current zero-cost signing
model**. An ad-hoc signed app has no Team ID. With Hardened Runtime and Library
Validation enabled, macOS refuses to load a separately signed `Sparkle.framework`.
In the strong-link proof build this aborted the app at launch:

```text
Library not loaded: @rpath/Sparkle.framework/Versions/B/Sparkle
Referenced from: /Applications/Rasc.app/Contents/MacOS/Rasc
Reason: tried: '/Applications/Rasc.app/Contents/Frameworks/Sparkle.framework/Versions/B/Sparkle'
  (code signature ... not valid for use in process:
   mapping process and mapped file (non-platform) have different Team IDs)
```

The final weak-link build recovers from the same rejection: the app launches,
but `dyld` skips the framework, `NSClassFromString("SPUStandardUpdaterController")`
is `nil`, and the updater is never constructed. Either way, the update UI,
download, signature check, extraction, relaunch, and data-survival checks cannot
be exercised. No production feed or release asset was published.

## What is implemented

- **Pinned dependency:** `Vendor/Sparkle/Sparkle.xcframework` contains
  Sparkle **2.9.4** (`macos-arm64_x86_64`), with the upstream MIT license.
- **Release-only integration:** the `Rasc` Release configuration defines
  `RASC_SPARKLE`, adds the framework search path, and weak-links Sparkle
  (`-weak_framework Sparkle`). Debug builds do not import, link, or embed
  Sparkle.
- **Safe runtime fallback:** `AppDelegate` constructs
  `SPUStandardUpdaterController` only when
  `SparkleUpdaterConfiguration.current()` is valid **and**
  `NSClassFromString("SPUStandardUpdaterController") != nil`. The default
  Release has neither a real public key nor an embedded framework, so it starts
  normally and shows “Updates are not available in this build.”
- **Configuration validation:** `SparkleUpdaterConfiguration` requires an
  `https://` feed URL and a base64 Ed25519 public key that decodes to exactly
  32 bytes. The placeholder key is rejected.
- **Menu integration:** **Check for Updates…** appears in the menu bar menu and
  in the app menu. It is manual; automatic checks are disabled.
- **Info.plist security settings:** `SUVerifyUpdateBeforeExtraction` is `true`;
  `SUEnableAutomaticChecks`, `SUAllowsAutomaticUpdates`, and
  `SUAutomaticallyUpdate` are `false`.
- **Sparkle-only entitlements:** `Rasc/Rasc.sparkle.entitlements` keeps App
  Sandbox and the existing user-selected read-only entitlement, and adds only
  the two mach-lookup exceptions Sparkle's sandboxed XPC services need. The
  default `Rasc/Rasc.entitlements` is unchanged.
- **Tests:** `RascTests/SparkleUpdaterConfigurationTests.swift` covers valid
  configuration, placeholder key rejection, insecure feed rejection, missing
  values, malformed keys, and malformed URLs.

## What was verified

| Check | Result | Evidence |
| --- | --- | --- |
| Release A/B builds with embedded Sparkle, nested code signed | Pass | `build/sparkle-proof/repro/dist/0.1.7/Rasc-0.1.7.dmg`, `0.1.8/Rasc-0.1.8.dmg` |
| Appcast generation with disposable Ed25519 key | Pass | `build/sparkle-proof/feed/appcast.xml` |
| All appcast signatures and lengths | Pass | `build/sparkle-proof/evidence/appcast-verification.txt` |
| One-byte tamper is rejected | Pass | `build/sparkle-proof/evidence/tamper-sha256.txt` |
| HTTPS feed serves appcast and DMG | Pass with explicit CA; fails without it | `build/sparkle-proof/tls/`, `build/sparkle-proof/evidence/https-feed.txt`, `Scripts/sparkle-proof/serve_feed.py` |
| Gatekeeper blocks browser-downloaded ad-hoc app | Pass (expected) | `build/sparkle-proof/evidence/gatekeeper-screen-2.png` |
| Strong-link proof app with embedded Sparkle launches | **Fail (blocker)** | `build/sparkle-proof/evidence/rasc-0.1.7-release-launch-crash.ips` |
| Final weak-link app with embedded Sparkle launches | Pass, but Sparkle is not mapped and updates are unavailable | `build/sparkle-proof/evidence/weak-embedded-no-sparkle.txt`, `build/sparkle-proof/evidence/rasc-proof-updates-unavailable.png` |
| Weak-link Release without embedded Sparkle launches and shows the fallback | Pass | `build/sparkle-proof/evidence/rasc-status-menu-crop.png`, `build/sparkle-proof/evidence/rasc-updates-unavailable.png` |
| Full test suite | 464 tests in 42 suites pass | `xcodebuild test`, see below |

### Appcast signature verification

`generate_appcast` produced signatures for the two DMGs and the delta. OpenSSL
verified all three against the test public key. Lengths in the appcast match the
files on disk. The test public key is:

```text
p3FfrWDwvxSNrshM0AKoOSfiw2L+OFTHTSbcVnN/5L0=
```

The private key is disposable and lives only under the gitignored
`build/sparkle-proof/keys/` directory. It is **not** a production key.

### Tamper rejection

Flipping one byte at offset 1024 of `Rasc-0.1.8.dmg` produced:

```text
Signature Verification Failure
EVP_DigestVerify:provider signature failure ... ED25519 digest_verify
```

The original and tampered SHA-256 values are recorded in
`build/sparkle-proof/evidence/tamper-sha256.txt`.

### HTTPS feed

The feed was served locally at `https://127.0.0.1:8443/` with a self-signed CA
and a server certificate containing `IP:127.0.0.1`. `curl --cacert` fetched the
appcast and the 0.1.8 DMG successfully; the downloaded DMG's SHA-256 matched the
feed copy. `curl` without the CA failed with
`self signed certificate in certificate chain`. The full output is in
`build/sparkle-proof/evidence/https-feed.txt`.

For Sparkle itself to trust this feed, the CA must be added to the login or
system keychain and marked as trusted. macOS presents a Touch ID/password
authorization dialog for that change. The prompt was captured at
`build/sparkle-proof/evidence/ca-trust-prompt.png` and cancelled; the
certificate was then removed. This is a secondary blocker, independent of code
signing. The feed server is stopped and the test CA is not trusted.

### Gatekeeper and launch

A browser-style quarantine attribute was applied to the v0.1.7 DMG, the DMG was
mounted, and the app was copied to `/Applications`. Gatekeeper showed the
expected “Rasc Not Opened” prompt. After removing quarantine manually, the
strong-link proof build still aborted in `dyld` before `main` because of Library
Validation. That crash report is the canonical evidence for the rejection.

The final weak-link build was then rebuilt with the current project, embedded
Sparkle, signed with the expanded Sparkle entitlements, installed in
`/Applications`, and launched. It stayed running, but `lsof` showed no
`Sparkle.framework` mapped: `dyld` had skipped the rejected library because the
load is weak. This is graceful degradation, not a working updater. A weak-link
Release with **no** embedded Sparkle also launched normally. Choosing
**Check for Updates…** in either build showed the fallback alert
(`evidence/rasc-proof-updates-unavailable.png` and
`evidence/rasc-updates-unavailable.png`). Both are production-safe; neither can
update.

## Test suite

The full suite passes when `xcodebuild` is allowed to inject its normal Debug
base entitlements (`get-task-allow`):

```bash
xcodebuild test \
  -project Rasc.xcodeproj \
  -scheme Rasc \
  -configuration Debug \
  -derivedDataPath "${TMPDIR:-/tmp}/RascTests-DerivedData" \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY=- \
  DEVELOPMENT_TEAM=
```

Result:

```text
Test run with 464 tests in 42 suites passed
** TEST SUCCEEDED **
```

The known “test runner hung before establishing connection” from
`CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO` is a test-invocation problem: without
`get-task-allow`, the test host cannot attach to the test manager. Do not use
that flag for Debug tests; it remains appropriate for ad-hoc Release proof
builds.

Two environment-specific test problems also appeared during final validation:

- One run hung inside dyld while opening the GRDB package framework from a
  DerivedData directory on the iCloud-synced Desktop. Re-running with
  `-derivedDataPath "${TMPDIR:-/tmp}/RascTests-DerivedData"` passed. The
  repository and its build products are not modified by this workaround.
- A visible macOS notification banner sat at a modal-level window layer and
  made the five `PanelControllerTests` panel-visibility expectations fail.
  Clearing the banner and re-running passed. This test suite intentionally
  accounts for other apps' modal windows, so it is sensitive to the desktop
  state.

Neither problem is caused by the Sparkle integration. The final clean run after
those adjustments executed all 464 tests successfully.

## Exact blocker

Requirements in force:

- App Sandbox enabled.
- Hardened Runtime enabled.
- No disabling of Library Validation or other protections.
- No Developer ID, notarization, paid service, or new backend.

With ad-hoc signing, `codesign -dvvv` reports `TeamIdentifier=not set` for both
the app and Sparkle. Hardened Runtime enables Library Validation, which requires
the main binary and every non-platform library it loads to share a Team ID.
Ad-hoc signatures do not provide one, so `dyld` rejects the framework. A strong
load aborts at launch; a weak load skips the framework and the app continues
without an updater.

A self-signed code-signing certificate was tested as a zero-cost workaround. It
can sign code, but it still produces `TeamIdentifier=not set`; Library
Validation therefore still rejects the framework. There is no supported way to
manufacture an Apple-recognized Team ID without an Apple-issued signing
identity.

The only ways to make the current integration load are:

1. Sign the app and Sparkle with an Apple-issued certificate that has a Team ID
   (normally **Developer ID Application**, which requires the paid Apple
   Developer Program for direct distribution), or
2. Remove Hardened Runtime / disable Library Validation, or otherwise weaken the
   process protections.

Option 2 conflicts with the stated requirements and is not implemented. Option 1
is the recommended path if in-app updates become a product requirement.

## Production impact

- The default Release target uses `Rasc/Rasc.entitlements` and does **not**
  embed Sparkle. It has no network entitlement. It launches without Sparkle and
  shows “Updates are not available in this build.”
- `Rasc/Info.plist` retains a placeholder `SUPublicEDKey`. Because the
  placeholder is rejected, no updater is constructed even if a framework were
  present.
- The live `rasc.app/appcast.xml`, GitHub Releases, and the current download are
  untouched.
- `Vendor/Sparkle` is a build-time dependency only for the Release target's
  weak link and for proof builds. It is not copied into the default app.

Do **not** enable the feed, replace the public key, or publish a Sparkle-enabled
DMG until the signing strategy changes.

## Release flow once unblocked

This plan is intentionally not automated or enabled yet.

1. Obtain a Developer ID Application certificate and Team ID. Keep using App
   Sandbox and Hardened Runtime.
2. Build Release with `RASC_SPARKLE`, embed Sparkle 2.9.4 under
   `Contents/Frameworks`, and sign the nested XPC services, `Autoupdate`,
   `Updater.app`, and the framework with the Developer ID identity. Preserve
   Sparkle's entitlements. Re-sign the app with
   `Rasc/Rasc.sparkle.entitlements` so its mach-lookup exceptions name the real
   bundle ID.
3. Replace `SUPublicEDKey` with the production Ed25519 public key. Store the
   private key offline (password manager plus an offline backup), never in git,
   logs, or CI artifacts.
4. Build the final DMG as the update payload. Do not use a ZIP; Sparkle verifies
   the Ed25519 signature before extraction (`SUVerifyUpdateBeforeExtraction` is
   already `true`).
5. Upload the versioned DMG, delta (if any), and SHA-256 sidecar to the GitHub
   Release **before** changing the feed. Verify signatures and lengths against
   the uploaded files.
6. Update the stable HTTPS feed at `https://rasc.app/appcast.xml` last. Keep the
   previous versioned artifacts available.
7. Test on a clean Mac, outside Xcode: browser download → `/Applications` →
   launch → Check for Updates → user confirms → download → verify → install →
   relaunch. Confirm notes, preferences, and shortcuts survive. Repeat from the
   previous public version.
8. Existing v0.1.5 users have no updater. The first Sparkle-enabled release must
   be downloaded and opened manually (right-click **Open** or **Open Anyway** in
   System Settings). Later releases can update in-app with user confirmation.

## Limitations of this proof

- Only this Apple Silicon Mac was available. It has Xcode installed; no clean
  user, VM, or second Mac was available, and sudo requires a password. This is
  not a clean-machine proof.
- The self-signed TLS CA could not be trusted non-interactively, so Sparkle's own
  HTTPS fetch was not exercised. The feed was verified with `curl --cacert`.
- Gatekeeper's “Open Anyway” flow was not completed because it requires a user
  click; the app was launched after removing quarantine to expose the dyld
  failure.
- No in-app update, download, extraction, relaunch, or data-survival check was
  possible because Sparkle is never loaded in the weak-link build (and the
  strong-link proof build aborts at launch).

## Reproduction

See `Scripts/sparkle-proof/README.md` for the exact build, embed, sign, appcast,
feed, and verification commands. The verifier is
`Scripts/sparkle-proof/verify-appcast.py`.

## Evidence index

All paths are gitignored under `build/sparkle-proof/`:

- `repro/dist/0.1.7/`, `repro/dist/0.1.8/` — current-project weak-link builds produced by
  `build-variant.sh`, each with a DMG.
- `dist/Rasc-0.1.7.dmg`, `dist/Rasc-0.1.8.dmg` — earlier strong-link proof DMGs,
  retained as historical evidence for the launch crash.
- `feed/appcast.xml` — generated appcast with Ed25519 signatures.
- `feed/Rasc14-13.delta` — generated delta.
- `keys/sparkle_public_key`, `keys/sparkle_private_key` — disposable test key.
- `evidence/appcast-verification.txt` — signature/length results.
- `evidence/tamper-sha256.txt` — original vs. tampered hashes.
- `evidence/https-feed.txt` — trusted/untrusted HTTPS fetch results.
- `evidence/gatekeeper-screen-2.png` — Gatekeeper prompt.
- `evidence/ca-trust-prompt.png` — macOS certificate-trust authorization prompt (cancelled).
- `evidence/rasc-0.1.7-release-launch-crash.ips` — strong-link Library Validation crash.
- `evidence/weak-embedded-no-sparkle.txt` — weak-link app runs without mapping Sparkle.
- `evidence/rasc-status-menu-crop.png` — menu-bar **Check for Updates…** item.
- `evidence/rasc-updates-unavailable.png` — production-safe fallback alert.
- `evidence/rasc-proof-updates-unavailable.png` — the same fallback from the embedded weak-link proof build.
- `evidence/mount.txt` — DMG mount log.
- `tls/` — test CA and server certificate.

The reusable scripts live in the working tree at
`Scripts/sparkle-proof/` (`build-variant.sh`, `verify-appcast.py`,
`serve_feed.py`, and `README.md`).

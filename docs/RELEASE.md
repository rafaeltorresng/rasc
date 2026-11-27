# Rasc Release Workflow

> Latest published release: [0.1.15, build 21](https://github.com/rafaeltorresng/rasc/releases/tag/v0.1.15), ad-hoc signed and unnotarized. Earlier published artifacts remain untouched. Preserve published artifacts and verify each candidate independently.

The current ad-hoc updater release path is documented in [SPARKLE-RELEASE.md](SPARKLE-RELEASE.md); update checks are manual. The Developer ID and notarization steps below describe an optional signed distribution path, not a requirement for the published ad-hoc release. See [installation](INSTALL-UNSIGNED.md) and [v0.1.15 provenance](RELEASE-NOTES-v0.1.15.md).

## Current release configuration

| Setting | Value |
| --- | --- |
| Product name | Rasc |
| Bundle identifier | `com.rafaeltorres.rasc` |
| Marketing version | `0.1.16` in current source (`0.1.15` latest published DMG) |
| Build number | `CURRENT_PROJECT_VERSION` in Xcode (`22` in current source; `21` for published v0.1.15) |
| Deployment target | macOS 14.0 |
| First public artifact | Apple silicon (`arm64`); `archive.sh` fixes the architecture |
| Hardened Runtime | Enabled for Debug and Release |
| App Sandbox | Enabled for Release; Debug is unsandboxed for local evaluation |
| LSUIElement | `true` (menu bar utility, no Dock icon) |
| Release signing identity | `Developer ID Application` in the project, for the optional notarized path; published ad-hoc builds are re-signed with `-` |
| Debug signing | Ad hoc (`-`) for convenient local Xcode runs |
| Swift package dependencies | GRDB 7.11.1, KeyboardShortcuts 3.0.1 |
| Sparkle | 2.9.4 vendored; default Release weak-links and does not embed it. The updater DMG embeds, signs and pins it |

### Entitlements

Release builds scope `RASC_APP_ENTITLEMENTS` to the main `Rasc` app target (`Rasc/Rasc.entitlements`), with:

- `com.apple.security.app-sandbox`
- `com.apple.security.device.audio-input` (requested at OS level only when the user opts into Voice Capture / Dictate)
- `com.apple.security.files.user-selected.read-write` for files and folders the
  user chooses for portable export and manual database backups

No Accessibility entitlement (managed dynamically via macOS TCC only if opted in), Contacts, Calendar, Location, Camera, outgoing network, or temporary exception entitlements are enabled in the default Release app target.

The embedded XPC helper (`Contents/XPCServices/com.rafaeltorres.rasc.VoiceModelDownloader.xpc`) keeps its own `VoiceModelDownloader/VoiceModelDownloader.entitlements` (`com.apple.security.app-sandbox` and `com.apple.security.network.client` only). Both `build-private-beta.sh` and `build-rc.sh` sign inside-out (`sign_app_inside_out`) without `--deep` so `VoiceModelDownloader.xpc` preserves its own entitlements.

An updater-enabled build that embeds Sparkle sets `RASC_APP_ENTITLEMENTS` to
`Rasc/Rasc.sparkle.entitlements` instead. It adds the two mach-lookup exceptions
for Sparkle's sandboxed Installer and Downloader XPC services (`-spks` and
`-spki`) plus `com.apple.security.cs.disable-library-validation`, paired with a
Library Load Constraint that pins the `cdhash` of every shipped Mach-O framework
and dylib slice in `Contents/Frameworks/` (including `Sparkle.framework` and
`libswiftCompatibilitySpan.dylib`). The default Release does not need or use them.

## Published release

The latest candidate artifact is **v0.1.15 / build 21** (2026-11-24): ad-hoc
signed, unnotarized, Apple silicon, macOS 14+, with manual Sparkle updates. The
GitHub Release will contain:

| Asset | Value |
| --- | --- |
| DMG | `Rasc-0.1.15-updater.dmg` |
| SHA-256 | `145d4a94759233f91e50bd1200b07749a4759a440efd33a86558623edac2e443` |
| Checksum sidecar | `Rasc-0.1.15-updater.dmg.sha256` |
| Deltas | `Rasc21-20.delta`, `Rasc21-19.delta`, `Rasc21-18.delta`, `Rasc21-17.delta`, `Rasc21-16.delta`, `Rasc21-15.delta` |

The release is built from merge commit `9a9b471` on `main` ([PR #96](https://github.com/rafaeltorresng/rasc/pull/96));
tag `v0.1.15` should point at the version-bump commit on top of that source. The
production appcast at `https://rasc.app/appcast.xml` still serves v0.1.14 until
after publication; extend it with a v0.1.15 entry while preserving prior
enclosure URLs. See [RELEASE-NOTES-v0.1.15.md](RELEASE-NOTES-v0.1.15.md).
Earlier published artifacts remain unchanged; see the archived
[v0.1.14 notes](RELEASE-NOTES-v0.1.14.md) and
[v0.1.13 notes](RELEASE-NOTES-v0.1.13.md).

### Retained local RC (`0.1.16`, build `22`, commit `30c5c14`)

An updated local release candidate was built and verified in `build/updater-rc/0.1.16-final-rc`
(retaining `0.1.15` and prior `0.1.16` artifacts untouched; ad-hoc signed with `cdhash`-pinned
Library Load Constraints, unnotarized — Developer ID & Apple notarization remain deferred):

| Asset / Check | Verified Value |
|---|---|
| `Rasc.app` | `46,660,045 B` (`44.50 MiB`), `arm64`, zero `network.client` on main app |
| `Rasc-0.1.16-updater.dmg` | `13,782,657 B` (`13.14 MiB`), SHA-256 `208d426e4448c6de918b712e7947a84a6631cb7954a1b9055ac76c188a8c839f` |
| LLC pins (`Contents/Frameworks/`) | `Sparkle` (`0e66f4ed0b19cb8b52fd8063740ba80e1481366a`), `libswiftCompatibilitySpan.dylib` (`c3228a12b0782b9b402391c99f9627f4c9e2456b`) |
| Delta & Ed25519 appcast | `Rasc22-21.delta` (`3,378,602 B`); `verify-appcast.py --tamper` passed (`Signature Verified Successfully` / tamper rejected) |
| Isolated `0.1.15 → 0.1.16` upgrade | Launched `com.rafaeltorres.rasc.rcverify` across clean container: `PRAGMA integrity_check = ok`, `v11_scale_indexes_and_origin` applied, seeded notes/revisions/`FTS5` preserved, 15s standby `31 MB` / `0.0%` CPU, personal DBs untouched |

### Isolated reliability candidate (`0.1.16`, build `25`)

Use `build/updater-rc/0.1.16-reliability-25/export/Rasc.app` for the independent
feature-freeze pass. The DMG, checksum and `candidate-manifest.json` are in
`build/updater-rc/0.1.16-reliability-25`. Verify the DMG with
`shasum -a 256 -c Rasc-0.1.16-updater.dmg.sha256` from that directory.

| Field | Value |
|---|---|
| Base commit | `5c4e5ad411b16738262451f930eb39074628ade6` |
| Build inputs | `candidate-source.patch`, SHA-256 `3fac0e536de267a4f102686936fd0edcdbd96db8ace0834b244a00b0e7b8eb9d`, relative to the base commit |
| Bundle | `com.rafaeltorres.rasc.reliabilityrc`, arm64, deployment target macOS 14.0 |
| DMG | `13,791,653 B`, SHA-256 `0114f1d1dc656999c0d538bb8ac7547af9d554336b14082224472a07fb0469b2` |
| App bundle | `46,738,030 B` logical regular-file bytes, optional model stored separately |
| Signing | Ad-hoc, Hardened Runtime, App Sandbox and cdhash-pinned LLC, unnotarized |
| Update isolation | Automatic checks off and `https://127.0.0.1:9/appcast.xml` as the feed |

This local build has a separate bundle and container for independent testing.
The feature-freeze commit consolidates the exact build inputs recorded in the
patch. Its commit message records the patch and DMG checksums, and the retained
manifest records the consolidating commit. Build 25 is a packaging override.
The checksum, read-only mount, embedded signatures and entitlements were verified
on macOS 26.5.1. The preceding DMGs have been retained.
Use the documented Open Anyway flow after verifying the checksum.
[Install guide](INSTALL-UNSIGNED.md), [Independent checklist](NATIVE-UI-VALIDATION.md#independent-reliability-candidate-pass)

### Focused UX / Dictate candidate (`0.1.16`, build `27`)

Use `build/updater-rc/0.1.16-ux-dictate-27/export/Rasc.app` for the final
Dictate, onboarding and window-geometry pass. Builds 25 and 26 are retained
untouched. This isolated ad-hoc build shares bundle identifier and container
with build 26 so onboarding and settings carry over, but its Accessibility
identity is distinct from both the distributed app and every other ad-hoc build.
If System Settings lists an older Rasc entry, remove it and add this exact
bundle with **+**, then return to Rasc; **Allow…** now opens Accessibility with
those instructions when the system prompt is suppressed.

| Field | Value |
|---|---|
| Base commit | `02dbacc577e5fb65f4eeb3402484281b3a186709` |
| Source commit | `f58caec31019eb903fcba696b42c6bb82ad46547` |
| Source patch | `candidate-source.patch`, SHA-256 `e12be8508233cf4ca0ffdba0903922615106d7557a6f592fecd7d2467ab6e87b` |
| Bundle | `com.rafaeltorres.rasc.uxrc`, arm64, deployment target macOS 14.0 |
| DMG | `Rasc-0.1.16-updater.dmg`, SHA-256 `568e1b359810260c066905b05d03d8c00a428a4313b783e1c54c4d3684d65b63` |
| App executable | SHA-256 `654b7e55b75ce15754e384e41124df4d2726340eb00ab6f8e836896bf1377e50` |
| Signing | Ad-hoc, Hardened Runtime, cdhash-pinned LLC, unnotarized |
| Update isolation | Automatic checks off and `https://127.0.0.1:9/appcast.xml` as the feed |
| Recording cap | 120 seconds (unchanged) |

Automated validation: 671 Xcode tests, 618 `Scripts/test-domain.py` tests plus
the scale suite, Debug and Release builds, `verify-rc-bundle.sh`, DMG checksum,
deep strict codesign and embedded library pins. Physical desktop checks are
still pending and listed in
[NATIVE-UI-VALIDATION.md](NATIVE-UI-VALIDATION.md#focused-ux--dictate--geometry-pass-build-26).
The production appcast and published release are unchanged.

## Prerequisites

The prerequisites below apply to the optional Developer ID/notarization path. The
published ad-hoc updater path needs no paid Apple program; follow
[SPARKLE-RELEASE.md](SPARKLE-RELEASE.md).

1. Xcode with the Rasc project opened at least once so Swift packages resolve.
2. An Apple Developer account with a **Developer ID Application** certificate installed in your login keychain.
3. A 10-character Team ID.
4. A notarytool keychain profile stored locally (never commit credentials).

### One-time local credential setup

Set your Team ID for release builds:

```bash
export RASC_DEVELOPMENT_TEAM="YOURTEAMID"
```

Create a notarytool keychain profile (recommended: app-specific password in Keychain):

```bash
xcrun notarytool store-credentials "RASC_NOTARY"
```

Optional override for the profile name:

```bash
export RASC_NOTARY_KEYCHAIN_PROFILE="RASC_NOTARY"
```

Enter the Apple ID, Team ID and app-specific password at the interactive prompts.
Do not put passwords on command lines, in shell history or in source control.
The profile is stored in Keychain. Team IDs identify the signing team, not a password.

## Release artifact flow

These steps produce the optional Developer ID-signed DMG. The published ad-hoc
updater DMG is produced by `Scripts/release/build-updater-rc.sh`; see
[SPARKLE-RELEASE.md](SPARKLE-RELEASE.md).

All scripts live in `Scripts/release/` and write artifacts to `build/`.

### 1. Run tests

```bash
xcodebuild test \
  -project Rasc.xcodeproj \
  -scheme Rasc \
  -destination 'platform=macOS'
```

### 2. Archive Release build

```bash
export RASC_DEVELOPMENT_TEAM="YOURTEAMID"
./Scripts/release/archive.sh
```

Output: `build/Rasc.xcarchive`

### 3. Export signed app

```bash
./Scripts/release/export-app.sh
```

Output: `build/export/Rasc.app`

GRDB and KeyboardShortcuts are statically linked; their resource bundles are
included under `Contents/Resources/`, together with third-party notices.

### 4. Package DMG

```bash
./Scripts/release/package-dmg.sh
```

Output: `build/Rasc.dmg`

The DMG contains:

- `Rasc.app`
- `Applications` alias

### Convenience wrapper

Steps 2–4 in one command:

```bash
export RASC_DEVELOPMENT_TEAM="YOURTEAMID"
./Scripts/release/build-distributable.sh
```

## Notarization flow

Submit the final DMG, wait for approval, then staple. The script intentionally
accepts only DMG: ZIP cannot receive a stapled ticket.

```bash
./Scripts/release/notarize.sh build/Rasc.dmg
```

Underlying commands:

```bash
xcrun notarytool submit build/Rasc.dmg --keychain-profile RASC_NOTARY --wait
xcrun stapler staple build/Rasc.dmg
xcrun stapler validate build/Rasc.dmg
```

If submission fails:

```bash
xcrun notarytool history --keychain-profile RASC_NOTARY
xcrun notarytool log <submission-id> --keychain-profile RASC_NOTARY
```

## Verification commands

For a notarized build, verify the actual distributed artifact (prefer the stapled
DMG):

```bash
./Scripts/release/verify-release.sh build/Rasc.dmg
```

Manual equivalents:

```bash
codesign --verify --deep --strict --verbose=2 /path/to/Rasc.app
codesign --display --entitlements :- /path/to/Rasc.app | plutil -p -
spctl --assess --type execute --verbose=4 /path/to/Rasc.app
xcrun stapler validate build/Rasc.dmg
```

The verification script covers the Developer ID/notarization path: it requires
Developer ID, a Team ID, hardened runtime, sandbox without network entitlements,
matching bundle/version/build, Gatekeeper acceptance and a stapled ticket. It
rejects debug/test/database artifacts and `get-task-allow`. For an `.app` argument,
staple the app ticket first; the normal workflow verifies the distributed DMG and
its ticket. `verify-release.sh` is not an ad-hoc release gate; verify those with the
checksum and signing/sandbox status instead.

## Bundle audit checklist

Before distributing, confirm the exported app does **not** include:

- `Contents/Frameworks/Sparkle.framework` unless this is a deliberately signed Sparkle-enabled build
- debug entitlements (`get-task-allow`)
- development API credentials
- signing private keys or notarization credentials
- note contents or local development databases
- test fixtures such as `RefinementEvals.v1.json`

Expected embedded dependencies (statically linked into the main executable):

- `Contents/Resources/GRDB_GRDB.bundle`
- `Contents/Resources/KeyboardShortcuts_KeyboardShortcuts.bundle`

The exported app should not contain `Contents/PlugIns/RascTests.xctest` or other test bundles.

### Bundle identifier

`Rasc/Info.plist` is source-controlled with `CFBundleIdentifier` set to `$(PRODUCT_BUNDLE_IDENTIFIER)`. The identifier is defined once per target in `project.pbxproj`:

| Target | Debug | Release |
| --- | --- | --- |
| Rasc | `com.rafaeltorres.rasc` | `com.rafaeltorres.rasc` |
| VoiceModelDownloader | `com.rafaeltorres.rasc.VoiceModelDownloader` | `com.rafaeltorres.rasc.VoiceModelDownloader` |
| RascTests | `com.rafaeltorres.rasc.tests` | `com.rafaeltorres.rasc.tests` |

`Scripts/test-native.sh` overrides only `RASC_APP_BUNDLE_IDENTIFIER=com.rafaeltorres.rasc.testhost` so `VoiceModelDownloader.xpc` retains its own identifier and copy path during AppKit tests.

Debug is unsandboxed for local evaluation tools; Release uses the sandbox.
Ad-hoc Xcode builds may include `get-task-allow` and Xcode can disable hardened
runtime with ad-hoc signing. They are build evidence, not public artifacts.
Developer ID exports must satisfy `verify-release.sh`.

## Clean-machine release verification

Do not treat “Run from Xcode” as proof of distribution behavior.

1. Copy `build/Rasc.dmg` to another Mac as if downloaded externally (AirDrop, browser download, or shared drive).
2. Open the DMG in Finder and drag `Rasc.app` to `/Applications`.
3. Launch Rasc from Finder (not Xcode).
4. Confirm the documented first-launch path for the artifact's signing model: **Open Anyway** for ad-hoc builds, or Gatekeeper acceptance for a notarized build.
5. Verify the global shortcut opens the scratchpad.
6. Create a note, quit Rasc, relaunch, and confirm persistence.
7. Open History/Search and recover the note.
8. On supported hardware, run Refine and accept or cancel a preview.
9. Confirm the menu bar icon is available.
10. Enable Launch at Login in Preferences and confirm registration (approve in System Settings if required).
11. With another app in native fullscreen, trigger the global shortcut and confirm the scratchpad appears above fullscreen.

Record any failures with macOS version, display layout, and reproduction steps.

## Steps requiring Apple Developer credentials

These steps cannot be completed without your Apple Developer account:

- Installing/importing a **Developer ID Application** certificate
- Setting `RASC_DEVELOPMENT_TEAM`
- Archiving/exporting with Developer ID signing
- Creating the notarytool keychain profile
- Submitting to Apple notary service
- Stapling the notarization ticket

Local Debug builds from Xcode continue to work with ad hoc signing and do not require notarization.

## Artifact retention (M14 policy)

Starting with **0.1.0-beta.2**, retain every shipped or private-release artifact needed for future upgrade testing:

| Retain | Location (example) |
|---|---|
| Versioned DMG | `build/rc/Rasc-<version>.dmg` |
| SHA256 sidecar | `build/rc/Rasc-<version>.dmg.sha256` |
| Release manifest | `build/rc/release-manifest.json` |
| Freeze record | `build/rc/FROZEN-RC.json` |
| Maintainer acceptance | `Evals/AppReliability/M14/` |

**Rules:**

1. Do not delete the immediately previous release artifact when shipping a new RC.
2. Future RC gates must include an **upgrade test** from the previous retained build + representative user database when available.
3. beta.1 → beta.2 upgrade was **not testable** (beta.1 artifact not retained). Not a blocker for beta.2 acceptance.
4. Store artifacts outside git if needed; record paths and SHA256 in the release manifest.

Scripts now refuse to overwrite an existing DMG or erase an existing `build/rc/`
or `build/private-beta/` directory. Move prior artifacts to a versioned retained
directory before building again. Retain the checksum, manifest and matching backup.
These checks do not certify an ad-hoc RC as a public release.

### RC build commands (private beta, ad-hoc)

```bash
./Scripts/release/build-rc.sh
./Scripts/release/verify-private-beta.sh build/rc/Rasc-<version>.dmg
./Scripts/release/verify-rc-bundle.sh build/rc/export/Rasc.app
./Scripts/release/generate-rc-manifest.sh build/rc/Rasc-<version>.dmg
```

Output directory: `build/rc/`.

## Incrementing versions

- User-visible version: update `MARKETING_VERSION` (for example `0.1.0`, `0.1.1`).
- Build number: increment `CURRENT_PROJECT_VERSION` for each distributable build.

For each release, build from the intended source, run the applicable acceptance checks and retain the exact artifact, checksum and provenance. For a notarized build, calculate the final checksum after stapling, which changes the artifact. Do not rename historical binaries. A version/build pair in the project does not by itself prove a published artifact; confirm the GitHub Release, its assets and the checksum.

Follow [SPARKLE-RELEASE.md](SPARKLE-RELEASE.md) for the updater-enabled ad-hoc path; [PUBLISH-0.1.md](PUBLISH-0.1.md) records the original v0.1.0 publication checklist. Verify any claimed signing or notarization on the machine that produces the DMG.

## CI note

This milestone is intentionally local and scriptable. The artifact layout (`build/export/Rasc.app`, `build/Rasc.dmg`) is stable for a future CI job to call the same scripts without redesign.

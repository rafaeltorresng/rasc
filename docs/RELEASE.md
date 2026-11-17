# Rasc Release Workflow

> Latest published release: [0.1.9, build 15](https://github.com/rafaeltorresng/rasc/releases/tag/v0.1.9), ad-hoc signed and unnotarized. Earlier published artifacts remain untouched. Preserve published artifacts and verify each candidate independently.

The current ad-hoc updater release path is documented in [SPARKLE-RELEASE.md](SPARKLE-RELEASE.md); update checks are manual. The Developer ID and notarization steps below describe an optional signed distribution path, not a requirement for the published ad-hoc release. See [installation](INSTALL-UNSIGNED.md) and [v0.1.9 provenance](RELEASE-NOTES-v0.1.9.md).

## Current release configuration

| Setting | Value |
| --- | --- |
| Product name | Rasc |
| Bundle identifier | `com.rafaeltorres.rasc` |
| Marketing version | `0.1.9` (published 2026-11-17) |
| Build number | `CURRENT_PROJECT_VERSION` in Xcode (`15` for v0.1.9) |
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

Release builds use `Rasc/Rasc.entitlements` with only:

- `com.apple.security.app-sandbox`
- `com.apple.security.files.user-selected.read-only` (for explicit copy/share handoff)

No Accessibility, Contacts, Calendar, Location, Camera, Microphone, outgoing network, file-provider, or temporary exception entitlements are enabled in the default Release build.

An updater-enabled build that embeds Sparkle uses
`Rasc/Rasc.sparkle.entitlements` instead. It adds the two mach-lookup exceptions
for Sparkle's sandboxed Installer and Downloader XPC services (`-spks` and
`-spki`) plus `com.apple.security.cs.disable-library-validation`, paired with a
Library Load Constraint that pins the signed Sparkle framework. The default Release
does not need or use them.

## Published release

The latest published artifact is **v0.1.9 / build 15** (2026-11-17): ad-hoc signed,
unnotarized, Apple silicon, macOS 14+, with manual Sparkle updates. The GitHub
Release contains:

| Asset | Value |
| --- | --- |
| DMG | `Rasc-0.1.9-updater.dmg` |
| SHA-256 | `97c0527a20c8da0faab58885c38af41683cb90c3debba1cdd791b09d00a9912d` |
| Checksum sidecar | `Rasc-0.1.9-updater.dmg.sha256` |
| Deltas | `Rasc15-14.delta`, `Rasc15-13.delta` |

The release notes record source commit `8fae4fd`; tag `v0.1.9` adds the provenance
commit. The production appcast at `https://rasc.app/appcast.xml` serves matching
versioned GitHub Release enclosures. Preserve these exact bytes and see
[RELEASE-NOTES-v0.1.9.md](RELEASE-NOTES-v0.1.9.md). Published v0.1.8/build 14 and
v0.1.7/build 13 artifacts remain unchanged.

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
| RascTests | `com.rafaeltorres.rasc.tests` | `com.rafaeltorres.rasc.tests` |

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

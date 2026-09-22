# Rasc Release Workflow (M6A)

This document describes how to produce a signed, sandboxed, notarized direct-distribution build of Rasc outside Xcode.

Sparkle and automatic updates are intentionally out of scope for this milestone.

## Current release configuration

| Setting | Value |
| --- | --- |
| Product name | Rasc |
| Bundle identifier | `com.rafaeltorres.rasc` |
| Marketing version | `0.1.0-beta.2` (current canonical private beta); use semver for public releases |
| Build number | `CURRENT_PROJECT_VERSION` in Xcode (`3` for beta.2) |
| Deployment target | macOS 14.0 |
| Hardened Runtime | Enabled for Debug and Release |
| App Sandbox | Enabled |
| LSUIElement | `true` (menu bar utility, no Dock icon) |
| Release signing identity | `Developer ID Application` |
| Debug signing | Ad hoc (`-`) for convenient local Xcode runs |
| Swift package dependencies | GRDB 7.11.1, KeyboardShortcuts 3.0.1 |

### Entitlements

Release builds use `Rasc/Rasc.entitlements` with only:

- `com.apple.security.app-sandbox`

No Accessibility, Contacts, Calendar, Location, Camera, Microphone, outgoing network, file-provider, or temporary exception entitlements are enabled.

## Prerequisites

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
xcrun notarytool store-credentials "RASC_NOTARY" \
  --apple-id "you@example.com" \
  --team-id "YOURTEAMID" \
  --password "@keychain:AC_PASSWORD"
```

Optional override for the profile name:

```bash
export RASC_NOTARY_KEYCHAIN_PROFILE="RASC_NOTARY"
```

Do not commit Apple IDs, team IDs used as secrets, app-specific passwords, or private keys.

## Release artifact flow

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

The exported app should contain embedded Swift package frameworks (`GRDB`, `KeyboardShortcuts`) under `Contents/Frameworks/`.

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

Submit the final DMG (or a signed ZIP of the app), wait for approval, then staple:

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

Verify the actual distributed artifact (prefer the stapled DMG):

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

The verification script fails if `get-task-allow` is present.

## Bundle audit checklist

Before distributing, confirm the exported app does **not** include:

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

Ad-hoc local builds (Debug or Release without Developer ID export) may include the `get-task-allow` entitlement. Developer ID–signed export artifacts must not; `verify-release.sh` enforces this.

## Clean-machine beta verification

Do not treat “Run from Xcode” as proof of distribution behavior.

1. Copy `build/Rasc.dmg` to another Mac as if downloaded externally (AirDrop, browser download, or shared drive).
2. Open the DMG in Finder and drag `Rasc.app` to `/Applications`.
3. Launch Rasc from Finder (not Xcode).
4. Confirm Gatekeeper accepts the app on first launch.
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

## CI note

This milestone is intentionally local and scriptable. The artifact layout (`build/export/Rasc.app`, `build/Rasc.dmg`) is stable for a future CI job to call the same scripts without redesign.

# Publish Rasc 0.1.0 (without Developer ID)

First public release **without** Apple Developer Program, Developer ID, or notarization.
Users get **open source + optional unsigned DMG**; macOS will show Gatekeeper warnings
until they explicitly allow the app the first time.

**Source candidate:** `0.1.0` / build `6`  
**Tag:** `v0.1.0`  
**Binary:** ad-hoc signed Release DMG (not notarized)

## What you are choosing

| With Developer ID + notarization | This path (no paid Apple program) |
| --- | --- |
| Gatekeeper accepts the DMG for most users | First open needs **Right-click → Open** or **Privacy & Security → Open Anyway** |
| `verify-release.sh` passes | Use `verify-private-beta.sh` on the DMG instead |
| Landing can claim `notarized: true` | Landing must say **unsigned / not notarized**; promote **build from source** |

That is acceptable for an MIT OSS v0.1 if messaging is honest. Do not tell users the download is “verified by Apple.”

## Before you publish

- [ ] `xcodebuild test` and CI green on `main`.
- [ ] Repo content review for public visibility (no secrets, no personal databases in git).
- [ ] Optional: quick manual pass on [NATIVE-UI-VALIDATION.md](NATIVE-UI-VALIDATION.md).

## Build the unsigned DMG

No `RASC_DEVELOPMENT_TEAM` required.

```bash
cd /path/to/rasc
xcodebuild test -project Rasc.xcodeproj -scheme Rasc -destination 'platform=macOS'

# If build/rc/ already exists, move it aside first:
# mv build/rc build/rc-retained-$(date +%Y%m%d)

./Scripts/release/build-rc.sh
./Scripts/release/verify-private-beta.sh build/rc/Rasc-0.1.0.dmg

mkdir -p build/releases
cp -n build/rc/Rasc-0.1.0.dmg build/releases/Rasc-0.1.0-unsigned.dmg
(cd build/releases && shasum -a 256 Rasc-0.1.0-unsigned.dmg > Rasc-0.1.0-unsigned.dmg.sha256)
```

Record `git rev-parse HEAD` and the SHA256 in [RELEASE-NOTES-v0.1.md](RELEASE-NOTES-v0.1.md).

**Filename `-unsigned`** makes the Gatekeeper story obvious in URLs and release assets.

## Test as an end user would

1. Copy `Rasc-0.1.0-unsigned.dmg` to a folder as if downloaded (not from Xcode).
2. Open DMG, drag to Applications.
3. First launch: expect Gatekeeper — use **Right-click → Open** (or System Settings → Privacy & Security).
4. Smoke: capture, autosave, Keep, Home, Search, hide/reopen.

Document this in the GitHub Release body (see [INSTALL-UNSIGNED.md](INSTALL-UNSIGNED.md)).

## GitHub

- [ ] Commit and push `main`.
- [ ] Make repository **public** when ready.
- [ ] Tag `v0.1.0` on the commit used for the DMG (or note the exact SHA in release notes).
- [ ] GitHub Release `v0.1.0`: notes from [RELEASE-NOTES-v0.1.md](RELEASE-NOTES-v0.1.md), attach `Rasc-0.1.0-unsigned.dmg` + `.sha256`.
- [ ] Confirm anonymous clone and release download work.

## Landing (`rasc-web`)

- [ ] `sourcePublic: true`, `publicReleaseReady: true`, **`notarized: false`**.
- [ ] Download points at the **unsigned** GitHub Release asset (or remove download CTA and link “Build from source” only).
- [ ] Short link to `INSTALL-UNSIGNED.md` on GitHub (or duplicate the steps on the site).

## Later (optional)

If you join the Apple Developer Program, use [RELEASE.md](RELEASE.md) (`build-distributable.sh`, notarize, `verify-release.sh`) and ship a **new build number** with a notarized DMG — do not rename the unsigned file as notarized.

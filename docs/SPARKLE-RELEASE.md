# Production runbook: Sparkle updates via Library Load Constraint (ad-hoc signed)

Status: **v0.1.15/build 21 is a verified local candidate (2026-11-24); v0.1.14/build
20 remains published until this release ships; v0.1.7/build 13 was the first
updater release.** The production feed still serves the v0.1.14 entry with
v0.1.7–v0.1.13 retained. The default Release build is unchanged and cannot
update itself. This document is
the canonical procedure for the updater-enabled build. Please read fully before
publishing.

Audience: the maintainer preparing the next public release.

## What this is

Ad-hoc-signed code has no Team ID. Hardened Runtime's Library Validation refuses
to load the vendored `Sparkle.framework`, so the default Release build (weak link)
only shows "Updates are not available in this build." The Library Load Constraint
(LLC) is the Apple-documented mechanism (WWDC23 "Protect your Mac app with
environment constraints"); see [SPARKLE-LLC.md](SPARKLE-LLC.md) for the full
proof, including the wrong-pin negative control.

The required combination — do not split these:

- App Sandbox + Hardened Runtime
- **no network entitlement on the main app** (Sparkle's Downloader/Installer XPC services and `VoiceModelDownloader.xpc` handle their own isolated network I/O)
- `com.apple.security.cs.disable-library-validation`, and
- an LLC embedded in the app signature that pins the `cdhash` of every **final signed**
  Mach-O framework main binary and loose `*.dylib` in `Contents/Frameworks/`
  (currently `Sparkle.framework/Versions/Current/Sparkle` and Xcode's embedded
  `libswiftCompatibilitySpan.dylib`) for every shipped architecture.

`Scripts/release/build-updater-rc.sh` produces the artifact and refuses to
package if the constraint is missing or wrong (it hard-fails before the DMG
stage).

## The development feed (staging, HTTPS, locally served)

For candidate verification, the feed is a local directory served over HTTPS via
a publicly-trusted tunnel such as Cloudflare quick tunnel (`cloudflared tunnel
--url …`) or any static HTTPS host. This was used both on this Mac and on the
maintainer's Air M4. The host name is disposable; the feed is never the
production one and never served from `rasc.app`. The production feed at
`https://rasc.app/appcast.xml` is live and serves the published v0.1.14 entry
(build 20) until v0.1.15 is deployed; earlier entries are retained for older
upgrades.

## RC build pipeline (what `build-updater-rc.sh` does)

One Release `xcodebuild` per version, strong-linked against Sparkle **not** used
here (Release keeps the weak link); ad-hoc signature:

1. Builds `Release` with `ARCHS=arm64`, sandbox + Hardened Runtime, reusing
   `.derivedData/Rasc/SourcePackages` when available, and setting `RASC_APP_ENTITLEMENTS`
   (main app target only) to `Rasc/Rasc.sparkle.entitlements`.
2. Confirms no `com.apple.security.network.client` on the main app; signs
   `VoiceModelDownloader.xpc` inside-out with `VoiceModelDownloader/VoiceModelDownloader.entitlements`
   and asserts it retains `network.client` without inheriting `device.audio-input`
   or `files.user-selected.read-write`.
3. Embeds and signs Sparkle helpers (`Installer.xpc`, `Downloader.xpc`,
   `Autoupdate`, `Updater.app`, `Sparkle.framework`) plus any loose
   `Contents/Frameworks/*.dylib` (such as `libswiftCompatibilitySpan.dylib`),
   preserving identifiers and entitlements.
4. Discovers every Mach-O framework binary and `*.dylib` under `Contents/Frameworks/`,
   computes the `cdhash` for each shipped slice (`lipo -archs` intersected with
   `RASC_RC_ARCHS`), validates the LLC with `codesign --validate-constraint`, and
   re-signs the outer app bundle (without `--deep`) with `--library-constraint` +
   the expanded entitlements.
5. Deep-verifies (`codesign --verify --deep --strict`), asserts `Has Library Load Constraints`,
   re-checks every embedded library/dylib `cdhash` against `library-constraint.plist`,
   re-verifies `VoiceModelDownloader.xpc` entitlements, and refuses to package if any check fails.
6. Writes the DMG + `.sha256` (and optionally runs `notarytool` + `stapler` + `spctl --assess`
   when `RASC_SIGNING_IDENTITY` and `RASC_NOTARY_PROFILE` are configured).

Routine builds take the public key from the **login keychain** account
`rasc-sparkle` (see the key ceremony below) via `generate_keys -p --account`.
No raw private-key file is required for routine signing.

Environment overrides:

- `RASC_RC_VERSION=…` and `RASC_RC_BUILD=…` (default: project settings)
- `RASC_RC_OUTPUT_DIR=…` (default: `build/updater-rc/<version>`)
- `RASC_RC_ARCHS="arm64 x86_64"` (default `arm64`)
- `RASC_SIGNING_IDENTITY=…` (default `-` ad-hoc) and `RASC_NOTARY_PROFILE=…` (optional notarytool profile)
- `RASC_RC_FEED_URL=…` (default `https://rasc.app/appcast.xml`)
- `RASC_RC_ED25519_PUBLIC_KEY=…` (rarely needed; normally comes from the keychain)
- `SPARKLE_ACCOUNT=…` (default `rasc-sparkle`)
- `RASC_RC_ED25519_ENFORCE=0` — build an intentionally inert candidate

Notes on appcast verification (`Scripts/sparkle-proof/verify-appcast.py`):
it automatically resolves OpenSSL 3 (`OPENSSL_BIN`, Homebrew `/opt/homebrew/opt/openssl@3/bin/openssl`, `/usr/local/opt/openssl@3/bin/openssl`, or `PATH`) so macOS LibreSSL on `/usr/bin/openssl` does not break Ed25519 `pkeyutl` verification.

```bash
./Scripts/release/build-updater-rc.sh                     # uses keychain account rasc-sparkle
RASC_RC_VERSION=0.1.8 RASC_RC_BUILD=14 ./Scripts/release/build-updater-rc.sh
```

`build/updater-rc/<version>/` is gitignored.

## Appcast for versioned GitHub Release assets

```bash
./Scripts/release/generate-release-appcast.sh \
  --version 0.1.8 \
  --prefix https://github.com/rafaeltorresng/rasc/releases/download/v0.1.8/ \
  --dmg build/updater-rc/0.1.8/Rasc-0.1.8-updater.dmg \
  --account rasc-sparkle
```

Key properties of `generate-release-appcast.sh`:

- Accumulates `build/updater-rc/feed/{*.dmg,appcast.xml}` across releases —
  re-running for the next release keeps every existing entry and appends the
  new one. `generate-release-appcast.sh` asks Sparkle to preserve all appcast
  versions and generate deltas for the six supported prior builds. It also
  restores each existing enclosure's original versioned GitHub URL after
  Sparkle applies the current prefix to every archive.
- Signs enclosures with the login-keychain `rasc-sparkle` account via
  `generate_appcast --account` — no raw key file.
- Immediately verifies with `verify-appcast.py` (Ed25519 signatures + lengths,
  tamper rejection with one byte flipped at offset 1024) against the derived
  public key read out of the login keychain; no public-key file required.
- Uploads nothing. Publishing remains a maintainer step.

`--prefix` used above is a **versioned GitHub Release asset** base URL. The DMG
in that URL is exactly the DMG you attach to release `v0.1.8`, so Sparkle's
EdDSA verification and the GitHub download URL agree by construction.

The first updater release (v0.1.7) shipped no delta: there was exactly one DMG
in the archives folder, so `generate_appcast` emitted no delta section. The
accumulated `feed/` folder yielded the published v0.1.7 → v0.1.8 delta
(`Rasc14-13.delta`).

## Update flow a user exercises

```
v0.1.5 DMG download → Gatekeeper → Open Anyway (first run only for unsigned builds)
  → in-app: Rasc menu → Check for Updates…
  → Sparkle fetches appcast from rasc.app (HTTPS)
  → downloads DMG from the GitHub Release asset referenced in the appcast
  → EdDSA-verifies it, extracts, replaces /Applications/Rasc.app
  → relaunches as the new version
  → notes, shortcuts, preferences preserved
```

Updates are **manual**. `SUEnableAutomaticChecks=false`, `SUAutomaticallyUpdate=false`,
`SUAllowsAutomaticUpdates=false` — both stay that way for this release.

## Clean-machine verification (mandatory before publishing)

No clean Apple Silicon machine or VM was available for the early RC phases. The
steps below were first executed on a MacBook Pro (this Mac, macOS 26.5.1) and
then repeated by the maintainer on a MacBook Air (reported as "Air M4");
record exact `sw_vers` for each. **No macOS version other than 26.5.1 has been
exercised**, so macOS 14 support is undefined until a 14.x machine passes.

Recommended final procedure for the shipping artifact — two separate paths in
strict order:

**Path A — Sparkle in-app update (staging source below the shipping build):**

1. `sw_vers` and `sysctl -n machdep.cpu.brand_string`; record OS + chip.
2. Pick a staging source build with **`CFBundleVersion` strictly lower** than the
   shipping build (e.g. build 11 if shipping 12). Build it with the *same*
   `rasc-sparkle` key: the pipeline uses `generate_keys -p --account rasc-sparkle`,
   no manual Info.plist editing is needed. Set the staging HTTPS feed URL in
   `SUFeedURL` at build time via `RASC_RC_FEED_URL=https://<staging>/appcast.xml`.
   Use a separate directory for the staging build (e.g. `build/staging-source/`)
   and a separate directory for the feed; do not reuse paths from RC staging.
3. Install the staging-source DMG via a browser download (quarantine present);
   drag into `/Applications`; Open Anyway on the unsigned app; confirm it runs
   with the empty state of the real user's account (clone or fresh user).
4. Create 3–4 notes, pin one, change theme (e.g. to `rascDark`), change the
   scratchpad shortcut (e.g. ⌥\ → ⌥-Shift-\); record `activeNoteID`.
5. Serve a staging feed over HTTPS with a publicly trusted certificate. Put the
   **shipping DMG unchanged** in the feed folder. Run **Check for Updates…**;
   expect the **Settings/Update** prompt as usual; press **Install Update**; the
   app relaunches at the shipping version; notes, preferences, shortcuts and
   visible active note must be identical.
6. Verify at relaunch: `vmmap`/`lsof` show Sparkle mapped;
   `codesign -dvvv …Rasc.app | grep -A3 "Library Load"` shows
   `Has Library Load Constraints`; `codesign --verify --deep --strict` of the
   installed app passes; `spctl --assess -vv /Applications/Rasc.app` returns the
   expected "rejected" line verbatim.
7. **Tamper rejection**: swap the served DMG for one with a single byte flipped
   at offset 1024 (same length). Install → expect "The update is improperly
   signed and could not be validated…" (record verbatim), and the app must
   remain on the staging source version. Quit, restore the genuine DMG, verify
   again.

**Path B — v0.1.5 → shipping build (one-time manual migration):**

1. Stay on the same fresh user account. Download the public `v0.1.5` DMG from
   the Release page; install; Open Anyway; relaunch; confirm notes/preferences
   persist.
2. Replace the app manually (drag `Rasc.app` from the shipping DMG into
   `/Applications`, choosing Replace). Relaunch; confirm notes/preferences/short.

**Path C — public build → next build in-app:** the updater is public, so the
normal upgrade path must be exercised for every release. Record the exact source
and target builds in the release notes; do not infer completion from publication.

1. On the same fresh user account, install the published v0.1.7/build 13 DMG
   from the GitHub Release (browser download → `/Applications` → Open Anyway).
2. Create a few notes, keep one, change theme and scratchpad shortcut; record
   `activeNoteID`.
3. Serve the v0.1.8 shipping DMG from a staging feed and run **Check for
   Updates…**; expect v0.1.8 (build 14 > 13) to be offered.
4. Install and relaunch; confirm notes, preferences, shortcuts and the visible
   active note are unchanged. Repeat the tamper-rejection check from Path A.
5. Click empty space in the home list and confirm no focus-ring lines appear.

Any failure here is a release blocker.

## Production key ceremony (one-time; completed for v0.1.7)

Use Sparkle's official tools only. Do not generate the key with OpenSSL, and do
**not** hand-carry any PEM or raw key file.

```bash
# One time, on the maintainer's Mac:
build/sparkle-tools/bin/generate_keys --account rasc-sparkle

# No further step is required. The release pipeline reads the public key from
# your login keychain at every build and stamps it into the packaged app —
# do NOT paste it into Rasc/Info.plist manually.

build/sparkle-tools/bin/generate_keys -x <secure-destination> --account rasc-sparkle
# <secure-destination> is anything you control: an encrypted disk image on a
# separate device, a password manager attachment, or a second Mac's keychain
# (with -f re-import). Never the Desktop, never the repo, never a cloud folder,
# never logs/notes/pasteboard.
```

**Do not edit `Rasc/Info.plist` after key generation.** The placeholder
`SUPublicEDKey = REPLACE_WITH_ED25519_PUBLIC_KEY` is intentional and stays as is.

To restore the key on another machine (or after an accident):

```bash
build/sparkle-tools/bin/generate_keys -f <secure-destination> --account rasc-sparkle
```

### Verify the packaged public key matches the keychain value

```bash
build/sparkle-tools/bin/generate_keys -p --account rasc-sparkle
/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' ./export/Rasc.app/Contents/Info.plist
```

Both strings must match exactly. The release pipeline embeds the value from
your login keychain in every updater build, so this check is redundant by
construction; run it anyway as a belt‑and‑braces sign‑off before publishing.

Routine signing never touches a raw private key file. Sparkle's own tools read
the login keychain directly; only packaging reads Info.plist (and it prints the
decision to the build log).

## Publish / order-of-operations (only after the clean-machine pass)

1. `xcodebuild test` green.
2. `RELEASE.md` version notes updated; `docs/RELEASE-NOTES-v<version>.md` written
   with the Open-Anyway explanation.
3. Build the final updater DMG; record `shasum -a 256`; attach DMG + `.sha256`
   to the GitHub Release `v<version>`.
4. Re-download the DMG from the release URL; re-verify lengths + signatures with
   `verify-appcast.py --account rasc-sparkle --feed <downloaded-files>`.
5. Only then upload `appcast.xml` to the `rasc.app` website repository and deploy
   it.
6. Only then change the website download link.

**6b. Mandatory post-deploy smoke test.** As soon as deploy is live: on a clean account with the
shipped DMG installed, press "Check for Updates…" and expect
**"Already up to date"** (or equivalent non-error), not
"An error occurred in retrieving update information." If an error is shown, the
feed or the appcast is wrong — revert deployment before announcing anything,
and do not change the website download link until a clean smoke succeeds.

## Why not Developer ID + notarization (yet)

Developer ID Application + notarization can reduce Gatekeeper friction and is
the preferred path if the maintainer joins the Apple Developer Program. None of
these ad-hoc artefacts are required if that path is taken; the LLC work is zero
cost and can remain as belt-and-braces.

## Key rotation / disaster recovery

- If the production private key is lost: ship a release that carries a new
  public key together with an updater-only refusal-of-update guard; every prior
  user cannot receive an automatic update and must download once more manually.
- If the key leaks: rotate immediately (new account `rasc-sparkle-v2`), ship a
  new public key, delete the old one from every keychain you control; treat the
  leak as a compromise for supply-chain analysis purposes — all previous update
  history must be re-verified.
- Always keep `SUVerifyUpdateBeforeExtraction=true`.

## Known limitations and honest status (as of 2026-11-17)

- The updater has been exercised on two Apple silicon machines, both running
  macOS 26.5.1 (`MACOSX_DEPLOYMENT_TARGET=14.0` remains supported). No other
  macOS version has been exercised. Treat macOS 14-25 support as **unverified**
  and say so in release notes.
- The `disable-library-validation` entitlement is an opt-out; reviewers must
  confirm the LLC pins every shipped architecture (done by the pipeline) and
  that the default Release build remains without it.
- `SUEnableAutomaticChecks=false`, `SUAutomaticallyUpdate=false`,
  `SUAllowsAutomaticUpdates=false`: updates are always manual. Do
  **not** flip them for this release.
- `activeNoteID` (classic defaults domain) is not expected to survive relaunch;
  convenience state, not user data. Notes, preferences, shortcuts survive.

## Decision checklist before publishing

The v0.1.15 candidate passed local build verification; it is not published yet.
The checklist below remains the publication gate for each next candidate;
completed run records belong in the release notes.

- [ ] `xcodebuild test` green; `RELEASE_NOTES-v<version>.md` written (Open-Anyway note present)
- [ ] Clean-machine pass of every step in the checklist above, on macOS 14.x as well as the deployment target if accessible
- [ ] Production key generated with named account (`rasc-sparkle`), held in the
     login Keychain only, never exported. No offline backup exists at this point
     and none is scheduled — losing the key would force every user to download
     a fresh DMG once. Not treated as a release blocker.
- [ ] Staging artifacts deleted or moved out of the working tree; no RC key/material remains in source
- [ ] GitHub Release assets attached before the feed change; feed change before the download link
- [ ] Website download link changed only after the feed is live and verified
- [ ] `git status --porcelain` shows only the intended files; no `build/`

## Current status (2026-11-27)

- **Latest final local RC (`0.1.16`, build `22`, commit `30c5c14`):** Built cleanly in
  `build/updater-rc/0.1.16-final-rc` (`Rasc.app` `46,660,045 B` / `44.50 MiB`;
  `Rasc-0.1.16-updater.dmg` `13,782,657 B`, SHA-256
  `208d426e4448c6de918b712e7947a84a6631cb7954a1b9055ac76c188a8c839f`) while keeping
  `build/updater-rc/0.1.15` and `build/updater-rc/0.1.16` untouched. Passed
  `verify-rc-bundle.sh`, `codesign --verify --deep --strict`, `Has Library Load Constraints`
  pinning both `Sparkle` (`0e66f4ed0b19cb8b52fd8063740ba80e1481366a`) and
  `libswiftCompatibilitySpan.dylib` (`c3228a12b0782b9b402391c99f9627f4c9e2456b`), zero
  `network.client` on main app, isolated `VoiceModelDownloader.xpc` entitlements,
  staging Ed25519 appcast + `Rasc22-21.delta` (`3,378,602 B`) + `--tamper` rejection, and
  an isolated `0.1.15 → 0.1.16` sandboxed container upgrade (`com.rafaeltorres.rasc.rcverify`:
  `v11_scale_indexes_and_origin` applied, seeded notes/revisions/FTS preserved, 15s standby
  `31 MB` / `0.0%` CPU, personal DBs unchanged). Ad-hoc signed & unnotarized; Developer ID
  and macOS 14–25 verification remain open.
- **Candidate (local, not published):** v0.1.15/build 21, source merge `9a9b471`
  ([PR #96](https://github.com/rafaeltorresng/rasc/pull/96)), DMG
  `Rasc-0.1.15-updater.dmg`, SHA-256
  `145d4a94759233f91e50bd1200b07749a4759a440efd33a86558623edac2e443`, with six
  `Rasc21-*` deltas (builds 15–20). Local `xcodebuild test` passed. Deep
  codesign, LLC, main-app no-network, and `VoiceModelDownloader.xpc`
  `network.client` checks passed. Staging appcast verification passed with
  OpenSSL 3 on `PATH`; seed the working feed from the live eight-entry production
  appcast before publishing. Clean-machine Sparkle UI, post-deploy smoke, and
  macOS 14–25 remain open. See [RELEASE-NOTES-v0.1.15.md](RELEASE-NOTES-v0.1.15.md).
- **Published:** v0.1.14/build 20, source on
  [PR #94](https://github.com/rafaeltorresng/rasc/pull/94) (the personalization
  merge from #93 plus the version bump), DMG `Rasc-0.1.14-updater.dmg`, SHA-256
  `f8c7d079cdf8a589556713a4dd3d7118a7582a465a4ae5c553474e6b2cd9f9b4`, with
  six `Rasc20-*` deltas. GitHub Actions runs `45308334979` and `45308356169`
  passed the Debug build, 486 domain checks plus the scale benchmark, the full
  native suite and the Release build. The appcast retains v0.1.7–v0.1.13 with
  their original versioned URLs; all eight entries are byte-identical to the
  previous feed for the seven historical versions. Signatures, lengths and
  tamper rejection passed. See [RELEASE-NOTES-v0.1.14.md](RELEASE-NOTES-v0.1.14.md).
- **Native update check:** an isolated build 19 app (bundle identifier
  `com.rafaeltorres.rasc.isolatedtest`, own container, three synthetic notes)
  checked for updates over a temporary public HTTPS staging feed. Sparkle
  offered 0.1.14/build 20, verified and installed it, and relaunched at build
  20 with all three synthetic notes byte-identical, the isolated container and
  the Library Load Constraint intact. A one-byte-flipped DMG was rejected by
  Sparkle with “The update is improperly signed and could not be validated” and
  the app stayed on build 19. The user's installed app and notes
  were not involved.
- The public release assets were downloaded and byte-matched; the website
  download link and appcast were checked after publication. GitHub Pages runs
  `45310336475` (appcast) and `45310606975` (release facts) passed, and the live
  appcast is byte-identical to the verified eight-entry file. A post-deploy
  in-app check on the live feed reported “You’re up to date!” on build 20.
  macOS 14–25 remain unverified.
- **Previous:** v0.1.13/build 19, source commit `c3ce2a1`, DMG
  `Rasc-0.1.13-updater.dmg`, SHA-256
  `bf324171fc1fe535c9615f56d4083300ea72f45279e8b5327d1ea3b993fa2cae`, with
  six `Rasc19-*` deltas. GitHub Actions run `45246536033` passed. Its appcast
  retains v0.1.7–v0.1.12. Its live in-app update and clean-account post-deploy
  smoke were not performed because that publishing environment had no usable
  interactive display.
- **Previous:** v0.1.12/build 18, behavioral source tip `6bdd410`, DMG
  `Rasc-0.1.12-updater.dmg`, SHA-256
  `64637dc077e9f882a2154ea3d710bf76ab23687738fef6f2e2c7148ccfa0805c`.
- **Previous:** v0.1.11/build 17, built from source commit `0e7aa69`, DMG
  `Rasc-0.1.11-updater.dmg`, SHA-256
  `baf11bd0cc4e2774987910d48eba8bc63e986a27acd0e1eac2bddf0db1f54067`. The
  GitHub Release carries the DMG, `.sha256` sidecar and the four `Rasc17-*`
  deltas; the production feed serves versioned GitHub Release enclosures. Final
  appcast signatures and tamper rejection passed `verify-appcast.py`.
- **Previous:** v0.1.10/build 16, built from source commit `6873641`, DMG SHA-256
  `7519ab01ebe7aa50af8a5656f80f2ebca81ec0bc706f75335a22a45b1d22ce22`. v0.1.9/build 15, built from source commit `8fae4fd`, DMG SHA-256
  `97c0527a20c8da0faab58885c38af41683cb90c3debba1cdd791b09d00a9912d`, with
  `Rasc15-14.delta` and `Rasc15-13.delta`. v0.1.8/build 14 and v0.1.7/build 13
  remain in the feed for older upgrades.
- **Historical:** Path A (staging source below build 12 → updater DMG, Sparkle
  offered the update, rejected a tampered DMG, installed in place, preserved the
  test note) and Path B (public v0.1.5 replaced manually in a Finder drag-and-drop)
  both passed on the M4 Air, macOS 26.5.1. Path B involves no Sparkle and no
  signature check.
- **Native update evidence:** an installed v0.1.9 with synthetic data was upgraded
  in-app to v0.1.10 using `Rasc16-15.delta` and a local feed; Sparkle installed
  and relaunched, preserving notes, theme and shortcuts. Native screenshots of
  Home, onboarding, Finder icon and menu bar are in
  `docs/validation/rasc-twin-fish/`.
- **Open verification:** clean install from the published DMG and tamper rejection
  through the live UI remain unverified for this release.
- **macOS 14–25 remain unverified**; only macOS 26.5.1 has been exercised.
- For v0.1.11, the local `xcodebuild test` runner was blocked by LaunchServices;
  the documented fallback passed 434 domain tests plus the scale benchmark. CI
  passed both `macos` checks on PR #84.
- The keychain key is not backed up offline and none is scheduled; losing it
  would force all users to download a fresh DMG once.

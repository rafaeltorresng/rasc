# Installing Rasc without notarization

The published Rasc release is distributed as an **ad-hoc signed DMG**, not a
**notarized** Developer ID build. The app is still built from the open-source
project; macOS simply cannot tie it to a registered Apple developer.

## Before you start

- **App:** the published release is **v0.1.14, build 20**, an Apple silicon DMG for
  macOS 14 or later. It is ad-hoc signed and not notarized.
- **Refine:** additionally requires macOS 26 or later, an Apple Intelligence-capable
  Mac, Apple Intelligence enabled, and its on-device model ready. Capture, Keep,
  Home and Search work without it.
- **Building from source:** requires Xcode 26.2 or later, Swift 6 and the macOS 26
  SDK. See [Build and test](../README.md#build-and-test).

## Install the published DMG

1. Download `Rasc-0.1.14-updater.dmg` and `Rasc-0.1.14-updater.dmg.sha256` from the
   [official v0.1.14 release](https://github.com/rafaeltorresng/rasc/releases/tag/v0.1.14).
   Keep both files in the same folder.
2. Verify the checksum:

   ```sh
   shasum -a 256 -c Rasc-0.1.14-updater.dmg.sha256
   ```

   The command should report `Rasc-0.1.14-updater.dmg: OK`. The published SHA-256 is
   `f8c7d079cdf8a589556713a4dd3d7118a7582a465a4ae5c553474e6b2cd9f9b4`.
   Download both files again if it does not match.

3. Open the DMG and drag **Rasc** to Applications.
4. **First launch:** Finder may say the app cannot be opened because the developer
   cannot be verified. Either:
   - **Right-click** (or Control-click) **Rasc** in Applications → **Open**, then confirm; or
   - **System Settings → Privacy & Security**. Scroll down to the **Security** section. **Open Anyway** appears there only after macOS has blocked an attempt to open Rasc. Choose it for Rasc.

5. Later launches work normally from the menu bar.

## Updates in ad-hoc builds

Rasc 0.1.7 and later include Sparkle for **manual** Check for Updates. Nothing
downloads or installs silently. The v0.1.5 release and the v0.1.6 pre-release
have no updater: download the v0.1.14 DMG once and install it by hand. To replace
an older build by hand, quit Rasc, verify the new DMG, drag **Rasc** to Applications
when Finder offers to replace it, and reopen; notes, preferences and shortcuts are
preserved. The updater has been exercised on macOS 26.5.1; behavior on macOS 14–25
remains unverified. See [SPARKLE-RELEASE.md](SPARKLE-RELEASE.md) and the
[v0.1.14 release notes](RELEASE-NOTES-v0.1.14.md).

A matching checksum verifies the file against the published checksum; it does not
establish notarization or independently prove authenticity. See [Apple’s guidance
on opening an app from an unidentified developer](https://support.apple.com/guide/mac-help/open-a-mac-app-from-an-unidentified-developer-mh40616/mac).

## Build from source

If you prefer to build the app yourself, use Xcode 26.2 or later:

```sh
git clone https://github.com/rafaeltorresng/rasc.git
cd rasc
open Rasc.xcodeproj
```

Run the **Rasc** scheme (Debug is fine for personal use). See
[Build and test](../README.md#build-and-test) for command-line builds and tests.
Debug builds and the packaged app use separate note stores; see
[Data and privacy](DATA-AND-PRIVACY.md) before switching between them.

## Privacy

Rasc does not require an account. Notes stay on your Mac. See [Data and privacy](DATA-AND-PRIVACY.md).

## Not a security bypass

Only install DMGs whose SHA256 you verified from the official release page. Do not disable
Gatekeeper globally or use third-party “crack” tools to open unknown binaries.

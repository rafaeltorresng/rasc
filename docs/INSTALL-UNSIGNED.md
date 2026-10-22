# Installing Rasc without notarization

The release files labeled **unsigned** contain an **ad-hoc signed app**, not a
Developer ID-signed or **notarized** build. macOS may block the first launch because
it cannot verify the developer or check the app for malicious software.

## Before you start

- The published DMG requires an **Apple silicon Mac running macOS 14 or later**.
- **Refine** additionally requires macOS 26 or later, an Apple Intelligence-capable
  Mac, Apple Intelligence enabled, and its on-device model ready. Capture, Keep,
  Home and Search work without it.
- Installing the DMG does **not** require Xcode. Building from source requires
  **Xcode 26.2 or later**, Swift 6, and the macOS 26 SDK.

## Install the unsigned DMG

1. Download `Rasc-0.1.2-unsigned.dmg` and `Rasc-0.1.2-unsigned.dmg.sha256` from the
   [official v0.1.2 release](https://github.com/rafaeltorresng/rasc/releases/tag/v0.1.2).
   For other versions, use [GitHub Releases](https://github.com/rafaeltorresng/rasc/releases)
   and download the DMG and checksum from the same release.
2. Save both files in the same folder. In Terminal, change to that folder (for
   example, `cd ~/Downloads`) and verify the checksum:

   ```sh
   shasum -a 256 -c Rasc-0.1.2-unsigned.dmg.sha256
   ```

   Continue only if the command reports `Rasc-0.1.2-unsigned.dmg: OK`. If a file
   cannot be found, check the folder and filenames. If the checksum fails, do not
   open the DMG; download both files again from the official release. For another
   version, substitute that version's checksum filename in the command above.

3. Open the DMG and drag **Rasc** to Applications, then open **Rasc** from
   Applications.
4. If macOS blocks it because the developer cannot be verified or Apple cannot
   check it for malicious software, and you trust the download, open **System
   Settings → Privacy & Security**. Scroll to the Rasc message, click **Open
   Anyway**, and confirm **Open** when prompted. This option appears after you
   attempt to open the app. See [Apple's first-launch guidance](https://support.apple.com/en-us/102445).
5. Once open, Rasc lives in the menu bar, with no Dock icon. After quitting, open
   it again from Applications.

A matching checksum confirms that the download matches the published file; it is
not a security review or notarization. If macOS reports malware or a damaged app,
do not bypass that warning; see the Apple guidance above. Do not disable Gatekeeper
globally to install Rasc.

## First use

Follow [Your first thought](../README.md#your-first-thought) to capture, keep and
retrieve a thought.

## Build from source

If you prefer to build the app yourself, use Xcode 26.2 or later:

```sh
git clone https://github.com/rafaeltorresng/rasc.git
cd rasc
open Rasc.xcodeproj
```

Select the **Rasc** scheme and run a Debug build. See [Build and test](../README.md#build-and-test)
for command-line builds and tests. Debug builds and the packaged app use separate
note stores; see [Data and privacy](DATA-AND-PRIVACY.md) before switching between them.

## Privacy

Rasc does not require an account. Notes stay on your Mac. See [Data and privacy](DATA-AND-PRIVACY.md).

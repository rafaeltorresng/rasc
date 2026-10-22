# Installing Rasc without notarization

Some Rasc releases are distributed as an **ad-hoc signed DMG**, not a **notarized**
Developer ID build. The app is still built from the open-source project; macOS simply
cannot tie it to a registered Apple developer.

## Before you start

- The published DMG requires an **Apple silicon Mac running macOS 14 or later**.
- **Refine** additionally requires macOS 26 or later, an Apple Intelligence-capable
  Mac, Apple Intelligence enabled, and its on-device model ready. Capture, Keep,
  Home and Search work without it.
- Installing the DMG does **not** require Xcode. Building from source requires
  **Xcode 26.2 or later**, Swift 6, and the macOS 26 SDK.

## Recommended: build from source

If you have Xcode, this avoids Gatekeeper friction and matches the MIT license:

```sh
git clone https://github.com/rafaeltorresng/rasc.git
cd rasc
open Rasc.xcodeproj
```

Run the **Rasc** scheme (Debug is fine for personal use). See the repository README for tests.

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

3. Open the DMG and drag **Rasc** to Applications.
4. **First launch:** Finder may say the app cannot be opened because the developer
   cannot be verified. Either:
   - **Right-click** (or Control-click) **Rasc** in Applications → **Open**, then confirm; or
   - **System Settings → Privacy & Security** → **Open Anyway** for Rasc.

5. Later launches work normally from the menu bar.

## First use

Follow [Your first thought](../README.md#your-first-thought) to capture, keep and
retrieve a thought. Rasc runs in the menu bar, with no Dock icon.

## Privacy

Rasc does not require an account. Notes stay on your Mac. See [Data and privacy](DATA-AND-PRIVACY.md).

## Not a security bypass

Only install DMGs whose SHA256 you verified from the official release page. Do not disable
Gatekeeper globally or use third-party “crack” tools to open unknown binaries.

# Installing Rasc without notarization

Some Rasc releases are distributed as an **ad-hoc signed DMG**, not a **notarized**
Developer ID build. The app is still built from the open-source project; macOS simply
cannot tie it to a registered Apple developer.

## Recommended: build from source

If you have Xcode, this avoids Gatekeeper friction and matches the MIT license:

```sh
git clone https://github.com/rafaeltorresng/rasc.git
cd rasc
open Rasc.xcodeproj
```

Run the **Rasc** scheme (Debug is fine for personal use). See the repository README for tests.

## Install the unsigned DMG

1. Download `Rasc-0.1.3-unsigned.dmg` and `Rasc-0.1.3-unsigned.dmg.sha256` from the
   GitHub Release for the version you trust.
2. Verify the checksum:

   ```sh
   shasum -a 256 -c Rasc-0.1.3-unsigned.dmg.sha256
   ```

3. Open the DMG and drag **Rasc** to Applications.
4. **First launch:** Finder may say the app cannot be opened because the developer
   cannot be verified. Either:
   - **Right-click** (or Control-click) **Rasc** in Applications → **Open**, then confirm; or
   - **System Settings → Privacy & Security** → **Open Anyway** for Rasc.

5. Later launches work normally from the menu bar.

## Privacy

Rasc does not require an account. Notes stay on your Mac. See [Data and privacy](DATA-AND-PRIVACY.md).

## Not a security bypass

Only install DMGs whose SHA256 you verified from the official release page. Do not disable
Gatekeeper globally or use third-party “crack” tools to open unknown binaries.

# Rasc Private Beta Distribution (M6B / M11)

> Historical specification/milestone reference. For current behavior, launch direction and superseded decisions, start with [CURRENT-PRODUCT](CURRENT-PRODUCT.md) and the [documentation index](README.md).


This path produces a repeatable private-beta `.dmg` for trusted testers **without** an Apple Developer Program membership.

It is separate from the future Developer ID / notarization workflow documented in [RELEASE.md](RELEASE.md). Ad-hoc signing does **not** provide developer identity or Gatekeeper trust.

Tester-facing notes for **0.1.0-beta.1** are in [BETA-1-RELEASE-NOTES.md](BETA-1-RELEASE-NOTES.md).

## Build (maintainers)

Prerequisites:

1. Xcode with Swift packages resolved (open the project once).
2. No Apple Developer credentials required.
3. Set `BetaFeedback.recipientEmail` in `Rasc/Platform/BetaFeedback.swift` before distributing.

Run tests, then build and verify:

```bash
xcodebuild test \
  -project Rasc.xcodeproj \
  -scheme Rasc \
  -destination 'platform=macOS'

./Scripts/release/build-private-beta.sh
./Scripts/release/verify-private-beta.sh build/private-beta/Rasc-0.1.0-beta.1.dmg
git diff HEAD --check
```

Example artifacts (version comes from `MARKETING_VERSION` in the Xcode project):

- `build/private-beta/export/Rasc.app`
- `build/private-beta/Rasc-0.1.0-beta.1.dmg`
- `build/private-beta/Rasc-0.1.0-beta.1.dmg.sha256`

The build script:

- compiles Release with App Sandbox and Hardened Runtime
- ad-hoc signs the app (`codesign --sign -`)
- packages a simple DMG (`Rasc.app` + `Applications` alias)
- writes a SHA-256 checksum alongside the DMG

## Verify download integrity (testers)

After downloading the DMG and checksum file to the same folder:

```bash
shasum -a 256 -c Rasc-0.1.0-beta.1.dmg.sha256
```

You should see `OK` when the file matches what the maintainer produced.

## Install (testers)

1. Open `Rasc-0.1.0-beta.1.dmg` in Finder.
2. Drag **Rasc** into **Applications**.
3. Try to open Rasc from `/Applications`.

macOS may block the app on first launch because this private beta is **not** Developer ID signed or notarized. That is expected.

If you trust this build:

4. Open **System Settings → Privacy & Security**.
5. Scroll to the security message about Rasc and click **Open Anyway**.
6. Confirm **Open** when macOS asks again.

Do **not**:

- disable Gatekeeper globally
- run `spctl --master-disable`
- remove quarantine flags with Terminal
- change system-wide security policy

Use Apple's normal per-app override flow only.

## What this build is

| Property | Private beta | Future public release |
| --- | --- | --- |
| Signing | Ad-hoc (`-`) | Developer ID Application |
| Notarization | No | Yes |
| Gatekeeper on first launch | May require Open Anyway | Should open normally |
| Developer identity | None | Verified publisher |
| Sparkle / auto-update | No | Planned later |

## Fresh-install acceptance (testers)

Work through this on a Mac that has never run Rasc, or after removing `~/Library/Application Support/Rasc` and quitting Rasc.

1. Install from the DMG to `/Applications` and launch from Finder.
2. Complete onboarding (global shortcut, optional Launch at Login).
3. Press the global shortcut — scratchpad opens.
4. Create a note with meaningful text.
5. If Refine is available on your Mac, press `⌘J`, review preview, accept or cancel.
6. Open Home from the menu bar icon.
7. Search from Home and with `⌘P`.
8. Open the command palette with `⌘K`.
9. Quit Rasc (`⌘Q` or menu bar → Quit Rasc).
10. Relaunch from Finder — note content, Home, and window positions should persist.

**Refine unavailable:** On Macs without Apple Intelligence, skip step 5. Capture, Home, search, and history must still work.

## Existing-user upgrade acceptance (maintainers)

Before distributing, verify on a Mac that already has note data from a prior Rasc build:

1. Confirm existing notes, FTS search, refinement history, active note, Home, and window-frame persistence.
2. Install `0.1.0-beta.1` over the previous build.
3. Relaunch and confirm all data remains intact (no destructive migration).

Automated coverage: `NoteRepositoryTests.migratesM2DatabaseToRefinementRevisionsWithoutLosingNotes` and `opensExistingDatabaseAtCurrentSchemaWithoutDataLoss`.

## Manual beta smoke test

After installing to `/Applications`, verify:

- [ ] Launch Rasc from Finder (not Xcode)
- [ ] Menu bar icon appears
- [ ] Global shortcut opens Rasc
- [ ] Create a note
- [ ] Hide and reopen Rasc
- [ ] Quit and relaunch Rasc; note persists
- [ ] ⌘P search works
- [ ] ⌘K command palette works
- [ ] ⌘J Refine works on supported Apple Intelligence hardware
- [ ] Selection Refine works
- [ ] Fullscreen overlay works
- [ ] Window position persists
- [ ] Launch at Login can be enabled
- [ ] Send Feedback opens mail client
- [ ] Sleep/wake does not lose the panel
- [ ] Uninstall/reinstall does not corrupt note storage

Record failures with macOS version, display layout, and reproduction steps.

## Privacy

Rasc is local-first. This build does not include analytics or telemetry. Refine uses on-device Foundation Models when available. The only user-initiated off-device action is **Send Feedback…**, which opens the system mail client.

## Limitations

- Ad-hoc signing is for trusted private testing only.
- Testers may need to use **Open Anyway** once per downloaded copy.
- This path does not replace Developer ID signing, notarization, or Sparkle updates.
- Do not redistribute this build as if it were a signed public release.

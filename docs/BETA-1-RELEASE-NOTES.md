# Rasc 0.1.0-beta.1 — Private Beta Notes

## What is Rasc?

Rasc is a native macOS scratchpad for unfinished thoughts. Capture a note instantly, refine it on-device when Apple Intelligence is available, then get back to work. Your notes stay on this Mac.

## Requirements

| Requirement | Notes |
| --- | --- |
| macOS 14.0 or later | Required |
| Apple Intelligence | Required **only** for Refine (`⌘J`) |
| Internet | **Not required** — Rasc is local-first |

Without Apple Intelligence, capture, Home, search, and history still work normally.

## Install (unsigned private beta)

This build is ad-hoc signed and **not** notarized. macOS may block it on first launch.

1. Download `Rasc-0.1.0-beta.1.dmg` and `Rasc-0.1.0-beta.1.dmg.sha256`.
2. Verify integrity (optional but recommended):

   ```bash
   shasum -a 256 -c Rasc-0.1.0-beta.1.dmg.sha256
   ```

3. Open the DMG and drag **Rasc** to **Applications**.
4. Launch Rasc from `/Applications`.
5. If macOS blocks launch, open **System Settings → Privacy & Security** and click **Open Anyway**, then confirm **Open**.

Do **not** disable Gatekeeper or use Terminal workarounds.

## Key shortcuts

| Shortcut | Action |
| --- | --- |
| `⌥ \` (default) | Open / hide scratchpad |
| `⌘N` | New scratch |
| `⌘P` | Find note (quick search) |
| `⌘K` | Command palette |
| `⌘J` | Refine (when available) |
| `⌘,` | Settings |

The global shortcut can be changed in Settings.

## Send feedback

Use **Send Feedback…** from the menu bar icon or Settings. It opens your mail app with version and Mac details pre-filled.

**No note content is included.**

> Maintainer: set `BetaFeedback.recipientEmail` in `Rasc/Platform/BetaFeedback.swift` before distributing.

## Known limitations

- First launch may require **Open Anyway** because this beta is not Developer ID signed.
- No automatic updates yet (Sparkle planned for public release).
- Refine requires supported Apple Intelligence hardware and settings.
- Menu bar utility — no Dock icon by default.
- Private beta only; do not redistribute as a signed public release.

## Privacy

Rasc does not send note content, analytics, or telemetry off this Mac. Refine uses on-device Foundation Models when available. The only network-related action is opening your mail client when you choose **Send Feedback…**.

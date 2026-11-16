# Rasc 0.1.6 — Warm precision

Version: 0.1.6 · build 12 · Apple silicon · macOS 14+

- **Warm precision.** Paper/graphite neutrals across Scratchpad, Home, Search, Command Palette, Settings and onboarding. No hue changes to the brand or the Orb.
- **Keep is the only copper.** `#9C421F` on `#F5E5DA` (light) and `#F0A780` on `#382822` (dark). Keep icon, Keep confirmation and the Kept status use copper; everything else is neutral.
- **Functional text contrast.** Snippets, shortcuts, timestamps and section labels now clear 4.5:1 against the surfaces they appear on (canvas, raised fill, cards, selections).
- **Neutral selection** everywhere — Search rows, Command Palette rows, input focus border, row stroke — matching the new text roles.
- **Home is a compact chronological list.** Kept stays pinned at the top; chronological sections follow (Today, Yesterday, …). One-line title, single-line excerpt, right-aligned SF Pro monospaced timestamp. No grid toggle, no preview pane.
- **Command Palette is a real input.** Caret on open, `Type a command…` placeholder, shared shell with Search; Return runs the selected command; Esc closes.
- **Discard requires one extra Return.** Reached by filtering (not by arrows or clicking), the Discard row shows `↵ again to discard` until confirmed. Arrow keys or click commit immediately.
- **Word-boundary snippets** in search; no mid-word cuts, match always in view.
- **Panel sizes to content.** Search and the Command Palette shrink to fit the visible rows (132 pt floor) and restore to default size when you return to the editor.
- **Settings shortcuts** align to the same right edge, and the disabled per-shortcut `Restore Default` rows are hidden.
- **Search tip banner** simplified to `Search from anywhere` plus the `⌘P` keycap (no more repeated “Search thoughts”).

## Updating from 0.1.5

0.1.5 has no updater. **Download the 0.1.6 DMG once** from the GitHub Releases page; later releases will be delivered in-app.

- This build (and all 0.1.x builds) is ad-hoc signed and **not notarized**. The first launch may require **Open Anyway** (System Settings → Privacy & Security → Security, after a blocked attempt) or right‑click → **Open**.
- Once installed, updates are delivered inside the app. After launching 0.1.6, choose **Rasc → Check for Updates…**. Sparkle (2.9.4, pinned, loaded via a pinned Library Load Constraint) verifies the downloaded DMG against an Ed25519 signature and a SHA‑256 checksum **before** unpacking it. Updates are always manual — nothing is downloaded silently and nothing installs without your confirmation.
- A failed signature check rejects the whole DMG and leaves the running build untouched; updates are always reversible by reinstalling the previous DMG.
- Updating preserves your notes, shortcuts and preferences. Onboarding does not reappear for existing installs.

## Platform support for the updater

Rasc supports **macOS 14 or later**. The updater integration has been exercised end‑to‑end on **macOS 26.5.1** on two Apple silicon machines. The updater has **not** yet been exercised on macOS 14; the app itself still launches and works there, but an in‑place update on macOS 14 has not been verified and should be treated as beta until then.

## Verification

Final candidate SHA-256 (this artifact is approved for release assets): `8467c3611c3c2c55701dd0b7d8a8f070d417573b6f8ca81846098b177719ea5b`.
The `v0.1.6` tag identifies the source revision used for this artifact. The tag
must point at a commit whose tree is byte‑identical to the working tree used to
produce it; see `docs/SPARKLE-RELEASE.md` for the publish sequence.
Prior 0.1.x releases are retained unchanged.

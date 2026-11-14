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

Upgrading preserves notes, settings and shortcuts. Onboarding does not reappear for existing installs.

This release is ad-hoc signed and **not notarized**. Follow
[the unsigned install guide](INSTALL-UNSIGNED.md) for the first launch.

## Relverification

DMG SHA-256: recorded on the GitHub Release for `v0.1.6`.
The `v0.1.6` tag identifies the source revision used for this artifact.
Prior 0.1.x releases are retained unchanged.

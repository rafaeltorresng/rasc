# Rasc 0.1.4 — Images and lists in notes

Version: 0.1.4 · build 10 · Apple silicon · macOS 14+

- Paste screenshots and images into the scratchpad; images stay on their own lines, preview on Space, and save locally with the note.
- Bullet lists with `- ` at the start of a line, with undo and plain-text search projection preserved.
- Home can duplicate, copy, and share notes with images; duplicate waits for the active scratchpad to finish saving.
- SQLite migrations upgrade existing databases; editing text in image notes no longer rewrites the full image blob on every autosave.

Refine remains unavailable while a note contains images. Mixed notes copy as rich text (RTFD); destinations that accept only plain text may need a different paste path.

This release is ad-hoc signed and **not notarized**. Follow
[the unsigned install guide](INSTALL-UNSIGNED.md) for the first launch.

## Relverification

DMG SHA-256: recorded on the GitHub Release for `v0.1.4`.
The `v0.1.4` tag identifies the source revision used for this artifact.
Prior 0.1.x releases are retained unchanged.

# Rasc 0.1.0

Rasc is a small native Mac scratchpad for unfinished thoughts. Invoke it over your
work, capture a thought, optionally Refine its wording, Keep it and return to work.

## Highlights

- Local autosave, Home and prefix/diacritic-aware text search.
- Keep/Unkeep, Copy/Share and Discard with session Undo.
- Optional on-device Refine with whole-note/selection preview, Original comparison,
  explicit acceptance and Undo. No account, backend, telemetry or cloud fallback.
- Customizable capture shortcut, launch-at-login preference and light/dark themes.
- Save failures retain text; missing/discarded notes cannot silently report success.
- Orb rendering pauses when its window is hidden or occluded.

## Requirements

- **App:** Apple silicon, macOS 14 or later.
- **Refine:** macOS 26 or later, eligible Mac/region, Apple Intelligence enabled and
  on-device model ready. Rasc works without Refine. Compare Suggested with Original
  before accepting; suggestions can change meaning or uncertainty.

There is no sync, cloud inference, folders, tags, built-in export/backup, Trash
screen or automatic update system. Discard is not secure erasure. SQLite is not
encrypted by Rasc; see [Data and privacy](DATA-AND-PRIVACY.md). Release installs use
the sandboxed store; unsandboxed Debug data is separate.

## Install

**Build from source** (recommended) or use the **unsigned** DMG from this release
(`Rasc-0.1.0-unsigned.dmg`). macOS may block the first launch until you
**Right-click → Open** or allow the app in **Privacy & Security**.
[Step-by-step](INSTALL-UNSIGNED.md).

| Action | Default shortcut |
| --- | --- |
| Invoke or hide scratchpad | `⌥\` |
| Keep and return to work | `⇧⌘K` |
| Search thoughts | `⌘P` |
| Home | `⌘⌥\` |

## Release metadata

Fill from the verified artifact immediately before publishing:

| Field | Value |
| --- | --- |
| Version / build | 0.1.0 (6) |
| Source revision | _git SHA at build tag_ |
| Git tag | `v0.1.0` |
| DMG filename | `Rasc-0.1.0-unsigned.dmg` |
| SHA256 | _from `build/releases/Rasc-0.1.0-unsigned.dmg.sha256`_ |
| Signing | Ad-hoc (`-`) Release + hardened runtime + App Sandbox |
| Notarization | **None** (v0.1 ships without Apple Developer Program) |
| Install verification | _macOS version / hardware tested; Gatekeeper first-open documented_ |

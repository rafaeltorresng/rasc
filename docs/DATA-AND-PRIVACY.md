# Data, privacy and manual backup

Rasc works without an account or backend. Capture, autosave, Keep, Home and FTS
Search use a local SQLite database through GRDB. Refine uses the default on-device
Apple Foundation Models provider on eligible macOS 26+ systems. Each request uses a
new model session; there is no cloud fallback, analytics or Rasc network client.
The Release entitlement file enables App Sandbox without network access.

## Storage and retention

- Sandboxed Release: `~/Library/Containers/com.rafaeltorres.rasc/Data/Library/Application Support/Rasc/Rasc.sqlite`.
- Unsandboxed Debug: `~/Library/Application Support/Rasc/Rasc.sqlite`.
- These are separate stores. Installing a Release build does not import the
  unsandboxed development database automatically.
- Notes contain a UUID, text, creation and update dates, optional discard and
  Kept dates, a note `origin` (`scratch` or `dictation`), and an image indicator.
  Eleven ordered GRDB migrations (`v1`–`v11`) preserve earlier schemas. SQLite opens in
  WAL mode (`synchronous = NORMAL`, 5 s busy timeout), verifies `PRAGMA quick_check(1)`,
  refuses to open unknown newer schema versions without deleting user data (offering
  Retry / Reveal Data Folder / Quit Rasc), and runs `PRAGMA wal_checkpoint(TRUNCATE)` on
  app termination. Mixed thoughts store ordered text and original image bytes, with a
  separate text projection for search.
- FTS5 indexes note content with prefix matching and diacritic normalization.
  Discarded notes are filtered out of retrieval immediately; on app launch, soft-deleted
  notes older than 7 days and their `refinement_revisions` are permanently purged.
- Accepted refinements store both before and after text in `refinement_revisions`
  in the same transaction as the note update. There is no revision-browser UI.
- Discard is a soft deletion. In-session Undo is capped at the 50 most recent discards;
  recovery across restart and secure erasure are not product features.
- Rasc does not encrypt the database. FileVault, account security and system
  backups are managed by macOS/the user. No app-level encrypted vault is promised.
- UserDefaults stores preferences, window geometry, onboarding progress and the
  active note UUID, not note content. Runtime diagnostics contain timing/state
  labels rather than text. Historical eval tools can write synthetic input/output
  locally; they are DEBUG-only and excluded from the Release entry points.

## Voice Capture and Dictate

Voice Capture is off by default. Rasc requests microphone permission when you
explicitly start a recording. It activates the microphone only for that
recording, including a short end buffer. It stops before transcription and
releases the tap and engine. The current reliability candidate caps a recording at **2 minutes (120 seconds)** and
records microphone input only.

Fluid Speech Pro transcribes on this Mac using Core ML. The main app has no
network client for Voice Capture, no remote fallback and no speech or audio
telemetry. When you opt in and choose **Download Speech Model**, an embedded
sandboxed XPC helper (`com.rafaeltorres.rasc.VoiceModelDownloader.xpc`, holding
only `app-sandbox` and `network.client` entitlements) fetches only the pinned
model files into its own cache and passes read-only file handles back to Rasc.
Rasc verifies every file against the built-in byte size and SHA-256 manifest
before moving the pack into its Application Support folder. After installation,
transcription runs completely offline, and you can remove the installed model
from Settings to reclaim storage. A manual **Choose Model Folder…** import path
also remains available. Model preparation can occur without microphone access.

Audio stays in memory. After a recognition failure it can be retried for up to
two minutes, or discarded immediately. Audio recovery ends when Rasc quits or
crashes. For **Voice Capture**, Rasc saves the text as a regular unfinished thought
(`origin = .scratch`) in SQLite and opens it in Scratchpad. For **Dictate**, Rasc
requests Accessibility permission only when explicitly needed, writes to the focused
field via `AXSelectedText` without synthetic keystrokes (refusing Secure Input or
`AXSecureTextField` targets), or copies to the clipboard; if optional local history
saving is enabled, it persists the note with `origin = .dictation`.

## Manual backup

1. Use **Settings → General → Back Up Database…** to write a consistent SQLite
   snapshot (`DatabaseQueue.backup(to:)`) to a user-selected location without quitting
   Rasc.
2. Or quit Rasc normally (if it reports a failed save, keep it open and retry or copy
   the unsaved text before proceeding) and copy the entire `Rasc` Application Support
   folder (`Rasc.sqlite`, `Rasc.sqlite-wal`, `Rasc.sqlite-shm`). Do not copy raw
   database files manually while the app is running.
3. Keep backups private; they include any not-yet-purged discarded thoughts and refinement originals.
4. Before restoring, quit Rasc and retain a copy of the current folder as well.
   Restore a compatible backup to the same store. Never reset/delete a database
   as an error-recovery step. Opening a newer schema with an older binary is not
   guaranteed to work; keep the matching release artifact with the backup.

## Export and handoff

- Use **Export Thought…** in the Scratchpad command palette or a Home thought’s
  context menu. Text-only thoughts save as a Markdown text file. Thoughts with
  images save as a folder with the text file and its images.
- Use **Export Thoughts…** in the Rasc menu bar or command palette for Kept,
  All, or Selected thoughts. All includes unfinished thoughts. In Selected,
  search and check the thoughts you want. Your checks stay selected as you search.
- Collection folders contain one Markdown file per thought, any images in
  `assets`, and a `manifest.json` with IDs and dates. Mixed-note entries also
  record the order and UTF-8 byte ranges of original text parts. Keep the folder
  together so relative image links continue to work. If a destination only accepts
  individual files, attach the Markdown and images separately.
- Exports include current saved content and exclude discarded thoughts and
  refinement history. The app receives write access to the location you choose
  in the macOS panel. Export leaves the thoughts in Rasc and produces files you
  can open and move independently. Use the manual backup steps for recovery.

Copy and Share remain available for quick handoff to compatible applications.
Feedback opens an email draft with version information and never attaches notes.

Refine proposals may still change meaning or uncertainty. Review Suggested, or the
word-level Changes diff, against Original before accepting. Automated language/literal
checks have limited semantic coverage. The reliability candidate also checks
that common questions and drafting instructions preserve their form. Cancellation,
guard rejection and failed acceptance keep the original intact.
[Intent and frozen-corpus results](evidence/refine-web-data.json)

Isolated container upgrade (`0.1.15` → `0.1.16-final-rc` under `com.rafaeltorres.rasc.rcverify`)
and backup/restore round-trip tests verify `v10 → v11_scale_indexes_and_origin` schema integrity,
`notes` (`origin`), `refinement_revisions`, and `FTS5` search preservation with personal databases
byte-identical (`shasum -a 256` verified before and after).

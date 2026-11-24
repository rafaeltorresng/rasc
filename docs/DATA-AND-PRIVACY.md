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
  Kept dates, and an image indicator. Ten ordered GRDB migrations preserve
  earlier schemas. Mixed thoughts store ordered text and original image bytes,
  with a separate text projection for search.
- FTS5 indexes note content with prefix matching and diacritic normalization.
  Discarded notes are filtered out of retrieval; their rows/indexed content remain.
- Accepted refinements store both before and after text in `refinement_revisions`
  in the same transaction as the note update. There is no revision-browser UI.
- Discard is a soft deletion. Undo is available in the running session; recovery
  across restart and secure erasure are not product features.
- Rasc does not encrypt the database. FileVault, account security and system
  backups are managed by macOS/the user. No app-level encrypted vault is promised.
- UserDefaults stores preferences, window geometry, onboarding progress and the
  active note UUID, not note content. Runtime diagnostics contain timing/state
  labels rather than text. Historical eval tools can write synthetic input/output
  locally; they are DEBUG-only and excluded from the Release entry points.

## Voice Capture

Voice Capture is off by default. Rasc requests microphone permission when you
explicitly start a recording. It activates the microphone only for that
recording, including a short end buffer. It stops before transcription and
releases the tap and engine. Rasc caps a recording at 90 seconds. It records
microphone input only.

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
crashes. After transcription, Rasc saves the text as an ordinary unfinished
thought in SQLite and opens it in Scratchpad. Edits autosave through the usual
Scratchpad path. A pending transcript from an older preview migrates to an
unfinished thought. Rasc stores the text and regular note metadata. Capture
source is absent from the note record.

## Manual backup

1. Quit Rasc normally. If it reports a failed save, keep it open and retry or copy
   the unsaved text before proceeding.
2. Copy the entire `Rasc` Application Support folder from the relevant path above
   to a safe location. Include any `Rasc.sqlite-wal` and `Rasc.sqlite-shm` siblings.
   Do not copy only the main database while the app is running.
3. Keep backups private; they include discarded thoughts and refinement originals.
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
checks do not prove semantic equivalence. Cancellation and failed acceptance keep the
original intact.

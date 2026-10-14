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
- Notes contain UUID, content, creation/update dates, optional discard date and
  optional Kept date. Five ordered GRDB migrations preserve earlier schemas.
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

There is no built-in export, automatic backup or sync. Copy and Share are explicit
user handoffs to other applications. Feedback opens an email draft with version
information; it neither attaches notes nor sends the message automatically.

Refine proposals may still change meaning or uncertainty. Compare Suggested with
Original before accepting. Automated language/literal checks do not prove semantic
equivalence. Cancellation and failed acceptance keep the original intact.

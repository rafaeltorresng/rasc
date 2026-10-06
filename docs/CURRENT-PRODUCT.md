# Current Rasc product

**Source candidate:** 0.1.0-beta.4, build 5 · 5 October 2026.
This describes the implementation; it does not certify a public release.

Rasc is **a scratchpad for unfinished thoughts**: the place before the note.
The core flow is Invoke → Capture → optional Refine → Keep → return to work.
The project is intended to be open source under MIT. GitHub is source/transparency;
download remains the primary product action when a verified artifact is available.
Private-beta access requests, checkout and licensing are not current priorities.

## Lifecycle

- Invoke opens the panel with the current scratch. Capture does not require a title or destination.
- Autosave persists locally. Esc hides the panel and preserves the current scratch.
- Keep persists a kept timestamp, clears the active scratch and returns to work.
- Unkeep returns the thought to unfinished status. Copy and Share are explicit handoffs.
- Discard soft-deletes. Undo restores its content, original dates and Kept state while
  the repository/session remains alive. No Trash screen or recovery across restart
  is promised. A stale Undo receipt cannot restore a later discard.
- Undo never overwrites a newly typed scratch merely to bring back a discarded one;
  the restored thought remains available in Home.

## Refine

Foundation Models operates on-device on macOS 26+ when Apple Intelligence and its
model are available. The application itself supports macOS 14+. Capture, Keep and
retrieval do not depend on Refine availability.

Each request is isolated. A suggestion remains pending, with Suggested/Original
comparison. Selection previews show the whole note with only the selected passage
replaced. Keep original/Esc leaves the original intact. Accept suggestion persists
only after revision/snapshot validation and supports Undo.

Neutral confirmations can disappear; errors and instructions remain until dismissed
or the user changes the thought. Save failures take precedence over onboarding hints.

## Retrieval and keyboard behavior

Home separates Kept and temporal groups. Initially it shows the newest 12 Kept,
with explicit Show all/Show fewer access to every remaining Kept. Cards reserve
space for secondary actions to keep titles stable on hover.

Grid arrows follow rendered columns and section rows. Left/Right do not wrap;
Up/Down keep the column where possible. Search-field caret editing stays distinct
from grid navigation; Down or Return transfers focus to results.

Both retrieval surfaces use local FTS, not AI. Snippets prefer context around an
actual query term. Quick Search shows up to 12 results with a truncation hint;
Home Search shows up to 500 with a hint to narrow the query. The visible action is
Search thoughts (`⌘P`); legacy “find” remains a palette search alias.

## Presentation

SF proportional text at 16 pt is the editor and preview default; shortcuts retain
monospaced treatment. Shared surface metrics and motion stay centralized. Keep has
a restrained action accent. Text-safe violet is separate from Orb/selection color.

Brand symbol belongs to app identity. Orb belongs to writing, retrieval and shaping
states; see [brand contract](BRAND.md). Window geometry and the panel's fullscreen
level are retained until native evidence supports a change.

## Validation boundaries

Automated domain tests cannot validate VoiceOver, Full Keyboard Access, active-window
focus or Spaces. Native window suites and the [manual checklist](NATIVE-UI-VALIDATION.md)
remain required. UI render captures, if used, are layout evidence only.

No notes, clipboard contents or credentials belong in diagnostics. No backend,
cloud fallback, telemetry, account, sync, folders, tags, assistant or project manager
has been added.

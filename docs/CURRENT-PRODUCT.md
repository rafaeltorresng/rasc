# Current Rasc product

This describes the current source. The latest published build and its installation requirements are listed in the [repository README](../README.md); source changes after that release are not yet shipped.

Rasc is **a scratchpad for unfinished thoughts**: the place before the note.
The core flow is Invoke → Capture → optional Refine → Keep → return to work.
The project is open source under MIT. GitHub is source/transparency;
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

## First run

First run teaches the loop in the real panel: shortcut, capture, optional Refine, Esc.
The Ready screen lists Keep, Search thoughts, Home, Command Palette and Settings with
one-line descriptions and live shortcuts, and states that Refine is optional. After at
least three notes and a second Home visit, Home shows a one-time, dismissible Search tip.
Established installs are migrated as onboarding-complete and never see a forced tour.

## Refine

Foundation Models operates on-device on macOS 26+ when Apple Intelligence and its
model are available. The application itself supports macOS 14+. Capture, Keep and
retrieval do not depend on Refine availability.

Each request is isolated. A suggestion remains pending, with three comparison views:
Suggested (the proposed text), Changes (a word-level strike/underline diff) and
Original. Left and Right arrows cycle them; Return accepts, Esc uses the original.
Selection previews show the whole note with only the selected passage replaced.
Use original/Esc leaves the original intact. Accept suggestion persists
only after revision/snapshot validation and supports Undo.

Neutral confirmations can disappear; errors and instructions remain until dismissed
or the user changes the thought. Save failures take precedence over onboarding hints.

## Retrieval and keyboard behavior

Home separates Kept and temporal groups. Initially it shows the newest 12 Kept,
with explicit Show all/Show fewer access to every remaining Kept. The default view
is the compact list: kept marker (kept rows only), single-line title, optional
single-line excerpt, right-aligned timestamp. A toggle in the header switches to a
card view that shows a multi-line excerpt of each note; ordering, search, selection
and keyboard navigation are identical in both views, and the choice is remembered.

Arrows move within the visible order in both views — by row in the list, by cell in
the card view; there is no horizontal wrap. Search-field caret editing stays
distinct from list navigation; Down or Return transfers focus to results.

Both retrieval surfaces use local FTS, not AI. Snippets prefer context around an
actual query term. Quick Search shows up to 12 results with a truncation hint;
Home Search shows up to 500 with a hint to narrow the query. The visible action is
Search thoughts (`⌘P`); legacy “find” remains a palette search alias.

## Presentation

The interface uses Graphite Paper: warm paper and neutral graphite surfaces, neutral selection and focus, and copper reserved for Keep and Kept. Settings → Theme Style adds curated presets (Graphite Paper default, Slate, Porcelain) without changing the default or copper's role; reset restores System + Graphite Paper. The brand symbol remains separate from the writing surface. The Thinking Orb has been removed from the interface. See the [design system](DESIGN-SYSTEM.md) and [brand](BRAND.md).

## Validation boundaries

Automated domain tests cannot validate VoiceOver, Full Keyboard Access, active-window
focus or Spaces. Native window suites and the [manual checklist](NATIVE-UI-VALIDATION.md)
remain required. UI render captures, if used, are layout evidence only.

No notes, clipboard contents or credentials belong in diagnostics. No backend,
cloud fallback, telemetry, account, sync, folders, tags, assistant or project manager
has been added.

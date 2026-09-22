# M16 — Product behavior specification (as shipped)

## Keep semantics

- **Field:** `kept_at: Date?` on `notes`
- **`kept_at == nil`:** unfinished thought
- **`kept_at != nil`:** kept / settled thought
- Keep never mutates `content`
- Unkeep clears `kept_at` only

## Active scratch session

### Keep (unfinished → kept)

1. `prepareForThoughtCompletionAction()` — await acceptance, cancel Refine, flush autosave
2. `repository.keep(id:)`
3. Clear active session (`noteID`, text, UserDefaults active note)
4. Transient **Kept** feedback
5. Panel hides after ~450ms
6. Next `restore()` with cleared active state → fresh scratch

### Unkeep (kept → unfinished)

- Available when viewing a kept note (scratchpad, palette, menu)
- Clears `kept_at`; content unchanged

### Discard

- Soft-delete active note via existing repository semantics
- Clear active session
- Does not affect other notes

### Copy / Share

- Plain text via `NoteHandoff`
- No repository mutation

## UI surfaces

| Surface | Behavior |
|---|---|
| Scratchpad bottom-trailing | Keep (unfinished + content) or Unkeep (kept) |
| Command palette | Context-aware completion commands |
| App menu Note | Keep, Unkeep, Copy, Share, Discard |
| Home | Kept section (≤12), temporal sections for unfinished |
| Search | Kept label on rows; all non-deleted notes indexed |

## Refine concurrency

- `canPerformThoughtCompletion` requires `surface ∈ {editor, message}` and no acceptance task
- Keep/Copy/Share/Discard blocked during refining, preview, or acceptance
- `prepareForThoughtCompletionAction` cancels in-flight Refine before lifecycle mutation

## Keyboard shortcuts

| Action | Shortcut |
|---|---|
| Keep | `⇧⌘K` |
| Command palette | `⌘K` |
| Find | `⌘P` |
| Refine | `⌘J` |

No new conflicts with `⌘J`, `⌘P`, or `⌘K`.

## Microcopy

Keep, Kept, Unkeep, Copy Note, Share…, Discard Note — no archive/knowledge vocabulary.

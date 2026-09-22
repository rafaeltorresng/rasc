# Thought completion (M16)

**Version:** 0.1.0-beta.3 (build 4)  
**Status:** Shipped in development line only. Frozen beta.2 artifact unchanged.

M16 closes the product loop:

```text
Capture → Refine (optional) → Keep / Hand off / Discard
```

The goal is **completion**, not organization.

---

## Lifecycle semantics

| State | Persistence | Meaning |
|---|---|---|
| **Unfinished** | `kept_at IS NULL` | Provisional scratch thought |
| **Kept** | `kept_at IS NOT NULL` | Intentionally settled thought |

- `Keep` sets `kept_at` to the current timestamp.
- `Unkeep` clears `kept_at`.
- Neither action changes note text.
- Editing a kept note does **not** auto-unkeep.

Existing notes migrate as **unfinished** (`kept_at = NULL`).

---

## Keep behavior

When the active unfinished note is kept:

1. Pending autosave is flushed.
2. In-flight Refine is cancelled safely.
3. `kept_at` is persisted.
4. A brief **Kept** confirmation appears.
5. The scratch session ends (active note cleared).
6. The scratchpad hides.
7. The next normal global-shortcut invocation starts a **fresh unfinished note**.

Reopening a kept note from Home or Search shows its content normally and does **not** redirect to a blank scratch.

---

## Handoff

Handoff moves content out of Rasc without changing note state.

| Action | Mechanism | State change |
|---|---|---|
| **Copy Note** | `NSPasteboard` plain text | None |
| **Share…** | `NSSharingServicePicker` plain text | None |

Handoff does not implicitly Keep or Discard.

---

## Discard

**Discard Note** exposes existing soft-delete semantics as an intentional product action.

- Flushes/cancels pending work safely.
- Soft-deletes only the active note.
- Clears the scratch session afterward.
- No Trash UI or retention settings.

---

## Surfaces

### Scratchpad

- Subtle **Keep** affordance when the note is unfinished and has content (`⇧⌘K`).
- **Unkeep** when viewing a kept note.
- No completion modal or wizard.

### Command palette (`⌘K`)

Context-aware commands:

| Note state | Commands |
|---|---|
| Unfinished (with content) | Keep, Copy Note, Share…, Discard Note, … |
| Kept | Unkeep, Copy Note, Share…, Discard Note, … |
| Empty unfinished | New Scratch, Find, Home, Refine, Settings only |

### Home

- Compact **Kept** section (recent kept notes, max 12).
- Existing temporal sections for unfinished notes.
- Restrained **Kept** badge on cards.

### Search (`⌘P`)

- Searches all non-deleted notes (kept and unfinished).
- Kept notes show a quiet **Kept** label.
- FTS ranking unchanged.

---

## Refine interaction

Completion does not change Refine behavior.

- Keep/Copy/Share/Discard are unavailable while Refine is generating or accepting.
- Completion actions flush accepted text first.
- Stale Refine protections remain intact.

---

## Explicit non-goals

M16 does **not** add:

- folders, tags, pinning, favorites, archive
- workflow boards, expiration, cloud state
- Trash browser, connector marketplace
- automatic unkeep on edit

Rasc remains a scratchpad, not a repository.

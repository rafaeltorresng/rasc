# M16 — Migration report

## Schema change

**Migration ID:** `v5_m16_notes_kept_at`

```sql
ALTER TABLE notes ADD COLUMN kept_at DATETIME;
```

- Nullable timestamp; no default inference
- Existing rows migrate as **unfinished** (`kept_at = NULL`)
- FTS (`notes_fts`) synchronizes automatically — kept notes remain searchable
- Soft-delete (`deleted_at`) unchanged
- Refinement revisions table unchanged

## Verification

| Scenario | Result |
|---|---|
| Fresh database | Column present; new notes `kept_at = NULL` |
| beta.2-era DB (through v4) | Migrates cleanly; content preserved |
| Keep / unkeep round-trip | `kept_at` set/cleared; content unchanged |
| FTS after keep | Kept note findable via search |
| Legacy note after migration | `isKept == false` |

Automated: `NoteRepositoryTests.migratesM3ADatabaseToKeptAtWithoutLosingNotes`, `keepAndUnkeepPersistKeptAtWithoutChangingContent`.

## Version bump

Development line only:

- **Marketing:** 0.1.0-beta.3
- **Build:** 4

Frozen artifact `Rasc-0.1.0-beta.2.dmg` and M14 acceptance records **not modified**.

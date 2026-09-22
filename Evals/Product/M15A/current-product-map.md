# M15A — Current product map

**Release:** 0.1.0-beta.2 (build 3)  
**Method:** Repository + shipped UI audit (not milestone assumptions)

---

## Product loop (what users actually experience)

```text
invoke (⌥\ or menu)
    → capture (type immediately)
    → edit (plain text, autosave ~200ms)
    → persist (SQLite local, active note tracked)
    → refine? (⌘J → preview → accept/cancel/undo)
    → hide (Esc — focus returns)
    → retrieve (⌘P in scratchpad, or Home)
    → revisit (open note, continue editing)
    → continue later (resume last note on next invoke)
```

There is **no distinct “done with this thought” step** beyond hiding the panel or leaving text in history.

---

## Surfaces

| Surface | Entry | Purpose |
|---|---|---|
| **Scratchpad** | Global shortcut (default `⌥\`), menu | Primary capture + edit + Refine |
| **Refine preview** | `⌘J` | Temporary preview state inside scratchpad |
| **Search overlay** | `⌘P` | Quick find inside scratchpad panel |
| **Command palette** | `⌘K` | Discover commands (5 fixed items) |
| **Home** | Menu, scratchpad house icon, palette | Browse/search notes in normal window |
| **Settings** | `⌘,`, menu, palette | Shortcut, launch at login, Refine language |
| **Onboarding** | First run | Shortcut setup, capture practice, optional Refine |
| **Menu bar** | Status item | Home, new, search, settings, feedback, quit |

No Dock icon. App stays resident after last window closes.

---

## Scratchpad

**Can do**
- Toggle show/hide via global shortcut
- Write plain text with immediate focus
- Autosave continuously; flush on hide/note switch/quit
- New scratch (`⌘N`)
- Resume last active note (or most recent on first launch)
- Open Home from editor chrome
- Hide with `Esc` (returns focus to previous app)
- Empty content → note removed from database

**Behavior**
- Single floating panel, one visible scratchpad at a time
- Resizable; frame persisted
- Above fullscreen apps (validated in M13)
- Does not auto-dismiss on click-outside

**Cannot do**
- Multiple simultaneous scratchpads
- Rich text / rendered markdown
- Pin as separate concept
- Keep / mark as preserved
- Export to other apps
- Explicit delete (except by clearing all text)

---

## Refine

**Can do**
- `⌘J` on whole note or selected text (macOS 15+ selection)
- Loading state with Shaping Orb + “refining…”
- Preview with Esc (cancel) / Enter (accept)
- Undo after accept (`⌘Z`)
- noChange when text already useful
- Refine Language: match note or fixed locale (Settings)

**Cannot do**
- Prompt, mode, or tone picker
- Cloud or alternate models
- Auto-refine or proactive suggestions
- Global style preference (M12C-002 rejected)
- Retry as first-class UI (no `⌘R` in palette)

When Foundation Models unavailable: capture/search/Home still work; Refine shows safe unavailable state.

---

## Notes & persistence

**Model:** `Note` — id, content, created/updated timestamps, soft `deleted_at`

**Not in schema:** `is_kept`, title column, tags, folders

**Title display:** Derived from first meaningful line (`displayTitle`)

**Lifecycle today**
- Create on first non-empty save
- Update on edit
- Soft-delete when content cleared to empty
- All non-deleted notes appear in search/Home equally

---

## Search & Home

**Scratchpad search (`⌘P`)**
- Overlay inside panel
- Recent notes when query empty
- FTS-backed search when typing
- Arrow keys + Enter; Esc back to editor

**Home**
- Normal resizable window (~1000×680)
- Groups: Today / Yesterday / Earlier
- Inline search (live filter)
- Open note → scratchpad (panel hides first)
- New Scratch from Home

**Not present:** semantic search, folders, favorites, kept filter, inbox states

---

## Settings

| Control | Present |
|---|---|
| Global shortcut recorder | ✅ |
| Launch at Login | ✅ |
| Refine availability status | ✅ |
| Refine Language | ✅ |
| Privacy copy (local storage) | ✅ |
| Send Feedback (mailto, no note content) | ✅ |
| Appearance picker | ❌ (follows system) |
| Menu bar visibility toggle | ❌ |
| AI model picker | ❌ (correct) |

---

## Menu bar

- Open Home
- New Scratch (`⌘N`)
- History / Search (`⌘P`)
- Settings (`⌘,`)
- Send Feedback…
- Quit (`⌘Q`)

---

## Launch & restart

- Optional launch at login (`SMAppService`)
- Notes persist in `~/Library/Application Support/Rasc/`
- Active note ID in UserDefaults
- Window frames persisted (scratchpad + Home)
- Onboarding skipped for returning users with existing data
- Quit flushes saves or blocks with alert on failure

---

## Shortcuts reference

| Shortcut | Action |
|---|---|
| `⌥\` (default) | Toggle scratchpad |
| `⌘N` | New scratch |
| `⌘P` | Find note |
| `⌘K` | Command palette |
| `⌘J` | Refine |
| `⌘,` | Settings |
| `Esc` | Cancel overlay / preview / hide scratchpad |
| `Enter` | Accept Refine preview / open search result |

---

## Out of scope (confirmed absent)

Accounts, sync, iCloud, cloud AI, chat, agents, folders, tags, templates, collaboration, task management, Sparkle updates, licensing/paywall, telemetry SDK, export/routing, Keep command, explicit delete UI.

---

## Engineering capabilities users never see

Refine eval harness, prompt versioning, refinement revisions table, reliability tests, RC packaging scripts — these support trust but are not product features.

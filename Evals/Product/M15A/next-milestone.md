# M15A — Next milestone proposal

**Decision:** B — one product capability still missing  
**Milestone:** **M16 — Thought completion (Keep + handoff)**

---

## Why this milestone

Rasc’s constitution has three verbs. Two are shipped and hardened. **Keep** is not optional rhetoric — it defines what happens when a provisional thought stops being unfinished.

Without completion:
- History is a flat archive, not a **temporary-first** system
- Shaping stops at *settled*, never *clear*
- Competitive story vs Antinote (handoff) and Quick Note (good enough capture) weakens

M16 closes the loop **without** becoming a notes app.

---

## Three serious candidates (summary)

| # | Milestone | User problem | Why now | Risk |
|---|---|---|---|---|
| **1** | **M16 Keep + handoff** | Thoughts never “finish”; history clutter | Completes product constitution | Scope creep into sync/export hub |
| 2 | M15 Trusted private beta | Need real habit signal | RC ready | Validates scratchpad, not Keep thesis |
| 3 | M17 Commercial shell | Can’t sell what isn’t packaged | After product complete | Polishes incomplete lifecycle story |

**Chosen:** #1 only as next **product** milestone.

---

# M16 — Thought completion (Keep + handoff)

## Name

**M16 — Thought completion (Keep + handoff)**

Alternate label: *Finish the thought*

---

## Product hypothesis

If users can **mark a shaped thought as kept** and **hand it off** to their permanent system in one or two actions, Rasc completes the temporary-thought job: capture and refine in Rasc; **keep only what matters** elsewhere or in a clearly marked local state — without folders, sync, or accounts.

---

## User flow

### Keep (local semantics)

```text
User shapes note in scratchpad (optional Refine)
    → ⌘⇧K or palette “Keep”
    → subtle “kept” state (Home/search indicator)
    → note stays in history with kept meaning
    → Esc back to work
```

Keep means: **this is no longer disposable buffer — don’t lose it.** Not a folder. Not sync.

### Handoff (exit to permanent home)

```text
User finishes shaping
    → “Send to…” or Copy for [Notes / Bear / Obsidian / clipboard]
    → content lands in chosen destination
    → optional: mark kept or offer discard in Rasc
    → Esc back to work
```

Handoff implements *where matters live* without Rasc becoming that place.

### Discard (companion, minimal)

```text
⌘⌫ or palette Delete
    → soft delete with brief Undo
    → removes from history
```

Explicit discard complements Keep; not the centerpiece.

---

## Scope

**In scope**
- `is_kept` (or equivalent) in persistence + migration
- Keep toggle command + keyboard shortcut
- Kept indicator in Home and search results
- Handoff: **clipboard-first**, plus **1–2 native share targets** (e.g. Apple Notes, plain copy) — minimal, macOS-native
- Explicit delete with undo toast (uses existing soft-delete)
- Palette entries: Keep, Delete (Copy optional if trivial)
- Evals: no change to Refine engine
- Acceptance tests for lifecycle, not AI

**Out of scope (non-goals)**
- Folders, tags, collections, favorites
- Cloud sync, accounts, iCloud
- Full export suite / routing marketplace (Einfall-style)
- Auto-expire old scratches
- Refine changes (prompt, modes, preferences)
- Semantic search, pinned smart lists
- iPhone / web
- Billing, Sparkle, public launch
- Telemetry beyond existing mailto feedback

---

## Interaction model

- **One verb for preservation:** Keep — not stars, tags, or projects
- **One verb for exit:** Hand off / Send — not a connector platform
- **Keyboard-first:** Keep and Delete discoverable via palette + shortcuts
- **No modal dialogs** for folder/title/tag
- **Esc still safe:** hide never destroys; delete is explicit

---

## Relationship to Shaping

| Shaping stage | M16 role |
|---|---|
| raw | (unchanged) capture |
| uncertain | (unchanged) messy text OK |
| shaping | (unchanged) Refine |
| settled | (unchanged) accept preview |
| **clear** | **Keep or handoff — thought leaves provisional state** |

Shaping Orb may appear briefly on keep/handoff success (settle/dissolve) — optional polish, not required for M16 acceptance.

---

## Acceptance criteria

1. User can mark/unmark a note as **kept** without dialogs; state persists across restart
2. Kept notes show **distinct but quiet** indicator in Home and search
3. User can **hand off** note content to at least clipboard + one external destination without leaving keyboard flow for long
4. User can **explicitly delete** a non-empty note with undo
5. Keep/handoff/delete **do not** invoke Refine or send content to cloud through Rasc servers
6. Core capture → Refine → hide loop unchanged; M13/M14 invariants preserved
7. No new organization surfaces (folders, tags, sidebar sections beyond kept indicator)

---

## Technical areas likely affected

| Area | Change |
|---|---|
| `Note` / schema migration | Add `is_kept` boolean |
| `NoteRepository` | Keep toggle, filter queries optional |
| `PaletteCommand` / shortcuts | Keep, Delete |
| `ScratchpadView` / session | Keep action, delete UX |
| `HomeView` / search UI | Kept badge |
| Share/handoff | `NSPasteboard`, `NSSharingService` or app-specific hooks |
| Tests | Lifecycle persistence, keep toggle, delete undo |
| Docs | PRD alignment, release notes |

**Not affected:** RefinementEngine, RefinementPrompt, FM provider, panel behavior, onboarding core.

---

## Complexity

**Medium.** Mostly product/UI + schema migration. Handoff surface needs careful scope guard. Lower risk than new AI features; higher product impact than polish.

---

## Main risk

**Scope creep into “router platform.”** Mitigation: clipboard + one native target first; evaluate Bear/Obsidian only if trivial via share sheet; no connector marketplace.

Secondary risk: **Keep without handoff feels cosmetic.** Mitigation: ship both in one milestone so “matter” can leave Rasc.

---

## What must explicitly NOT be built in M16

- Global Refine Preference (rejected)
- Named AI modes / tone presets
- Tags, folders, smart collections
- Sync, accounts, backend
- Chat, agents, auto-refine
- Public launch infrastructure
- Semantic search
- Task/calendar extraction beyond what Refine already does in text
- Reopening M12 Refine reliability work except regressions

---

## After M16 (recommended sequence)

1. **M15 — Trusted private beta distribution** (commercial ops, not product)
2. **M17 — Commercial readiness** (site, demo, pricing, signed updates)
3. Revisit open questions (auto-expire, always-new vs resume) **only with usage evidence**

Do not start M15 as substitute for M16 unless product constitution is formally narrowed to two verbs.

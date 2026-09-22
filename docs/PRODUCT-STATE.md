# Rasc product state

**As of:** 2026-09-22  
**Release:** 0.1.0-beta.3 (build 4) — M16 thought completion  
**Audit:** M15A (product), M16 (lifecycle)

This document reconciles product specification with what is actually shipped today.

---

## Executive summary

Rasc is a **maintainer-accepted private beta** that delivers the full **capture → edit → persist → refine → keep/handoff** loop on macOS. Engineering reliability (M13), Refine reliability (M12B), and thought completion (M16) are complete for the private-beta product arc.

The three-verb constitution (*Capture without thinking. Refine without prompting. Keep only what matters.*) is **implemented**. Keep marks intentional completion; Copy/Share provide handoff without organization tax; Discard is an explicit product action.

**Decision (M16):** **A — thought completion complete.**  
**Next milestone:** **M15 — Trusted private beta distribution** (signing, notarization, retained upgrade artifacts).

---

## Source-of-truth hierarchy

| Source | Role | Trust level |
|---|---|---|
| Shipped app (`Rasc/`) | What users can do | **Highest** |
| `AGENTS.md` | Engineering invariants | High |
| `docs/Product.md` | Product thesis & anti-features | High (intent) |
| `docs/PRD.md` | V1 behavior contract | High (some items deferred) |
| `docs/UX-Spec.md` | Interaction detail | Medium (superseded in places) |
| `docs/HOME-SPEC.MD` | Home surface | High for Home |
| `docs/DESIGN-SYSTEM.md` | Shaping visual language | Medium (partially implemented) |
| `docs/ARCHITECTURE.MD` | Engineering plan | Medium (includes unshipped items) |
| Milestone evals (`Evals/`) | Evidence | High for completed milestones |

When docs disagree with code, **code wins** for current-state claims; **Product.md / PRD** win for intended direction.

---

## Doc ↔ implementation mismatches

| Topic | Spec says | Shipped today |
|---|---|---|
| **Keep** | Third product verb; `⌘⇧K`; kept lifecycle | **Implemented** — `kept_at`, scratchpad affordance, palette, menu |
| **Delete** | Explicit command (`⌘⌫`), palette entry, undo toast | **Partial.** Discard Note in palette/menu; soft-delete; no dedicated undo toast |
| **Copy / export** | Palette Copy; handoff to permanent apps | **Implemented** — Copy Note + Share… via `NoteHandoff` |
| **History-only UX** | Product.md emphasizes search overlay, no homepage | **Home window added** (per `HOME-SPEC.MD`) — intentional expansion |
| **Command palette** | Keep, Copy, Delete, context-aware list | **Context-aware** — completion commands when note has content |
| **Pin** | Optional pin vs keep distinction | **Not exposed.** Panel is always floating while open |
| **Global shortcut default** | Docs vary (`⌥Space`, `⌥\`) | **`⌥\`** (migrated from `⌥Space`) |
| **Sparkle / auto-update** | Architecture target | **Not shipped** |
| **Global Refine preference** | Was experiment M12C-002 | **Rejected and removed.** Refine Language (M12C-001) remains |
| **Shaping Orb** | Brand motion during transformation | **Partial.** Orb during Refine loading; onboarding uses static logo |
| **Telemetry** | Minimal event list in PRD | **Not implemented** (mailto feedback only) |
| **Markdown rendering** | Minimal support possible | **Plain text editor**; markdown preserved as text |
| **Appearance settings** | System/Light/Dark in UX spec | **Not in Settings** (follows system via SwiftUI) |

Remaining gaps are polish or distribution — not core lifecycle blockers.

---

## What is complete

### Capture
- Menu-bar agent (`LSUIElement`, no Dock icon)
- Global shortcut toggle (configurable)
- Floating scratchpad (`NSPanel`, fullscreen/Spaces hardened)
- Immediate editor focus, autosave, Esc to hide
- New note (`⌘N`), resume last active note
- Onboarding (shortcut, capture practice, optional Refine hint, launch at login)

### Refine
- Whole-note and selection Refine (`⌘J`)
- Preview / accept / cancel / undo
- Conservative noChange behavior (M12B complete)
- Refine Language preference (M12C-001)
- On-device Foundation Models only; graceful unavailability
- Shaping Orb during refinement

### Thought completion (M16)
- Keep / Unkeep (`⇧⌘K`, scratchpad affordance, palette, menu)
- Copy Note + Share… handoff
- Discard Note (soft-delete)
- Home **Kept** browse section + search label
- `notes.kept_at` migration with reversible unkeep

### Retrieve
- In-scratchpad search (`⌘P`)
- Home window (browse by lifecycle, search, open note)
- Lexical FTS search
- Command palette (`⌘K`)

### Trust
- Local-first SQLite/GRDB
- Maintainer acceptance (M14)
- App reliability audit (M13A)
- No silent cloud transmission

---

## Shaping promise status

Design-system arc: **raw → uncertain → shaping → settled → clear**

| Stage | Status |
|---|---|
| Raw | ✅ Instant capture |
| Uncertain | ✅ Messy text welcome; no upfront structure |
| Shaping | ✅ Refine + orb + preview |
| Settled | ✅ Accept / cancel / undo |
| Clear | ✅ Keep + handoff; kept notes labeled in Home/Search |

---

## Readiness layers

| Layer | Status |
|---|---|
| **Technically complete** | Yes — private beta RC + M16 |
| **Product-worthy** | Yes — core lifecycle complete |
| **Commercially ready** | No — trusted distribution, signing, updates, pricing |

Developer ID / notarization are **distribution** requirements, not product features.

---

## Anti-features (still in force)

Do not add without overwhelming evidence: folders, tags, sync, accounts, chat/agents, prompt libraries, named AI modes, collaboration, task manager, semantic search, telemetry-heavy analytics.

---

## Next milestones (ordered)

1. **M15 — Trusted private beta distribution** — signing, notarization, Sparkle prep, retained upgrade artifacts  
2. **M17 — Commercial readiness** — site, pricing, public launch shell

---

## References

- `Evals/Product/M15A/product-audit.md`
- `Evals/Product/M16/report.md`
- `Evals/AppReliability/M14/acceptance-report.md`
- `docs/THOUGHT-COMPLETION.md`
- `docs/releases/0.1.0-beta.2.md`

# M15A — Product & sellability audit

**Date:** 2026-09-22  
**Subject:** Rasc 0.1.0-beta.2 (build 3), MAINTAINER ACCEPTED  
**Scope:** Analysis only — no code, no distribution

---

## 1. Original product promise

**Thesis:** A premium native macOS scratchpad for unfinished thoughts.

**Operational promise:** *Capture without thinking. Refine without prompting. Keep only what matters.*

**Shaping arc (design system):** raw thought → uncertain form → shaping → settled clarity

**Competitive bet:** Not “AI in a note,” but **AI as judgment** — one Refine action instead of tool menus or prompts.

---

## 2. Promise delivery assessment

### Genuinely delivered

| Promise element | Evidence |
|---|---|
| Instant capture | Global shortcut, focus-ready editor, Esc hide, M14 PASS |
| Zero-prompt Refine | Single `⌘J`; M12B reliability; preview/accept/cancel |
| Local/private | SQLite, on-device FM, no note content in feedback |
| Native macOS utility | NSPanel, Spaces/fullscreen, menu bar agent, keyboard-first |
| Reversible AI | Preview required; undo; noChange; revision storage |
| Retrieval without org tax | FTS search, Home browse, no folders/tags |
| Conservative Refine | Eval-gated; language preference without style modes |

### Conceptual only

| Element | Status |
|---|---|
| **Keep only what matters** | In branding and PRD; **not in app** |
| **Temporary vs permanent lifecycle** | Described in Product.md; **all notes equal** |
| **Shaping as product identity** | Orb + motion during Refine; **not a user-facing narrative** |
| **Discard vs close** | Close saves to history; **no explicit discard semantics** |
| **Handoff to permanent tools** | Antinote lesson cited; **not built** |

### Missing for coherent loop

The loop **capture → shape → finish** lacks **finish**. Users can hide and return, but Rasc never helps answer: *Is this thought done? Should it leave the scratchpad world?*

---

## 3. Is “scratchpad + ⌘J” enough?

**For a technical beta:** Yes — maintainer accepted, differentiated engineering.

**For the stated product thesis:** **Not quite.** Writing Tools already cover “rewrite this text” in situ. Rasc’s extra value must come from the **whole temporary-thought workflow**:

1. Faster capture than opening Notes — **delivered**
2. Judgment without tool choice — **delivered**
3. **Letting go of the provisional** or **promoting what matters** — **not delivered**

Without (3), habit formation may still occur for capture, but **differentiation erodes** to hotkey UX + Refine quality — a narrower moat against Apple and Raycast.

More AI features would **not** fix this; it would worsen menu creep (M12C-002 lesson).

---

## 4. Sellability audit

### Immediacy of value
**High** for capture. Refine value requires Apple Intelligence. Onboarding teaches shortcut + optional Refine in minutes.

### Frequency of useful interaction
**Potentially high** for target persona (keyboard-heavy Mac workers). Session duration should stay short; product supports that.

### Friction
**Low** in core loop. Gatekeeper friction is distribution, not product. Resume-last-note can surprise users expecting always-new scratch (open PRD question) — minor.

### Uniqueness of workflow
**Medium.** Refine interaction is distinctive; capture/search overlap with Raycast, Quick Note, Antinote.

### Native macOS advantage
**High** when panel behavior works (validated M13). Menu-bar agent model fits thesis.

### Zero-prompt behavior
**High** for Refine invocation. **Low** for lifecycle completion (no guidance at end of thought).

### Local/private positioning
**High** and credible.

### Clarity of Shaping concept
**Low externally.** “Unfinished thoughts” tagline works; Shaping arc is mostly internal design language.

### vs generic notes + AI assistant
Rasc wins on **speed + no prompt + no app switch** when Refine helps. Loses on **long-term home, sync, organization, handoff**.

### Reason to return
Search, Home, resume-last-note support return. **No completion ritual** weakens “I’m done with that thought” closure.

---

## 5. Readiness classification

| Layer | Verdict | Rationale |
|---|---|---|
| **Technically complete** | ✅ | M13 + M14; frozen RC |
| **Product-worthy** | ⚠️ Mostly | Core loop strong; third verb missing |
| **Commercially ready** | ❌ | Identity, pricing, trusted distribution, signed updates |

---

## 6. Strongest differentiation today

**Refine as single judgment action** — explicit, reversible, on-device, eval-hardened — inside a **floating capture utility** that disappears with Esc.

Combined with **no organization tax**, this is the defensible wedge — **if** users feel the full temporary-thought lifecycle, not just one-shot rewrite.

---

## 7. Biggest product weakness

**No thought-completion moment.** Everything saved looks the same in history. The product asks users to capture and shape provisional thoughts but never helps them **finish** — keep, hand off, or intentionally discard.

---

## 8. Sellable in principle?

**Yes, with caveats.** A paying user on Apple Intelligence hardware could justify **$15–20 one-time** for capture + Refine **if** they understand the workflow and Refine earns trust quickly.

**Weaker sell** without completion/handoff: easier to compare to free Quick Note + Writing Tools and dismiss as incremental.

Commercial packaging (demo, site, word-of-mouth video from Product.md §44) matters as much as another Refine tweak.

---

## 9. Next-milestone candidates (max 3)

### Candidate 1 — M16: Thought completion (Keep + handoff) ⭐ recommended

See `next-milestone.md`.

### Candidate 2 — M15: Trusted private beta distribution

Hand frozen RC to small cohort; mailto feedback; observe habit/Refine acceptance **without** blocking on external feedback for this audit.

**Why not first:** Distribution validates demand but does not close the lifecycle gap; risks learning “nice scratchpad” without testing Keep thesis.

### Candidate 3 — M17: Product presentation & commercial shell

Landing, 10-second demo, pricing experiment, signed builds + Sparkle.

**Why not first:** High leverage for sellability; does not fix incomplete product constitution.

---

## 10. Feature-creep failures (do not pursue)

These failed the “core promise incomplete without it?” test:

- Tags, folders, sync, accounts
- Chat / agents / connectors
- Named tone modes / global Refine prefs (rejected)
- Semantic search / second brain
- Auto-refine suggestions
- Task manager / calendar integration
- iPhone app / browser extension

---

## 11. Final decision

**B — ONE PRODUCT CAPABILITY IS STILL MISSING**

Exactly one capability: **thought completion via Keep + handoff** — marking what matters and sending shaped text to where it belongs, without turning Rasc into a permanent notes system.

---

## 12. What must NOT be built next

- M12C-002 Global Refine Preference (rejected)
- Public launch / App Store push before private beta learning
- Preemptive P2/P3 reliability fixes as a “milestone”
- Organization features (tags, folders, projects)
- Cloud sync, accounts, telemetry platforms
- Additional Refine modes or prompt surfaces
- Generic AI chat
- Feature marketplace / plugin system
- Rebuilding the frozen RC for non-P0/P1 reasons

---

## References

- `docs/Product.md` — thesis, anti-features, Keep lifecycle
- `docs/PRD.md` — V1 scope, Keep entity
- `docs/DESIGN-SYSTEM.md` — Shaping arc
- `Evals/AppReliability/M13A/issue-register.md`
- `Evals/AppReliability/M14/acceptance-report.md`
- `Evals/Refine/experiments/M12C-002-global-refine-preference/REJECTED.md`

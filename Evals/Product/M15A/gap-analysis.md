# M15A — Gap analysis

---

## A. Missing product capabilities

### A1. Thought completion — **primary gap**

**Problem:** After capture and optional Refine, every note has the same status in history. The product constitution promises *Keep only what matters*, but there is no moment where a thought becomes **finished**, **preserved intentionally**, or **handed off** to a permanent system.

**User impact:**
- History grows as an undifferentiated pile of scratches
- No semantic distinction between “buffer I’m done with” and “this should survive”
- Shaping arc stops at *settled*; never reaches *clear*
- Competes with Antinote/Einfall on capture alone; handoff is a known scratchpad expectation

**Spec basis:** Product.md §23 lifecycle, §164 three verbs; PRD §21 Keep; UX-Spec §28–29 (Keep candidate)

**Feature-creep test:** *If Keep/handoff did not exist, would the core promise feel incomplete?* **Yes** — it is one third of the branded constitution.

---

### A2. Discard as intentional action — **secondary gap**

**Problem:** Notes disappear only when content is cleared to empty. There is no explicit “remove this scratch” that preserves non-empty mistakes or abandoned drafts without editing them away.

**User impact:** Users who want to delete a partial note must manually erase text or leave clutter in history.

**Spec basis:** PRD §47 Delete; UX-Spec §53; palette included Delete

**Feature-creep test:** Helpful but **not** the primary missing capability. Subordinate to completion lifecycle.

---

### A3. Product identity / Refine comprehension — **secondary gap**

**Problem:** Refine quality is engineering-proven (M12B), but the **product story**—“judgment without prompting, unlike Writing Tools menus”—is mostly implicit. Shaping visual language exists during loading; it does not explain *why* Rasc exists post-onboarding.

**User impact:** First-time sellability depends on demo/video or trial habit; in-app differentiation from Quick Note + Writing Tools is thin.

**Feature-creep test:** Important for **commercial** conversion, weaker as **core loop** gap. Partially addressable in distribution/onboarding copy without new capabilities.

---

## B. Polish opportunities (not next product milestone)

| Item | Notes |
|---|---|
| Command palette fuzzy filter UI | Helper exists; UI missing |
| Explicit delete + undo toast | UX spec; soft-delete backend ready |
| Copy command in palette | Trivial; not lifecycle-critical alone |
| Onboarding Shaping Orb richness | ONBOARDING-SPEC > shipped |
| Appearance setting | UX spec optional |
| P2/P3 reliability edges | Known; not blockers |
| Command palette Copy/Keep entries | Blocked on A1 anyway |

---

## C. Engineering debt (not next product milestone)

| Item | Notes |
|---|---|
| Sparkle / signed updates | Planned; distribution |
| Developer ID / notarization | Distribution |
| Upgrade testing from beta.1 | Artifact retention policy now set |
| Bootstrap retry (P2-003) | Reliability polish |
| Settings presentation hack (P3-002) | Internal |

---

## D. Commercial / distribution work (not next product milestone)

| Item | Notes |
|---|---|
| Trusted private beta cohort (M15) | Recommended after product gap closed |
| Pricing / licensing | After willingness-to-pay signal |
| Marketing site / demo video | Product.md §44 — high leverage but commercial |
| Mac App Store | Post direct distribution |
| Telemetry opt-in | PRD lists events; not required for private beta |

---

## Feature-creep test summary

| Candidate | Incomplete without it? | Strengthens unique model? |
|---|---|---|
| Keep + handoff | **Yes** | **Yes** — completes temporary-first thesis |
| Folders/tags | No | **No** — becomes notes app |
| Sync/accounts | No | **No** |
| Named AI modes | No | **No** — rejected pattern |
| Semantic search | No | **No** — org tax |
| Auto-refine hints | No | **No** — adds active AI behavior |
| More Home features | No | Risk — PKM drift |
| Export-only without Keep | Partial | **Yes** — but Keep gives meaning to history |

---

## Rough edges vs gaps

**Scratchpad + ⌘J alone** is a **technically complete beta** but **not a complete expression** of the product thesis. Capture and Refine are strong; the **exit arc** (what happens when a thought is no longer unfinished) is unspecified in the shipped product.

That exit arc is what separates Rasc from:
- Quick Note + Writing Tools (system capture + menu AI)
- Raycast Notes (floating notes + ecosystem)
- Antinote (capture + export handoff)

---

## Known issues (carry-forward)

M13A P2/P3 items do not change this analysis. None alter the product-gap conclusion.

---

## Decision input

**Meaningful A remaining:** Yes — **A1 Thought completion (Keep + handoff)**

**Recommend B** over A because 0.1.0-beta.2 deliberately deferred Keep but did not revoke the three-verb constitution. Shipping commercially before closing that gap risks positioning Rasc as “another scratchpad with Refine” rather than the full *Capture / Refine / Keep* proposition.

**Recommend against C** (loop reconsideration): The loop is structurally sound. Missing piece is completion, not wrong architecture.

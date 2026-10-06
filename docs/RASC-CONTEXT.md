# Rasc — Product & Engineering Context

> Historical specification/milestone reference. For current behavior, launch direction and superseded decisions, start with [CURRENT-PRODUCT](CURRENT-PRODUCT.md) and the [documentation index](README.md).


**Snapshot:** 22 Sep 2026  
**Purpose:** canonical context document for product, design, engineering, reliability, release, and commercial work on Rasc.  
**Status:** the core macOS product is functionally complete for the current 0.1 line; the next major phase is commercial positioning, landing page, distribution, and launch readiness.

---

## 1. Executive summary

Rasc is a **premium native macOS scratchpad for unfinished thoughts**. It is designed for the moment when a thought is useful enough to capture but not important enough to justify opening a full notes system, organizing it, naming it, or prompting an AI assistant.

The core interaction is intentionally small:

> **Invoke → Capture → Refine → Keep → get out of the way**

A global shortcut opens a compact floating scratchpad over whatever the user is doing. The user writes freely, without structure. If the thought needs shaping, `⌘J` invokes an on-device Refine action powered by Apple Foundation Models. Refine is deliberately conservative: it can improve wording and structure, but should prefer `noChange` rather than inventing meaning, changing language without authorization, mutating protected literals, or leaking context. When the thought is settled, **Keep** ends the scratch session while preserving the note; the next normal invocation starts fresh.

Rasc is local-first, account-free, menu-bar-first, keyboard-first, reversible, and intentionally not a knowledge-management system. There are no folders, tags, cloud sync, accounts, chat UI, prompt library, agents, or generic AI modes.

The product now has a coherent end-to-end lifecycle:

> **raw thought → uncertain form → shaping → settled clarity → kept / handed off / discarded**

The accepted product differentiator is not “AI notes.” It is a **zero-prompt, single-action shaping workflow inside a native floating scratchpad**, with a conservative reliability layer and an explicit completion moment.

---

## 2. Product thesis

### 2.1 Problem

Most thoughts that appear during work are too small, incomplete, messy, or temporary for a conventional notes app:

- a rough sentence;
- a message to send later;
- a small task;
- an idea fragment;
- a technical note;
- a reminder to investigate something;
- an unfinished thought that may or may not become important.

Traditional notes products introduce unnecessary ceremony: open a large app, decide where the note belongs, create or select a document, organize it, and often leave behind a growing pile of undifferentiated notes.

Generic AI assistants create a different kind of friction: choose a tool, explain the task, provide the text, prompt for the desired transformation, inspect the answer, and move it back into the original workflow.

Rasc is built around the opposite idea: **capture first; decide later**.

### 2.2 Core proposition

> **A scratchpad for unfinished thoughts.**

Supporting product language that has emerged during design:

> **Capture without thinking. Refine without prompting. Keep what matters.**

The product should feel like a temporary thinking surface, not a repository the user has to manage.

### 2.3 Shaping

The core brand/product metaphor is **Shaping**:

> raw thought → uncertain form → shaping → settled clarity

This shows up in:

- the Thinking Orb visual language;
- Refine as a single action rather than a menu of AI tools;
- preview / accept / cancel / undo;
- conservative `noChange` behavior;
- Keep as the completion moment.

### 2.4 Product verbs

The product is now best understood through three primary verbs:

1. **Capture** — get the thought down immediately.
2. **Refine** — shape it without writing a prompt.
3. **Keep** — intentionally settle the thought and move on.

Supporting actions:

- **Copy Note** — hand off as plain text.
- **Share…** — use native macOS sharing.
- **Discard Note** — intentionally soft-delete the thought.
- **Unkeep** — reopen a settled thought as unfinished.

---

## 3. Product principles

Rasc development has converged on the following principles.

### 3.1 Scratchpad first, AI second

The app should still feel useful and understandable as a scratchpad. AI is part of the flow, not the chrome.

This is why there is no persistent large **Refine** button in the idle editor. Refine lives in the interaction model (`⌘J` / command palette / contextual affordance), not as a permanent AI toolbar.

### 3.2 Zero-prompt interaction

The user should not have to explain what Refine should do every time. The default behavior is judgment-based and conservative.

A free-text global Refine preference was implemented and evaluated in M12C-002, but **rejected and removed** because it reopened wrong-language and protected-content failures and increased stochasticity. Named tone modes and per-invocation prompt workflows are intentionally not part of the current product.

### 3.3 Conservative transformation

Refine's central contract is:

> Missing an improvement is acceptable. A harmful edit is not.

Safety and meaning preservation outrank “doing something because the user pressed Refine.”

### 3.4 Local and private by default

- Notes are stored locally.
- Refine uses Apple Foundation Models on-device.
- No automatic telemetry is part of the current product.
- No account is required.
- No cloud AI backend exists.

### 3.5 Reversible actions

- Refine uses preview before mutation.
- Accepted Refine is undoable.
- Keep does not alter text.
- Unkeep reverses Keep.
- Copy/Share do not mutate lifecycle state.
- Discard uses soft-delete semantics.

### 3.6 Native macOS behavior

Rasc is intentionally not a web app wrapped in a desktop shell. It uses native window behavior, menu bar integration, keyboard shortcuts, local persistence, native sharing, launch-at-login integration, and Apple Foundation Models.

### 3.7 No knowledge-management creep

Rasc is intentionally **not** becoming Notion, Obsidian, Apple Notes, or a second-brain system.

Current non-goals include:

- tags;
- folders;
- collections;
- kanban/workflow states;
- cloud sync;
- accounts;
- collaboration;
- semantic-search platform;
- task/calendar system;
- chatbot;
- agent platform;
- prompt marketplace;
- feature marketplace.

---

## 4. Current core user journey

### 4.1 First run

The first-run onboarding introduces the product through a short, interactive flow rather than a feature tour.

The onboarding architecture reuses the real production scratchpad and Refine path rather than simulating them.

The flow conceptually covers:

1. Welcome / product promise.
2. Global shortcut discovery/configuration.
3. Real shortcut handoff into the production scratchpad.
4. Capture practice.
5. Refine practice when Foundation Models are available.
6. Completion.
7. Optional Launch at Login.

The welcome screen currently communicates:

> **A scratchpad for unfinished thoughts.**

and the full product loop:

> **Capture without thinking. Refine without prompting. Keep what matters.**

The onboarding uses the official **ThinkingOrbsKit** implementation from Libraries.dev, vendored into the repository under MIT license.

### 4.2 Daily capture

The default global shortcut is **`⌥\`**. This was chosen deliberately because `⌥ Space` is already commonly occupied and is personally used elsewhere.

Normal flow:

1. User presses `⌥\`.
2. Scratchpad appears over the active work context.
3. Editor receives focus immediately.
4. User types a thought.
5. Autosave persists it locally.
6. `Esc` hides Rasc and restores focus to the prior app.

### 4.3 Refine

If the text needs shaping:

1. Press `⌘J`.
2. The orb switches to the shaping/refining state.
3. Foundation Models generates a single candidate.
4. Deterministic safety layers validate the proposal.
5. If safe and useful, a preview appears.
6. User accepts or cancels.
7. Accepted content is persisted and undoable.

No second repair generation is used. Safety violations resolve to the existing `noChange` path.

### 4.4 Keep

When the thought is settled:

1. The user invokes **Keep** (`⇧⌘K` in the current implementation).
2. Pending autosave is flushed.
3. `kept_at` is persisted.
4. The scratch session ends.
5. The scratchpad hides.
6. The next normal global-shortcut invocation opens a fresh unfinished scratch.

This is a key product behavior: Keep is not a star/favorite label. It is the completion moment.

### 4.5 Revisit

Kept and unfinished notes remain retrievable through:

- **Home**;
- **Search / History (`⌘P`)**.

Opening a kept note explicitly does not redirect to a blank note. It opens normally and can be edited without implicitly clearing the kept state.

### 4.6 Handoff or discard

The user can:

- **Copy Note** to the clipboard as exact plain text;
- **Share…** through native macOS sharing;
- **Discard Note** using soft-delete semantics.

Copy and Share never imply Keep or Discard.

---

## 5. Current surfaces

## 5.1 Scratchpad

The scratchpad is the center of Rasc.

Implementation characteristics:

- native floating `NSPanel`;
- keyboard-first;
- quick appearance over the current work context;
- frame persistence;
- focus restoration;
- resilient positioning across screens/display changes;
- content-driven intrinsic size is prevented from resizing the panel;
- editor-first visual hierarchy.

### Current empty state

The latest visual direction uses:

- Thinking Orb at top-leading;
- Home affordance at top-trailing;
- editor-origin empty-state copy:
  - **“Write something unfinished…”**
  - **“Thoughts, tasks, messages, ideas. Anything goes.”**
- no permanent Refine button in the empty state.

The important design decision is that the empty state looks like an editor, not a landing-page hero.

### Orb behavior

In the scratchpad's normal idle/editing state, the orb remains in the product's **Solving** state rather than changing on every keystroke. It changes for Refine/shaping. This reduced visual noise and kept the orb semantic rather than decorative.

### Completion interaction

Current scratchpad actions include:

- Keep / Unkeep;
- Refine;
- Home;
- Copy Note;
- Share…;
- Discard Note;
- contextual palette/menu access.

Completion actions are blocked during unsafe Refine states such as active generation/preview/acceptance so stale output cannot mutate a completed or discarded note.

---

## 5.2 Home

Home is a separate normal `NSWindow`, not the floating scratchpad panel.

Its role is **browsing and retrieval**, not editing.

Current Home structure:

- top action zone:
  - Rasc / orb identity anchor;
  - Search;
  - New Scratch;
  - Settings;
- **Kept** section;
- temporal unfinished sections such as:
  - Today;
  - Yesterday;
  - Earlier;
- responsive compact note-card grid.

The current visual direction deliberately avoids:

- sidebar;
- filter tabs;
- dashboard widgets;
- analytics;
- folders/tags;
- archive-management UI.

### Current card design

The latest polish moved Home from large sparse cards to a denser responsive grid suitable for scanning many notes.

Cards use:

- compact fixed/controlled geometry;
- title/excerpt/timestamp hierarchy;
- restrained border/fill;
- subtle violet keyboard selection/focus;
- ellipsis/menu primarily on hover/focus rather than permanent visual noise.

### Kept

Kept notes are visually and structurally separated from unfinished temporal notes, but the distinction remains lightweight. Search still covers all non-deleted notes.

---

## 5.3 Search / History

Shortcut: **`⌘P`**.

Search uses the local SQLite FTS5 index and the same repository/search path used elsewhere.

Properties:

- live query;
- keyboard navigation;
- Enter opens selected note;
- Esc closes the search surface and returns to the editor;
- kept notes remain searchable;
- kept state can be indicated quietly in results;
- no separate search engine or cloud index.

Several rounds of polish specifically fixed geometry discontinuities between Scratchpad, Search, and Command Palette and prevented transient surfaces from resizing the panel.

---

## 5.4 Command Palette

Shortcut: **`⌘K`**.

Command Palette is a compact action/navigation surface rather than a product mode.

It has included commands such as:

- New Scratch;
- Find Note;
- Refine;
- Open Home;
- Settings;
- context-aware completion actions after M16:
  - Keep / Unkeep;
  - Copy Note;
  - Share…;
  - Discard Note.

Keyboard behavior:

- type to filter;
- ↑ / ↓ navigation;
- Enter execute;
- Esc close.

---

## 5.5 Settings

Current Settings is a native grouped surface.

### General

- global shortcut recorder;
- Launch at Login.

### Refine

- Foundation Models / Apple Intelligence availability;
- **Refine Language** preference.

### Privacy

- concise local-first / on-device explanation.

### Explicitly absent

- model picker;
- cloud-provider settings;
- prompt editor;
- global free-text Refine preference;
- tone presets;
- named AI modes;
- themes.

---

## 5.6 Menu bar

Rasc runs as a menu-bar utility (`LSUIElement`) with no normal Dock presence.

Menu actions have included:

- Open Home;
- New Scratch;
- History / Search;
- Settings;
- Send Feedback… in beta builds;
- Quit Rasc.

The menu bar is recovery/discovery. The global shortcut remains the primary capture path.

---

## 6. Keyboard model

Current key interactions:

| Action | Shortcut |
|---|---|
| Toggle/open scratchpad | `⌥\` global shortcut |
| New Scratch | `⌘N` |
| Search / History | `⌘P` |
| Refine | `⌘J` |
| Command Palette | `⌘K` |
| Keep | `⇧⌘K` |
| Settings | `⌘,` |
| Hide / dismiss current surface | `Esc` |
| Quit | `⌘Q` |

Transient-surface Escape semantics are layered: dismiss the innermost transient surface first; only normal-editor Escape hides the panel.

---

## 7. Refine: product contract

Refine is the most heavily evaluated subsystem in Rasc.

### 7.1 Product behavior

Refine is not “rewrite this text to sound better.” It is a conservative transformation engine.

It should:

- preserve meaning;
- preserve language unless the user explicitly selects a fixed Refine language;
- preserve names and identifiers;
- avoid invention;
- avoid unjustified expansion;
- preserve protected literals;
- respect selection scope;
- keep intentional casualness when appropriate;
- return `noChange` when a safe improvement is not clear.

### 7.2 Accepted Refine v2 production pipeline

The canonical Refine v2 pipeline is conceptually:

1. **One-content-unit preflight**
   - highly under-specified one-content-unit whole-note inputs can resolve directly to `noChange` without asking Foundation Models to invent context.
2. **Language resolver v2**
   - language target resolution for match-note behavior;
   - avoids treating technical English tokens as evidence that an otherwise Portuguese/Spanish note is English;
   - uses conservative unresolved states instead of fabricated confidence.
3. **Single Foundation Models generation**
4. **High-confidence language validator**
   - independent language assessment can override brittle marker disagreement when confidence is strong;
   - wrong high-confidence output target rejects to `noChange`.
5. **Strict unresolved-language guard**
   - only for genuinely ambiguous/unknown + insufficient-confidence source resolution;
   - mixed/high inputs are explicitly excluded.
6. **Exact protected-literal validation**
7. **Money semantic validation**
8. **Percentage semantic validation**
9. **Time semantic validation**
10. **Selection safety checks**
11. **Duplicate-context selection guard**
12. final changed / `noChange` result.

There is no second-generation repair pass.

---

## 8. Refine language preference

M12C-001 added a user-facing **Refine Language** setting.

### Default

**Match note language**.

This uses the accepted Refine v2 resolver/validation stack.

### Fixed locale

When supported by the local Foundation Models environment, the user can select a fixed target such as Portuguese, English, or Spanish.

In fixed-locale mode, intentional translation is authorized. Language validation checks the output against the selected target instead of treating translation as drift.

The app discovers supported locales from the local Foundation Models API instead of presenting a large hardcoded universal list.

If a saved locale becomes unsupported, execution safely falls back to Match note language without crashing or silently sending an invalid contract.

---

## 9. Refine reliability program

Rasc went through an unusually extensive internal evaluation program before the current product state was accepted.

### 9.1 M12A — Reliability Lab

A versioned evaluation system was built around the same production Foundation Models provider path.

The initial corpus included roughly:

- 322 cases plus permanent regressions;
- Portuguese, English, Spanish, mixed-language inputs;
- tiny/ambiguous notes;
- already-good notes;
- selection cases;
- protected tokens;
- technical/code-like content;
- adversarial cases.

Baseline-v2 revealed severe issues including:

- PT → EN drift;
- ES → EN drift;
- unnecessary rewriting;
- over-expansion of tiny fragments;
- protected-token mutation;
- instability across repeated Foundation Models runs.

### 9.2 Human/frontier review infrastructure

A two-stage local blind review tool was built for adjudicating product output separately from benchmark expectations.

This prevented diagnostics/expected labels from contaminating the first-stage product judgment.

### 9.3 Accepted reliability improvements

The accepted M12B sequence ultimately introduced:

- language contract;
- conservative one-content-unit preflight;
- exact protected literals;
- semantic money validation;
- semantic percentage validation;
- constrained semantic time validation;
- selection-context hardening;
- duplicate-context selection guard;
- language resolver v2;
- calibrated high-confidence validator;
- strict unresolved-language safety guard.

Several experiments were rejected rather than forced into production.

### 9.4 Important rejected directions

Rejected/removed experiments include:

- prompt-only noChange/ambiguity calibration that increased over-abstention and instability;
- broad unresolved-language guard that harmed valid mixed-language refinements;
- short-Portuguese morphology overlay that created false-PT classifications;
- earlier over-aggressive language validator hardening;
- M12C-002 global free-text Refine preference.

These rejections are important product context: Rasc intentionally prefers a smaller, safer feature surface over maximizing customization.

### 9.5 Integrated gate

The final M12B integrated reliability gate showed material improvement over the frozen baseline-v2.

Representative results:

| Split | Baseline-v2 objective pass | Final objective pass |
|---|---:|---:|
| Dev | 43.0% | 66.3% |
| Validation | 43.9% | 54.4% |
| Holdout | 36.1% | 54.2% |

Critical failures also fell materially, and no new serious holdout failure class was discovered.

The final decision was:

> **M12B RELIABILITY COMPLETE**

Language, semantic-literal, and selection reliability were closed for the iteration rather than endlessly tuned toward synthetic benchmark perfection.

---

## 10. Protected information semantics

### 10.1 Exact-preservation classes

Production protects classes such as:

- URLs;
- emails;
- handles;
- identifiers;
- code-like literals;
- quoted literals;
- opaque IDs / UUID-like/hash-like IDs;
- selected exact numeric literals where appropriate.

### 10.2 Money

Explicit monetary identity and numeric value are protected semantically.

The validator distinguishes currency families conservatively and does not infer ambiguous `$` as USD.

Known unsafe examples such as `R$ 99,90 → $ 99.90` or dropping `R$` are rejected.

### 10.3 Percentage

Explicit `%`-marked values preserve:

- numeric percentage value;
- percent representation;
- multiplicity.

Harmless spacing normalizations may pass; representation-changing reinterpretations such as `50% → 0.5` are not treated as equivalent.

### 10.4 Time

Time validation allows narrow same-family normalization, such as 24-hour-to-24-hour formatting variants, while rejecting cross-family rewrites such as `15:00 → 3 PM` even when mathematically equivalent.

### 10.5 Intentionally unsupported semantic normalization

Current Refine does **not** try to semantically normalize every possible literal class.

Dates and generic/formatted-number normalization were deliberately left out because locale ambiguity and complexity did not justify production rules without stronger evidence.

---

## 11. Selection safety

Selection Refine receives limited surrounding context as read-only context, but replacement is constrained to the selected span.

Existing protections cover:

- size/runaway expansion;
- replacement-only semantics;
- protected literals inside the selected source;
- outside-selection literals not becoming preservation obligations;
- duplicate-text context leakage.

A specific failure where selected `retry` could become `retry again` by copying a longer duplicate occurrence elsewhere in context led to a narrow deterministic duplicate-context guard.

Selection reliability was then explicitly closed for the iteration.

---

## 12. Data model and persistence

Rasc uses **GRDB + SQLite** with versioned migrations and SQLite FTS5.

Core persisted concepts include:

- Note;
- content;
- timestamps;
- soft-delete state;
- `kept_at` lifecycle state;
- refinement revisions;
- FTS index/search state.

### Autosave

- draft/edit state is maintained in memory;
- autosave is debounced;
- pending work is flushed across important lifecycle boundaries such as hide, note switch, new note, completion actions, and termination paths;
- stale async work is guarded by content revisions.

### `kept_at`

Added in M16 through migration `v5_m16_notes_kept_at`.

Semantics:

- `nil` → unfinished;
- timestamp → kept/settled.

Existing notes migrate as unfinished. No inference is made.

Editing a kept note does not auto-unkeep it.

---

## 13. Active-note and concurrency model

The scratchpad has explicit session/active-note state rather than treating every window appearance as a new document.

Important invariants:

- stale Refine output cannot overwrite newer edits;
- A → B → A content cycles are still protected by monotonic content revision rather than naive string comparison;
- completion actions flush/cancel safely;
- wrong-note mutation is treated as a critical failure class;
- discard cannot leave a deleted note active;
- explicit opening of a kept note is distinct from normal fresh-scratch invocation after Keep.

---

## 14. Architecture and major technologies

### Platform

- native macOS application;
- Swift;
- SwiftUI;
- AppKit where windowing/system integration requires it.

### Persistence

- GRDB;
- SQLite;
- FTS5.

### AI

- Apple `FoundationModels`;
- `SystemLanguageModel.default`;
- `LanguageModelSession`;
- one generation per Refine attempt;
- no cloud fallback.

### Shortcuts

- `KeyboardShortcuts` Swift package.

### Visual orb

- vendored **ThinkingOrbsKit** from Libraries.dev;
- upstream MIT license retained;
- third-party notices included in the app bundle;
- integrated through Rasc's own wrapper rather than imported throughout product code.

### macOS system integrations

- `NSPanel` for scratchpad;
- normal `NSWindow` for Home;
- `NSStatusItem` for menu bar;
- `SMAppService` for Launch at Login;
- `NSPasteboard` for Copy Note;
- `NSSharingServicePicker` for Share…;
- native Foundation/NaturalLanguage APIs for language assessment.

---

## 15. Window model

Rasc deliberately uses different window roles rather than one universal app window.

### Scratchpad

- floating panel;
- compact;
- resizable within product constraints;
- frame persisted;
- opens on an appropriate active/frontmost display when no valid stored frame is available;
- survives display topology changes with off-screen recovery;
- does not grow because SwiftUI content has a larger intrinsic ideal size.

### Home

- normal resizable `NSWindow`;
- independent persisted frame;
- default implementation historically around `1000 × 680pt`, minimum around `760 × 520pt`;
- independent from scratchpad lifecycle.

### Onboarding

- dedicated onboarding window;
- historically `720 × 520pt`;
- focused, guided, transient experience;
- centered on the active display rather than behaving like a persistent workspace.

### Placement principle

Consistency comes from a window contract, not from forcing all surfaces to the same dimensions.

- onboarding: centered;
- Home: centered on first/open-without-valid-frame, then restore user frame;
- scratchpad: compact, context-aware placement, then restore user frame.

---

## 16. Visual design system

The visual system has been deliberately restrained.

### 16.1 Color semantics

Accepted direction:

- **violet** → state, focus, selection, navigation;
- **orange** → primary action;
- **neutral graphite/warm surfaces** → structure and content;
- **Thinking Orb palette** → separate semantic visual system.

A recent audit found two competing orange tokens (`controlAccent` vs `actionAccent`) in onboarding. The intended system is to converge primary CTAs on a single semantic action-orange token and ensure contrast tests exercise the actual visible action color.

### 16.2 Light / dark

Rasc uses an adaptive palette with:

- warm editorial light mode;
- graphite dark mode;
- restrained steel/violet accent behavior;
- reduced glass/material dependence where legibility would suffer.

### 16.3 Materials

Glass/material is used selectively on transient surfaces rather than everywhere.

Reduce Transparency falls back to solid control/background surfaces.

### 16.4 Motion

Motion uses small design-system timing tokens and respects Reduce Motion.

Principles:

- micro interactions are fast;
- surface transitions are subtle;
- no large spatial jumps between Scratchpad/Search/Palette;
- orb changes should not cause layout movement;
- Reduce Motion collapses spatial transitions to opacity/static states.

### 16.5 Home design

Current Home visual direction:

- compact action zone;
- responsive multi-column grid;
- compact note cards;
- Kept separated structurally from temporal unfinished sections;
- restrained selection wash;
- overflow/menu affordances mostly on hover/focus;
- no sidebar or dashboard visual language.

### 16.6 Scratchpad design

Current scratchpad direction:

- content-first;
- empty-state copy at the writing origin;
- orb top-leading;
- Home control top-trailing;
- no permanent Refine CTA in idle state;
- minimal chrome;
- interaction states communicate Refine/preview/noChange contextually.

### 16.7 Onboarding design

Current welcome screen direction:

- Thinking Orb as visual anchor;
- Rasc wordmark;
- **“A scratchpad for unfinished thoughts.”**
- supporting product loop copy;
- one primary CTA;
- trust line such as **“No account required · On-device”**;
- no competing Skip CTA on the opening screen.

---

## 17. Accessibility

Accessibility work includes:

- VoiceOver labels for core controls;
- selected traits in transient lists;
- accessible shortcut/keycap representations;
- Reduce Motion handling;
- Reduce Transparency fallback;
- Increase Contrast considerations;
- focus restoration after transient surfaces;
- keyboard-only operation for primary flows.

The goal is not merely WCAG-style contrast compliance but preserving native macOS interaction expectations.

---

## 18. App reliability program

M13 moved reliability evaluation beyond Refine and audited the app as a complete lifecycle.

Covered areas included:

- launch/bootstrap;
- autosave boundaries;
- note switching;
- persistence failure;
- stale Refine responses;
- termination during work;
- search/FTS;
- Home refresh;
- settings persistence;
- window frames;
- migrations;
- scale up to roughly 1,000 notes;
- release-bundle privacy checks.

Representative local benchmark results at 1,000 notes were in the low-millisecond range for bootstrap/recent/search/autosave operations, with FTS search around low single-digit milliseconds.

M13A concluded:

> **APP RELIABILITY READY**

with no P0/P1 blockers.

---

## 19. Release and acceptance history

### 19.1 Private distribution strategy

Because no paid Apple Developer / Developer ID setup was available, Rasc built a private-beta packaging path using:

- Release build;
- ad-hoc signing;
- Hardened Runtime;
- App Sandbox;
- `get-task-allow` removed;
- DMG packaging;
- SHA-256 checksum;
- verification scripts.

This supports trusted/private testing without paying Apple yet, but Gatekeeper friction remains.

### 19.2 beta.2

`0.1.0-beta.2` build 3 became the first frozen maintainer-accepted RC artifact.

It passed:

- clean Release packaging;
- bundle verification;
- smoke installation;
- manual interactive acceptance;
- app-wide reliability checks.

The artifact was ad-hoc signed because Developer ID/notarization credentials were unavailable.

### 19.3 beta.3 development line

M16 Thought Completion bumped the development line to:

- **0.1.0-beta.3**
- **build 4**

This line contains `kept_at`, Keep/Unkeep, handoff, Discard, and subsequent visual polish.

At the time of this context snapshot, beta.3 is the current product/source direction, while beta.2 remains the historically frozen/accepted artifact unless a later freeze has been executed outside this record.

### 19.4 Artifact retention

From beta.2 onward, the release process retains:

- DMG;
- SHA256 sidecar;
- release manifest;
- freeze/acceptance records.

This enables real upgrade testing between future retained builds.

---

## 20. Privacy and networking

Current product privacy posture:

- notes remain local;
- no account;
- no automatic telemetry;
- no cloud AI;
- no automatic product analytics;
- Foundation Models runs on-device;
- feedback is user-initiated through the mail client and includes system/version metadata rather than note content;
- release-bundle audits check for eval corpora, test bundles, databases, developer paths, and unintended artifacts.

Rasc should not claim stronger guarantees than the implementation provides, but local-first/on-device is a genuine architectural property, not marketing-only language.

---

## 21. Foundation Models availability

Refine depends on Apple Foundation Models / Apple Intelligence availability on the user's Mac.

When Foundation Models are unavailable, the rest of Rasc should remain usable:

- capture;
- autosave;
- Home;
- search/history;
- Keep;
- Copy/Share/Discard.

Refine availability is surfaced explicitly rather than silently falling back to cloud inference.

There is intentionally **no cloud fallback**.

---

## 22. Product state after M15A / M16

A dedicated product-gap audit concluded that the product was sellable in principle but missing one lifecycle capability: a thought-completion moment.

M16 implemented that capability.

The product now delivers:

> **Capture → Refine → Keep**

with handoff and discard completing the lifecycle.

This means the next major problem is no longer “what core app feature is missing?”

It is:

> **How does someone discover Rasc, understand it in seconds, want it, install it, and eventually pay for it?**

---

## 23. Milestone history

This is a condensed chronology of the project.

### M0 — Native shell

- SwiftUI/AppKit macOS project;
- floating `NSPanel`;
- editor;
- global shortcut;
- Settings basics.

### M1 — Persistence

- GRDB / SQLite;
- migrations;
- Note repository;
- autosave;
- active drafts;
- soft delete;
- lifecycle flushes.

### M2 — History/Search

- FTS5;
- `⌘P`;
- recent notes;
- keyboard navigation.

### M3A — Refine domain contract

- `RefinementRequest` / result/decision/domain types;
- provider abstraction;
- revision semantics.

### M3B — Foundation Models Refine

- on-device Foundation Models provider;
- `⌘J`;
- preview / accept / cancel;
- stale-response protection;
- selection Refine;
- conservative prompt evolution.

### M4 — Native product integration

- Command Palette;
- menu bar;
- Settings expansion;
- Launch at Login;
- transient surfaces;
- accessibility;
- window-frame persistence.

### M5 — Dogfood & stabilization

- launch/focus reliability;
- display positioning;
- search debounce;
- Refine undo persistence;
- diagnostics;
- lifecycle fixes.

### M6 — Release infrastructure

- bundle/signing audits;
- private ad-hoc beta pipeline;
- DMG/checksum verification;
- release scripts/docs.

### M7 — First-run onboarding

- dedicated coordinator/store/window;
- real production scratchpad handoff;
- real shortcut practice;
- Foundation Models availability behavior;
- onboarding persistence/migration.

### M7B / M8 / M9 — Visual system maturation

- official ThinkingOrbsKit integration;
- motion tokens;
- surface palette;
- scratchpad visual refinement;
- transient surface geometry/transition hardening;
- consistent focus/selection behavior.

### M10 — Home

- normal Home window;
- action zone;
- responsive note browsing;
- search reuse;
- note opening into scratchpad.

### M10B — Home polish

- editorial hierarchy;
- responsive card geometry;
- restrained surfaces;
- improved density.

### M11 — Private Beta 1 readiness

- versioning;
- feedback path;
- release notes;
- privacy audit;
- packaging readiness.

### M12A — Refine Reliability Lab

- corpus;
- deterministic scorers;
- stability runs;
- eval runner;
- baseline.

### M12B — Refine reliability hardening

Accepted final architecture from multiple isolated experiments:

- language contract;
- one-content-unit preflight;
- protected literals;
- semantic money/percentage/time guards;
- selection hardening;
- language resolver v2;
- validator calibration;
- strict unresolved-language safety.

Integrated holdout gate passed.

### M12C-001 — Refine Language Preference

- Match note language;
- supported fixed locales;
- intentional translation semantics;
- unsupported-locale fallback.

### M12C-002 — Global Refine Preference

Implemented and evaluated, then **rejected and removed** because it reintroduced safety failures.

### M13 — App-wide reliability

- lifecycle audit;
- scale tests;
- fault injection;
- migration/release/privacy checks;
- no P0/P1 blockers.

### M14 — Maintainer acceptance

- frozen beta.2 accepted through interactive packaged-app testing.

### M15A — Product gap & sellability audit

Conclusion: one core capability still missing — thought completion.

### M16 — Thought Completion

- `kept_at` lifecycle;
- Keep / Unkeep;
- Copy Note;
- Share…;
- Discard;
- Kept Home section;
- completion/concurrency tests;
- beta.3 development line.

### Post-M16 visual closeout

Recent design work focused on:

- final onboarding composition;
- Home responsive density/grid;
- scratchpad empty-state composition;
- orange/violet design-token semantics;
- window size/placement consistency.

The app is intentionally considered closed for feature work for now.

---

## 24. Current design/product decisions that should not be casually reopened

Unless real user/product evidence changes them, future work should preserve these decisions:

1. Rasc is a scratchpad, not a knowledge-management system.
2. Global shortcut is the primary entry point.
3. `⌥\` is the current default shortcut.
4. Refine is a single action, not a tool menu.
5. No permanent Refine button is needed in the empty idle editor.
6. Foundation Models stays on-device; no cloud fallback.
7. `noChange` is a successful outcome.
8. Deterministic safety can override Foundation Models output.
9. Only one Foundation Models generation per Refine attempt.
10. Language Preference exists; free-text style preference does not.
11. Keep is a lifecycle completion action, not a favorite/star.
12. Kept notes remain searchable/recoverable.
13. Home remains simple and scan-oriented; no sidebar/taxonomy system.
14. Orange is for primary action; violet for state/focus/selection/navigation.
15. Thinking Orb is semantic motion/identity, not decoration everywhere.
16. Copy/Share are handoff, not lifecycle mutation.
17. Discard uses soft-delete; no Trash product surface for now.
18. External beta feedback is useful but not required as a gate for internal product progress.

---

## 25. Known limitations / intentionally open items

### Product / design

- final app icon/logo may still need brand-level closure;
- public-facing commercial identity/website has not been completed;
- pricing is not finalized;
- no public distribution funnel exists yet.

### Distribution

- Developer ID / notarization is not currently part of the accepted private-beta path;
- ad-hoc builds may require Gatekeeper's private-beta manual Open flow;
- frictionless public macOS distribution will require Apple signing/notarization work.

### Refine

- Foundation Models output remains stochastic;
- residual language/evaluator disagreements exist but no repeatable blocking class remained after M12B;
- date and generic formatted-number semantic normalization are intentionally not implemented;
- model availability depends on the user's Apple Intelligence/Foundation Models environment.

### App reliability

Earlier audits recorded some non-blocking P2/P3 edge cases such as rare early-lifecycle/flush or presentation conditions. None became P0/P1 blockers in maintainer acceptance.

---

## 26. Commercial position today

Rasc is now **sellable in principle** as a premium independent Mac utility.

The strongest positioning is not “AI note-taking.” It is:

> **A native macOS scratchpad for unfinished thoughts.**

The clearest demo is the interaction itself:

1. user is working in another app;
2. `⌥\`;
3. Rasc appears;
4. user types something messy;
5. optional `⌘J`;
6. orb shapes;
7. user accepts;
8. Keep;
9. Rasc disappears;
10. work continues.

This 8–12 second loop should be the center of commercial storytelling.

### Commercial strengths

- understandable single-purpose utility;
- native Mac feel;
- local/on-device story is real;
- no account requirement;
- negligible recurring inference infrastructure cost;
- product has a clear interaction model rather than a generic AI feature list;
- strong demoability.

### Commercial gaps

- landing page;
- final brand/logo/app icon decision;
- polished product demo/video;
- screenshots/launch assets;
- pricing decision;
- Developer ID + notarization for public-quality install;
- payment/licensing/download/update flow;
- public support/privacy/release pages as needed.

---

## 27. Recommended next phase

Feature development should pause.

The next phase should be **Commercial Foundation**:

1. positioning and messaging;
2. landing-page information architecture;
3. landing-page visual implementation;
4. hero/product demo;
5. final brand/icon closure;
6. pricing hypothesis and commercial model;
7. Developer ID / notarized distribution when public release is justified;
8. download/payment/license/update mechanics;
9. launch.

The immediate next artifact should be a **Landing / Commercial Specification**, not another Swift feature milestone.

---

## 28. Proposed landing-page narrative

A strong initial structure is:

### Hero

> **A scratchpad for unfinished thoughts.**  
> Capture without thinking. Refine without prompting. Keep what matters.

Primary CTA: **Get Rasc for Mac**

Trust line: **No account required · On-device**

Hero visual: real product loop, preferably video rather than static marketing illustration.

### One shortcut away

Show `⌥\` opening Rasc over another app.

Message: Rasc appears wherever the user is already working.

### Write it messy

Show a raw, unfinished thought.

### Shape it

Show `⌘J`, Thinking Orb, and the improved proposal.

Message: no prompt, no tool picker, no chat.

### Keep what matters

Show Keep ending the scratch session and the next invocation starting fresh.

### Find it later

Show the Home / Kept grid and search.

### Private by default

Explain:

- on-device Foundation Models;
- local notes;
- no account;
- no cloud AI.

### Final CTA

Reinforce the lifecycle:

> **Thought → shaped → settled.**

---

## 29. Brand status

### Name

**Rasc** is settled.

The name supports the product idea of a rascunho / scratch / unfinished thought without being overly descriptive internationally.

### Symbol / orb

The Thinking Orb is now strongly associated with the interaction model and onboarding, but the final standalone logo/app icon remains a separate brand decision.

Earlier logo exploration considered:

- an orb-like abstract form;
- an incomplete circular gesture becoming coherent;
- a subtle relationship to the letter **R**;
- avoiding generic AI sphere/chatbot/sparkle/brain aesthetics.

The final brand mark should not be allowed to delay commercial-spec/landing work, but should be resolved before a serious public release.

---

## 30. What Rasc should avoid becoming

Future decisions should reject work that pushes Rasc toward any of these categories without overwhelming evidence:

- a full notes database;
- a second brain;
- a project manager;
- an AI chat app;
- a prompt playground;
- a cloud SaaS suite;
- a collaboration platform;
- an automation hub;
- an agent shell.

The product's value comes from **narrowness + speed + judgment + disappearance**.

---

## 31. Current one-paragraph canonical description

**Rasc is a native macOS scratchpad for unfinished thoughts. Press a global shortcut from anywhere, write without organizing, optionally shape the text with a single on-device Refine action, then Keep what matters and return to your work. Notes stay local, Refine is conservative and reversible, and Home/Search let you recover what you intentionally kept without turning Rasc into another knowledge-management system.**

---

## 32. Current status checklist

### Core product

- [x] Native macOS scratchpad
- [x] Global shortcut
- [x] Menu-bar utility
- [x] Autosave/local persistence
- [x] Multiple notes
- [x] Search / History
- [x] Home
- [x] Refine with Foundation Models
- [x] Selection Refine
- [x] Preview / accept / cancel / undo
- [x] Conservative `noChange`
- [x] Refine Language preference
- [x] Protected-literal safety
- [x] Language safety
- [x] Selection safety
- [x] Keep / Unkeep
- [x] Copy Note
- [x] Share…
- [x] Discard Note
- [x] Onboarding
- [x] Launch at Login
- [x] Light/dark support
- [x] accessibility-oriented motion/transparency behavior

### Reliability

- [x] Refine eval lab
- [x] frozen baseline + holdout
- [x] regression corpus
- [x] app-wide lifecycle audit
- [x] migrations
- [x] scale tests
- [x] release bundle verification
- [x] private-beta packaging
- [x] maintainer acceptance for beta.2 baseline

### Commercial / public launch

- [ ] final public landing page
- [ ] final logo/app icon closure
- [ ] product demo/video
- [ ] public screenshots/assets
- [ ] pricing decision
- [ ] Developer ID signing
- [ ] notarization
- [ ] public-quality download flow
- [ ] payment/licensing if paid
- [ ] update mechanism for public distribution
- [ ] launch/support/privacy web presence as appropriate

---

## 33. Context for future agents

When continuing Rasc:

1. **Do not assume a new feature is needed.** The app's core loop is deliberately considered complete for now.
2. **Read current product/reliability docs before touching Refine.** Many seemingly reasonable ideas were already tested and rejected.
3. **Do not revive M12C-002 global free-text preferences.** It failed safety acceptance.
4. **Do not replace local Foundation Models with cloud fallback** without an explicit product decision.
5. **Do not turn Keep into archive/favorite management.** It is a completion event.
6. **Do not add permanent AI chrome to the scratchpad** merely for discoverability.
7. **Do not optimize eval metrics at the expense of product behavior.** Holdout and benchmark perfection are not product goals.
8. **Preserve deterministic safety layers.** They exist because Foundation Models proposals are stochastic.
9. **Keep Home scan-oriented and simple.** No taxonomy system unless product strategy changes.
10. **The next major workstream is commercial presentation/distribution, not another app subsystem.**

---

## 34. Short glossary

**Scratch** — an unfinished active note.  
**Keep** — mark a thought as settled and end the current scratch session.  
**Kept** — persisted settled thought, still retrievable/editable.  
**Unkeep** — return a kept thought to unfinished state without changing content.  
**Refine** — one-action, on-device conservative text shaping.  
**noChange** — successful Refine outcome when a safe useful transformation is not justified.  
**Shaping** — the conceptual transition from unfinished thought to settled clarity.  
**Thinking Orb** — visual/state language used to represent Rasc's shaping activity.  
**Home** — browse/search surface, not the primary capture surface.  
**Match note language** — default Refine language policy.  
**Fixed locale** — optional Refine target-language preference authorized by the user.  
**Protected literal** — text whose identity/value must survive Refine according to deterministic rules.  

---

## 35. Final project statement

Rasc has moved from prototype to a coherent, reliability-hardened native Mac utility. The engineering challenge that dominated the middle of the project — making a small on-device Foundation Models interaction trustworthy — has been substantially addressed through deterministic guards, evaluation infrastructure, holdout testing, and app-wide reliability work. The product challenge that followed — completing the lifecycle beyond capture/refine — was addressed with Keep, handoff, and discard.

The core application should now be treated as **closed for feature expansion until a concrete product need justifies reopening it**.

The next challenge is commercial clarity: make a stranger understand the interaction in seconds, believe the privacy/local story, see why Rasc is different from Notes + AI, install it without friction, and decide that the utility is worth paying for.

That next chapter begins with positioning and the landing page.

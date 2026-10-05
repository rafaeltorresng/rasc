# Rasc Home Specification

> Historical specification/milestone reference. For current behavior, launch direction and superseded decisions, start with [CURRENT-PRODUCT](CURRENT-PRODUCT.md) and the [documentation index](README.md).


## 1. Purpose

Rasc Home is the persistent visual surface of Rasc.

It gives users a comfortable place to:

- see their notes
- visually browse recent thoughts
- search
- create a new scratch
- access core product actions
- understand where they are in the product

It complements the quick Scratchpad.

It does NOT replace it.

Core distinction:

Scratchpad = thought mode
Home = orientation mode

The product should support both:

"I need to capture something immediately"
and
"I want to open Rasc and look at my things."

---

## 2. Product invariant

Home must not turn Rasc into:

- a PKM system
- a second brain
- a folder-based notes application
- a task manager
- a Notion-like workspace

Do not add:

- folders
- tags
- favorites
- collections
- projects
- graph views
- spaces/workspaces
- AI chat
- semantic organization

Home organizes through:

- time
- search
- visual hierarchy

Nothing else in V1.

---

## 3. Window architecture

Home must use a normal macOS application window.

Do NOT reuse the floating Scratchpad NSPanel.

Home characteristics:

- normal NSWindow
- non-floating
- resizable
- persistent while the user works
- independent frame persistence
- appropriate for many notes
- behaves normally across Spaces

Scratchpad remains:

- NSPanel
- floating
- transient
- compact
- optimized for immediate capture

Home and Scratchpad must never fight over window size/state.

---

## 4. Window sizing

Recommended first-run size:

~1000 × 680 pt

Minimum:

~760 × 520 pt

The layout must adapt fluidly.

Home window position and size are persisted independently from Scratchpad.

Never reuse Scratchpad's WindowFrameStore keys.

---

## 5. Home entry points

Provide visual and existing-system access.

Required:

### Menu bar

Open Rasc

should open Home.

The quick Scratchpad remains accessible through the configured global shortcut.

### Command Palette

Add:

Open Home

Do not require the user to know the command.

### Scratchpad

Add one restrained Home affordance in the Scratchpad surface.

Preferred position:

top-right.

It should be:

- small
- quiet
- always discoverable
- not part of a toolbar

Use an appropriate SF Symbol.

Do NOT use the orb as a Home button.

The orb represents state, not navigation.

---

## 6. Primary Home composition

Use a single spacious surface.

Conceptually:

┌──────────────────────────────────────────────────────┐
│                                                      │
│  ◉  Rasc                  [ Search ]   + New Scratch │
│                                                      │
│  Your notes                                          │
│                                                      │
│  Today                                               │
│  ┌──────────────────┐ ┌──────────────────┐           │
│  │ note             │ │ note             │           │
│  │                  │ │                  │           │
│  │ excerpt...       │ │ excerpt...       │           │
│  │             14:31│ │             12:12│           │
│  └──────────────────┘ └──────────────────┘           │
│                                                      │
│  Yesterday                                           │
│  ...                                                 │
│                                                      │
└──────────────────────────────────────────────────────┘

Do not add a traditional application toolbar if custom composition remains
native and accessible.

Avoid excessive chrome.

---

## 7. Top action zone

The top region is the user's visual comfort zone.

It must contain:

- Rasc orb + wordmark
- Search field
- New Scratch
- Settings access

Do not make users remember shortcuts to perform basic actions.

Keyboard shortcuts remain accelerators.

Suggested hierarchy:

left:
orb
Rasc

center/right:
Search notes…

right:
+ New Scratch
Settings icon

Do not show all keyboard shortcuts permanently.

Tooltips may reveal them.

---

## 8. Orb behavior

Use the existing Rasc-owned semantic orb abstraction.

Do not import ThinkingOrbsKit directly into Home views.

Home default:

Rasc semantic state:
`.note` / current stable state

Underlying visual:
Thinking Orb `.solving`

The orb stays in `.solving` while:

- browsing
- scrolling
- selecting cards
- opening menus

Do NOT react to every interaction.

When search is actively being used:

Rasc semantic state:
`.searching`

Underlying:
Thinking Orb `.searching`

Do not switch state merely because the Search field has focus while empty.

Recommended rule:

empty query
→ solving

non-empty query
→ searching

Clearing query
→ solving

No per-keystroke animation logic beyond the state already being `searching`.

Reduce Motion remains supported by ThinkingOrbsKit.

---

## 9. Search

Home Search must reuse the existing lexical/FTS infrastructure.

Do not implement a second search engine.

Do not add semantic search.

Input:

Search notes…

Suggested height:

38–42 pt

Use the Rasc violet focus language.

Search should filter Home content in-place.

Do not open ⌘P Search automatically.

Home search and quick ⌘P search are two presentations over the same search
semantics.

### Query empty

Show chronological Home.

### Query non-empty

Replace grouped chronology with:

Search results

Do not preserve Today/Yesterday grouping for search results unless it proves
clearly useful.

Search results should prioritize relevance.

---

## 10. Notes overview

The main Home view uses a responsive grid.

Cards are appropriate here because the goal is spatial browsing.

Do not use cards inside quick ⌘P search.

Recommended adaptive card width:

min ~240 pt
ideal ~270–300 pt
max ~330 pt

Typical layout:

760–900 pt window:
2 columns

~1000–1250:
3 columns

larger:
3–4 columns

Avoid tiny cards.

Do not maximize card count at the cost of legibility.

---

## 11. Note cards

Each card is derived entirely from existing note content.

No new title field.

No AI-generated title.

Structure:

derived title
excerpt
updated time

### Title

First meaningful line / existing derived title logic.

Use:

SF Pro/System
14–16 pt
Medium

Maximum:
approximately 2 lines.

### Excerpt

Use the note body after the title where possible.

2–5 lines depending on card height.

Use:
system typography for scanning.

Do NOT render the entire note in SF Mono inside the Home card.

The actual Scratchpad remains the writing surface.

### Timestamp

Use compact human-readable metadata.

Examples:

14:31
Yesterday
Sep 12

Avoid verbose:

"11 hrs, 46 min"

Home should look editorial rather than diagnostic.

---

## 12. Card geometry

Cards should feel like surfaces, not boxes.

Suggested:

radius:
14–16 pt

padding:
16–18 pt

border:
extremely restrained

shadow:
minimal

dark:
graphite raised surface
subtle violet undertone

light:
warm raised neutral

No glass per card.

Do not create card soup.

Whitespace between cards should be significant enough for the layout to breathe.

Suggested grid gap:

14–18 pt

---

## 13. Card interaction

Hover:

- subtle elevation/material response
- restrained border change
- ≤ 150ms

Selection:

- violet wash / focus treatment
- clear keyboard focus

Do not use:

- 3D tilt
- large scaling
- glow
- Gooey
- Metal

Those effects belong to marketing surfaces, not note browsing.

---

## 14. Opening a note

Single click may select a note.

Double-click or Enter may open it.

However, to keep the interaction direct, V1 may use:

single click → open

if manual testing confirms this does not make grid navigation frustrating.

Preferred keyboard behavior:

arrow keys
→ move selection

Enter
→ open

Opening a note:

1. loads that note into the production ScratchpadSession
2. shows/activates the normal Scratchpad panel
3. focuses the editor
4. leaves Home open behind it

Do not create a second note editor inside Home in V1.

Home browses.
Scratchpad edits.

This is a key architectural invariant.

---

## 15. New Scratch

Primary Home action:

+ New Scratch

Behavior:

1. call the existing production new-scratch path
2. show Scratchpad
3. focus editor
4. Home remains available

Do not implement separate Home draft semantics.

---

## 16. Temporal grouping

When query is empty, group notes visually by existing `updated_at`.

Use:

Today
Yesterday
Earlier

Optional future refinement:

Previous 7 days

But V1 should begin with:

Today
Yesterday
Earlier

These groups are presentation only.

No schema changes.

Within each group:

updated_at DESC

Do not add user-manageable grouping.

---

## 17. Empty Home

If there are zero saved notes:

keep the layout extremely quiet.

Conceptually:

◉ Rasc

Your notes

Nothing here yet.

[ New Scratch ]

Supporting copy, if needed:

Your notes will appear here as you use Rasc.

No illustration.

No onboarding replay.

No feature cards.

---

## 18. Search no-results

Use:

No notes found.

Keep the Search field active.

No illustrations.

No state-reset CTA.

Clearing the query restores Home.

---

## 19. Visual identity

Home uses the visual language established by M9.

### Dark

graphite / ink
violet undertone

### Light

warm near-white
restrained violet depth

### Orange

Reserved primarily for actions.

Example:

New Scratch

Do not use orange across navigation state.

### Violet

Use for:

- selection
- search focus
- keyboard focus
- subtle depth/state

Do not turn the Home background visibly purple.

---

## 20. Typography

Home is more editorial than Scratchpad.

Use:

SF Pro/System:
- navigation
- titles
- card excerpts
- metadata
- actions

SF Mono:
- only shortcuts / technical keycaps where needed

Do not use mono for the entire Home interface.

Scratchpad remains the place where note content gets its distinctive writing
treatment.

---

## 21. Motion

Home should remain calm.

Allowed:

window/content entrance:
180–220ms

card hover:
120–150ms

selection:
120–150ms

search results transition:
~180ms

orb internal state:
ThinkingOrbsKit

Do not animate every card individually on first load.

No stagger animation across the grid.

No scroll-triggered animations.

Do not delay interaction for motion.

Reduce Motion:
- opacity/state changes only
- no unnecessary spatial transitions

---

## 22. Scrolling

The notes area scrolls.

The top action area should preferably remain stable.

Two viable options:

A:
entire page scrolls, top actions disappear naturally

B:
small sticky top action zone

Preferred V1:
subtle sticky action zone if it remains visually clean and native.

Do not use heavy blur under sticky content.

If sticky behavior introduces complexity or visual noise, use normal scrolling.

---

## 23. Responsive behavior

The Home window is resizable.

The grid adapts by available width.

Do not resize the window automatically based on content.

If width becomes narrow:

- reduce columns
- preserve card readability
- keep top actions usable

Never let actions overlap.

The minimum window size should prevent layouts that are obviously unusable.

---

## 24. Settings

Settings remains its existing system/settings surface.

Home only provides a visible entry point.

Do not embed Settings inside Home.

---

## 25. Relationship with quick Search

Keep both.

### ⌘P

Fast retrieval.

Use when:
"I know what I want."

### Home

Visual orientation/exploration.

Use when:
"I want to see what I have."

Do not redirect ⌘P into Home.

Do not replace quick Search with the Home search field.

---

## 26. Relationship with Command Palette

Keep ⌘K.

Home reduces dependency on it but does not replace it.

Commands remain accelerators.

Add:

Open Home

if not already present.

Do not expose dozens of new Home-specific commands.

---

## 27. Scratchpad Home affordance

Add one subtle visual entry point.

Preferred:

small icon at top-right.

It must not create a visible toolbar.

Approximate:

24–28 pt hit surface

The icon can become more visible on hover/focus.

Accessibility label:

Open Rasc Home

Tooltip:

Open Home

Do not use the orb for this.

---

## 28. Window lifecycle

Home window should:

- restore last frame
- restore reasonably after display topology changes
- not become floating
- not appear on every Scratchpad invocation
- not steal focus when the global Scratchpad shortcut is used

Opening Scratchpad while Home is open:

Home stays where it is.
Scratchpad becomes active.

Closing Home:

does not quit Rasc.

Rasc remains menu-bar/background utility.

---

## 29. Performance

Home may eventually contain many notes.

Do not render hundreds of heavy SwiftUI cards unnecessarily.

Use an appropriate lazy container:

LazyVGrid

Avoid:

- per-card orb
- blur
- shader
- expensive material
- continuous animation

Search must remain responsive.

---

## 30. Data

Reuse existing NoteRepository.

Home needs:

- recent/all non-deleted notes
- existing derived title/snippet logic
- existing FTS search

Do not add columns.

Do not add migrations.

Do not create separate Home persistence.

---

## 31. Accessibility

Home must be fully keyboard usable.

Required:

- logical focus order
- card accessible title
- card accessible excerpt if useful
- selected card state
- Search label
- New Scratch label
- Settings label
- Home icon label from Scratchpad
- Increase Contrast
- Reduce Motion
- Reduce Transparency

Cards must remain distinguishable without relying only on color.

---

## 32. V1 exclusions

Do NOT implement:

- list/card toggle
- folders
- tags
- pinning
- favorites
- archive
- trash UI
- multi-select
- bulk actions
- sorting controls
- filters
- AI summaries
- semantic search
- drag/drop organization
- note detail pane
- statistics
- activity feed
- cloud sync
- collaboration

These require evidence from actual usage.

---

## 33. Definition of done

Rasc Home is successful when a user can launch Rasc visually and:

see their notes
→ understand what is recent
→ search
→ open a note
→ create a new scratch
→ reach Settings

without knowing any keyboard shortcut.

At the same time:

the quick Scratchpad remains faster for capture.

The user should understand:

Home is where Rasc lives.
Scratchpad is where a thought appears.
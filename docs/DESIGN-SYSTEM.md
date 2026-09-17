# Rasc Design System

Rasc is a quiet macOS utility for unfinished thoughts.

Its visual language is **Shaping**:

> raw → uncertain → shaping → settled → clear

The interface should feel calm while idle and almost physical while transforming.

The design must never compete with the user's text.

---

## 1. Core principles

### Content first

Text is the primary visual element.

Chrome, motion, materials, icons, and AI states exist only to support:

- capture
- retrieval
- refinement
- orientation

If removing an element makes the text easier to use without reducing clarity, remove it.

### Quiet at rest

Idle screens should have almost no visible motion.

Avoid:

- decorative loops
- floating particles
- animated gradients
- constant glowing
- unnecessary shimmer
- moving backgrounds

Ambient motion is reserved for rare branded surfaces such as the landing-page hero.

### Physical during change

Movement should explain state transitions.

Prefer:

- morphing
- resizing
- merging
- settling
- matched geometry
- direct spatial continuity

Avoid generic:

- fade out → unrelated fade in
- slide carousels
- bouncing
- spinning loaders
- large spring overshoot

### Minimal decisions

Visual minimalism means fewer decisions, not merely fewer pixels.

Avoid introducing:

- unnecessary controls
- redundant labels
- multiple equivalent actions
- persistent toolbars
- visible settings for uncommon behavior

### Native before custom

In the macOS app:

1. use native behavior
2. use native controls
3. use native materials
4. customize only where Rasc gains meaningful identity

Never sacrifice platform behavior for visual novelty.

---

# 2. Brand language

## Name

**Rasc**

Derived from *rascunho*: something unfinished, temporary, and still taking shape.

Preferred casing:

`Rasc`

Avoid:

`RASC`
`rasc.ai`
`Rasc AI`

AI is a capability, not the brand.

## Core phrase

**A scratchpad for unfinished thoughts.**

## Supporting phrase

**Capture without thinking. Refine without prompting.**

Use sparingly.

Do not repeat marketing copy throughout the product UI.

---

# 3. Visual hierarchy

Rasc should visually prioritize:

1. user content
2. current action/state
3. navigation
4. product chrome
5. branding

Branding should almost disappear inside the actual editor.

---

# 4. Color

Use a restrained neutral system.

Do not build the identity around a fixed saturated brand color.

## Semantic hierarchy

### Background
System-derived near-white / near-black.

### Primary text
Native primary foreground.

### Secondary text
Native secondary foreground.

### Tertiary text
Used only for hints, timestamps, shortcut labels.

### Accent
One restrained adaptive accent.

It may carry a slightly cool metallic character, but must remain subtle.

### Success
Use primarily for temporary confirmation.

### Error
Use only where actionable.

Never use color alone to communicate state.

---

# 5. Typography

## Product UI

Use San Francisco system typography.

Default:

- `.body` for editor text
- `.callout` or `.subheadline` for auxiliary content
- `.caption` for transient metadata

Avoid custom fonts inside the app.

## Monospace

Use SF Mono only for:

- keyboard shortcuts
- technical identifiers when appropriate
- tiny state labels
- developer-facing surfaces

Do not render normal notes in monospace by default.

## Landing page

Primary:
- system / Geist / equivalent restrained sans

Monospace:
- SF Mono-like face for shortcuts and technical accents

Typography should provide the personality before effects do.

---

# 6. Shape language

Use moderate continuous radii.

Avoid extreme pillification.

## Guidelines

Small controls:
`8–10px`

Cards / transient containers:
`12–16px`

Large marketing surfaces:
`16–24px`

True pills only for:

- shortcut capsules
- compact status indicators
- small segmented states

The scratchpad itself should feel like a window, not a floating bubble.

---

# 7. Material system

## App

### Editor

Solid or nearly solid.

Never place primary note text on visually busy glass.

### Transient surfaces

Glass/material is appropriate for:

- Search
- Command Palette
- Refine Preview
- small transient feedback

On macOS 26+:
use native Liquid Glass selectively.

Older versions:
use appropriate system Material fallback.

### Rule

**Content is solid. Chrome may be translucent.**

---

## Landing page

Three material families are allowed.

### Neutral solid

Default.

Most of the page should use this.

### Glass

Use for product simulations and floating interface surfaces.

### Metal

Use only as an accent for moments such as:

- main CTA
- selected icon treatment
- key marketing badge
- focal border

Metal must never become the general page material.

---

# 8. Motion philosophy

Motion exists to answer one of these questions:

- What changed?
- Where did this come from?
- Where did this go?
- What is processing?
- What can I interact with?

If an animation answers none of them, remove it.

---

# 9. Motion budget

Each view may have at most:

- **1 primary motion event**
- **1 microinteraction per user action**
- **0 competing decorative animations**

If two elements move simultaneously, one must clearly be subordinate.

---

# 10. Timing tokens

Use these ranges as defaults.

## Micro

`120–180ms`

For:

- button press
- hover
- selection movement
- small control state

## Surface

`180–240ms`

For:

- Search opening
- Command Palette
- Refine Preview
- small overlays

## Morph

`240–360ms`

For:

- shared-element transitions
- panel → preview
- onboarding transformations

## Hero storytelling

`400–700ms`

Only on the landing/onboarding.

Never make users wait for these transitions to complete before interacting.

## Ambient

`4–10s`

Extremely subtle loops only.

---

# 11. Easing

Prefer spring-like movement with restrained overshoot.

Movement should feel:

- responsive
- weighted
- controlled

Avoid:

- elastic bounce
- overshooting cards
- playful wobble
- exaggerated inertia

When possible, allow native SwiftUI/Animation or Motion physics to determine exact curves.

Do not manually tune exotic cubic-bezier curves without a concrete need.

---

# 12. Reduced motion

All nonessential animations must respect Reduce Motion.

When enabled:

- replace morphs with fast opacity changes
- remove ambient loops
- remove translation/scale when unnecessary
- preserve state clarity

Never remove feedback entirely.

---

# 13. Signature element: Shaping Orb

The Shaping Orb represents computation only when Rasc is actively transforming something.

It is not a mascot.

## States

Allowed conceptual states:

- breathing
- shaping
- settling

Avoid exposing multiple named AI states to users.

## App

Approximate visual size:
`16–22px`

Use beside subtle text:

`refining…`

Never center a giant orb over the editor.

## Onboarding

May be larger:

`32–48px`

## Landing

May become a branded hero element:

`48–72px`

Still restrained.

## Motion

Idle:
minimal breathing.

Refining:
more active shaping / internal motion.

Success:
settle → dissolve.

Failure:
do not turn red and shake dramatically.
Return to neutral state and show concise error text.

---

# 14. Text transformation

Refine should visually communicate that existing text is being shaped rather than replaced by magic.

Prefer:

- shared word positioning
- subtle letter/line morph
- local opacity transitions
- layout movement
- preserving spatial continuity

Avoid:

- deleting everything then typing new text character-by-character
- typewriter AI effects
- token streaming
- sparkling words
- rainbow highlighting

Rasc does not imitate a chatbot.

---

# 15. Shared-element transitions

Shared elements are a core part of the Rasc language.

Examples:

### Shortcut → Scratchpad

During onboarding:

`⌥ Space`

may expand into the real scratchpad surface.

### Search result → Editor

Selected history item should feel spatially connected to the note that opens.

### Editor → Refine Preview

The preview should emerge from the editor state rather than appearing as an unrelated modal.

### Panel hide

The panel should contract/fade quickly toward its resting state.

Do not over-animate normal repeated usage.

After onboarding, common interactions must prioritize speed.

---

# 16. Keyboard language

Keyboard interactions should feel physical.

## Keycap

Use keycap UI for:

- `⌥ Space`
- `⌘J`
- `⌘P`
- `⌘K`
- `Esc`
- `↵`

## States

Idle:
neutral.

Hover:
very small elevation.

Pressed:
- slight downward displacement
- subtle scale reduction
- shadow compression

Release:
short controlled spring.

When the user presses the actual physical shortcut during onboarding, the on-screen keycap should react simultaneously.

This is an important branded interaction.

---

# 17. Gooey motion

Gooey behavior is permitted only where merging itself communicates something.

Good uses:

- onboarding shortcut keycaps merging/separating
- CTA metadata emerging from a button
- small related controls joining into one temporary state

Bad uses:

- navigation
- every button
- editor
- history results
- normal production controls

Maximum:
one gooey interaction per surface.

---

# 18. Metal treatment

Metal is a marketing accent, not an application material.

Use for:

- primary landing CTA border
- hero badge
- small icon treatment
- subtle pointer-reactive halo

Preferred:
silver / neutral metallic.

Avoid:

- chrome typography everywhere
- gold unless contextually justified
- strong rainbow chromatic effects
- entire cards rendered as liquid metal

Cursor response should be small and physically plausible.

---

# 19. Dither / grain

Use primarily on the landing and onboarding.

Purpose:
represent transition between rough and resolved.

Possible use:

`raw → dithered → sharp`

Grain:
extremely subtle.

Do not reduce text legibility.

Do not add visible noise over editor content.

---

# 20. App interaction motion

## Open Rasc

Duration:
~150–180ms

Use:
- slight opacity
- minimal scale or vertical movement

Must never delay keyboard readiness.

The editor must be focused before or independently of animation completion.

## Hide

Faster than open.

Approx:
120–160ms.

## Search

Surface appears with restrained material transition.

Results:
do not fade every row independently.

Selected row:
shared moving highlight.

## Command Palette

Same motion grammar as Search.

Do not visually create a separate subsystem.

## Refine

Sequence:

1. user presses `⌘J`
2. small Shaping Orb appears
3. editor remains visually stable
4. result arrives
5. preview surface morphs in
6. Enter settles accepted content into editor
7. Esc restores original editor state

## noChange

Orb:
shaping → subtle check/settle → disappear.

Copy:
`Already useful.`

Keep feedback under ~1.5s where appropriate.

## Errors

No shake animation.

Use:

- concise text
- appropriate semantic foreground
- stable layout

---

# 21. Onboarding motion system

The onboarding is the most expressive product surface.

Still, each step gets only one primary motion.

## Welcome

Subtle ambient Shaping Orb or brand mark.

No large continuous spectacle.

## Shortcut

Physical keycaps.

Changing shortcut may use restrained gooey/morph behavior.

## Try it

Onboarding visually yields to the actual Rasc panel.

The user should feel like the tutorial disappeared and the product took over.

## First Refine

Shaping Orb is introduced naturally.

No explanation of models or AI infrastructure.

## Accept

Content settles into final state.

## Escape

Panel quickly disappears.

This teaches the core behavior through motion.

## Completion

Almost static.

The calm after the interaction reinforces:

`Rasc stays out of the way.`

---

# 22. Landing page motion system

Marketing may be more expressive than the app, but must use the same vocabulary.

## Hero

Primary animation:
interactive Rasc demo.

Not:
animated headline + background + orb + CTA + particles simultaneously.

## Demo flow

Recommended:

1. raw thought appears
2. physical `⌘J` reacts
3. Shaping Orb activates
4. text morphs into refined form
5. panel settles
6. `Esc` closes it

## Scroll

Scroll should reveal product behavior, not decorate sections.

Allowed:
- shared product panel moving between contexts
- sticky storytelling section
- subtle depth transitions

Avoid:
- every block fading upward
- parallax everywhere
- horizontal scroll hijacking
- animation that blocks reading

## Privacy section

Almost no motion.

Copy:

`On-device.`
`No account.`
`No cloud AI.`

Stillness is intentional.

## Final CTA

Metal accent may return.

One focal motion only.

---

# 23. Web implementation stack

Preferred:

- Next.js
- React
- Tailwind CSS
- shadcn/ui
- Motion

shadcn provides structural primitives only.

Rasc's design system determines:

- typography
- spacing
- radius
- motion
- materials
- states

Never ship default shadcn aesthetics unchanged.

## External components

Copy individual components when useful.

Allowed inspiration/source pools:

- Motion Primitives
- Animate UI
- Cult UI
- Thinking Orbs
- Gooey
- Metal
- React Bits
- Aceternity
- Magic UI

Do not install entire visual libraries for one effect.

Own the resulting code.

---

# 24. Native implementation

SwiftUI is the primary presentation layer.

Use AppKit only where platform behavior requires it.

Prefer:

- native glass/material APIs
- matchedGeometryEffect where appropriate
- SwiftUI transitions
- system accessibility
- native reduced-motion environment

Do not attempt to reproduce web shader effects inside the production app unless they add clear product value.

The native Rasc must remain lighter and quieter than the marketing site.

---

# 25. Spacing

Use a 4pt base grid.

Core spacing tokens:

`4`
`8`
`12`
`16`
`24`
`32`
`48`
`64`
`96`

Avoid arbitrary spacing unless optical correction requires it.

The app should lean toward compact spacing.

The landing should use substantially more whitespace.

---

# 26. Density

## App

High information efficiency.

Avoid wasted vertical space.

## Onboarding

Medium-low density.

One idea per stage.

## Landing

Low density.

Large whitespace and clear visual rhythm.

---

# 27. Icons

Prefer SF Symbols in the native app.

Web icons should visually match SF Symbol weight and simplicity.

Avoid mixing multiple icon styles.

Do not use icons where text is clearer.

---

# 28. Borders and shadows

Borders:
subtle and low contrast.

Shadows:
soft, short, material-aware.

Avoid:

- large dark drop shadows
- colored glows
- strong card borders
- heavy elevation hierarchy

Depth should primarily come from:

- material
- overlap
- movement
- subtle shadow

---

# 29. Hover

Hover states should never be the only way an interaction becomes discoverable.

Use hover for:

- small elevation
- subtle material response
- cursor-proximity metal
- tiny highlight

Do not animate layout significantly on hover.

---

# 30. Empty states

Empty states should be textual and quiet.

Example:

`Start typing.`

Not:

- illustrations
- mascots
- feature cards
- educational carousel

---

# 31. Feedback

Feedback should be proportional.

### Success

Small, temporary.

### noChange

Neutral, not celebratory.

### Error

Stable and actionable.

### Destructive action

Clear, explicit, undoable where practical.

No confetti anywhere in Rasc.

---

# 32. Accessibility

Minimum requirements:

- full keyboard navigation
- VoiceOver labels
- sufficient contrast
- Dynamic Type-equivalent system scaling where applicable
- Reduce Motion support
- Reduce Transparency compatibility
- no state represented only by color
- predictable focus movement

Visual novelty never overrides accessibility.

---

# 33. Performance

Motion must never compromise the defining experience:

`shortcut → cursor ready`

The app must not wait on:

- animation completion
- shaders
- network
- model
- unnecessary rendering

to become interactive.

For web:

- avoid large WebGL payloads above the fold unless clearly justified
- lazy-load decorative effects
- respect `prefers-reduced-motion`
- avoid hydration-heavy components for static content
- keep hero interactive without making the whole page client-rendered

---

# 34. Anti-patterns

Do not use:

- AI-purple gradients as identity
- animated aurora backgrounds
- stars / meteors
- generic floating particles
- infinite logo marquees without real social proof
- glowing cards everywhere
- glass on every surface
- custom cursor replacement
- excessive magnetic buttons
- typewriter AI output
- streaming-token visualizations
- 3D tilt cards
- animation on every scroll section
- large decorative blobs
- fake terminal aesthetics
- cyberpunk styling
- UI that looks like a component-library showcase

---

# 35. Product-specific visual rules

## Capture

Must be almost invisible.

No animation should compete with typing.

## Search

Fast and spatially stable.

## Refine

This is where the brand becomes expressive.

Use:
- shaping
- morphing
- settling

## History

Utility-first.

Do not turn history into a gallery.

## Settings

Pure native utility.

No branding theater.

---

# 36. Motion acceptance test

Before adding any animation, ask:

1. What state change does it explain?
2. Would the interaction remain understandable without it?
3. Does it slow repeated use?
4. Does another animation already own attention?
5. Does it respect Reduce Motion?
6. Is this Rasc, or merely a trendy effect?

If question 1 has no strong answer, do not add the animation.

---

# 37. Design review checklist

Before merging visual work:

### Hierarchy
- Is user text still the strongest element?
- Is there one obvious primary action?

### Motion
- Is there at most one primary animation?
- Does it communicate state?
- Does it remain fast after the tenth repetition?

### Material
- Is glass used only where appropriate?
- Is metal limited to accent surfaces?
- Is content readable over every material?

### Brand
- Does it communicate shaping rather than generic AI?
- Could this still look like Rasc with all logos removed?

### Accessibility
- Keyboard complete?
- VoiceOver meaningful?
- Reduce Motion supported?
- Contrast sufficient?

### Performance
- No visible typing lag?
- No animation blocking interaction?
- No oversized decorative dependencies?

---

# 38. Rasc signature

If only five visual ideas survive, keep these:

1. **Shaping Orb**
2. **Raw → refined text morph**
3. **Shared-element surface transitions**
4. **Physical keyboard interactions**
5. **Dither → sharp transformation**

Everything else is optional.

These five should be enough to make Rasc visually recognizable across:

- macOS app
- onboarding
- landing page
- screenshots
- product videos
- social media

---

# 39. Final principle

Rasc should not look futuristic because it has more effects.

It should feel modern because every transition behaves as if the interface understands what is happening.

**Quiet when thinking is yours.  
Physical when Rasc shapes it.**
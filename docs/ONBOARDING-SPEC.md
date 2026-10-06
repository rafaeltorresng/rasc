# Rasc Onboarding Specification

> Historical specification/milestone reference. For current behavior, launch direction and superseded decisions, start with [CURRENT-PRODUCT](CURRENT-PRODUCT.md) and the [documentation index](README.md).


## 1. Goal

The onboarding must teach the core Rasc loop through direct interaction:

> summon → capture → refine → dismiss

The user should finish onboarding understanding three things without needing documentation:

1. Rasc is always one shortcut away.
2. Rasc accepts unfinished thoughts.
3. Refine improves them without requiring a prompt.

The onboarding is not a feature tour.

It must not attempt to teach the full product.

---

# 2. Activation definition

A user is considered successfully activated when they have:

1. completed or accepted the global shortcut setup;
2. invoked the real Rasc panel using that shortcut;
3. typed meaningful non-whitespace content;
4. returned from the live scratchpad exercise.

Refine is strongly encouraged but must not block activation because Apple Intelligence may be unavailable.

Launch at Login is optional and must never block completion.

---

# 3. Target duration

Ideal:

`45–90 seconds`

Acceptable:

`< 2 minutes`

If the user already understands keyboard-first Mac utilities, they must be able to skip the guided portion almost immediately.

No timed animation should artificially extend onboarding.

---

# 4. Product principles

## Use the real product

Whenever possible, onboarding must invoke the actual:

- shortcut system;
- scratchpad panel;
- editor;
- Refine pipeline;
- Foundation Models provider;
- Launch at Login implementation.

Do not create fake copies of production interactions just for onboarding.

## Progressive disclosure

Teach only:

- global shortcut;
- typing;
- `⌘J Refine`;
- `Esc`.

Do not introduce:

- `⌘P`;
- `⌘K`;
- `⌘N`;
- History;
- Command Palette;
- Settings;
- database concepts;
- provider/model terminology.

Those belong to contextual discovery after onboarding.

## No account wall

There is no sign-in, registration, email capture, account creation, or browser authentication.

## No AI theater

Do not use:

- chatbot language;
- prompt examples;
- token streaming;
- “AI assistant” terminology;
- exaggerated intelligence claims.

The user experiences Refine rather than being told about AI.

---

# 5. Onboarding architecture

The onboarding has five logical stages:

```text
WELCOME
   ↓
SHORTCUT
   ↓
LIVE CAPTURE
   ↓
LIVE REFINE
   ↓
READY
```

`LIVE CAPTURE` and `LIVE REFINE` happen inside the real Rasc scratchpad.

The onboarding window must temporarily yield control to the production panel.

---

# 6. State model

Use explicit state.

Conceptually:

```swift
enum OnboardingStep: Int, Codable {
    case welcome
    case shortcut
    case capturePractice
    case refinePractice
    case completion
    case finished
}
```

Additional runtime state:

```swift
struct OnboardingState {
    var step: OnboardingStep
    var shortcutConfirmed: Bool
    var scratchpadInvoked: Bool
    var meaningfulTextEntered: Bool
    var refineAttempted: Bool
    var refineCompleted: Bool
    var refineSkipped: Bool
    var launchAtLoginEnabled: Bool
}
```

Do not derive onboarding progress from incidental UI state.

---

# 7. Persistence

Persist only lightweight onboarding state in `UserDefaults`.

Recommended:

- current step;
- onboarding completed;
- whether contextual hints have already been shown.

Do not persist tutorial text or duplicate note content.

If the app quits during onboarding, resume from the nearest safe stage.

Never reopen directly into a broken transient state.

---

# 8. Resume behavior

## Quit during Welcome

Resume at Welcome.

## Quit during Shortcut

Resume at Shortcut with current configured shortcut.

## Quit during Capture Practice

Resume at Capture Practice introduction.

Do not automatically reopen the scratchpad on launch.

## Quit during Refine

If no Refine result was accepted, resume at Capture Practice or Refine Practice depending on whether meaningful note content still exists.

## Quit during Completion

Resume at Completion.

---

# 9. Skip behavior

A quiet secondary action:

`Skip setup`

must be available from Welcome and Shortcut.

Skipping:

- preserves current/default shortcut;
- marks onboarding complete;
- does not create any note;
- does not enable Launch at Login;
- opens normal Rasc behavior.

Never shame or warn the user for skipping.

---

# 10. Window model

The onboarding should use a dedicated window/surface rather than the production scratchpad panel.

Recommended approximate size:

`720 × 520 pt`

Properties:

- centered on active screen;
- non-resizable during onboarding;
- standard native focus behavior;
- no unnecessary titlebar chrome if safely achievable;
- visually independent from the floating scratchpad.

Do not turn the production `NSPanel` itself into a multi-page onboarding wizard.

---

# 11. Screen 1 — Welcome

## Purpose

Explain Rasc in one glance.

## Layout

Centered vertical composition.

Recommended hierarchy:

```text
[ subtle brand mark / shaping orb ]

Rasc

A scratchpad for unfinished thoughts.

Capture without thinking.
Refine without prompting.

[ Get started ]

No account · On-device
```

## Copy

Primary:

**Rasc**

**A scratchpad for unfinished thoughts.**

Secondary:

**Capture without thinking. Refine without prompting.**

Trust line:

**No account · On-device**

Primary CTA:

**Get started**

Secondary:

**Skip setup**

## Motion

One primary motion only.

Allowed:

- subtle Shaping Orb breathing;
- brand mark settle on initial appearance.

Duration:
`~400–600ms` initial settle.

No looping spectacle.

## Interaction

`Return` activates Get started.

`Esc` should not quit the app.

Do not overload standard dismissal semantics here.

---

# 12. Screen 2 — Shortcut

## Purpose

Make the global shortcut memorable and personally owned.

## Layout

```text
One shortcut away.

Rasc appears wherever you're working.

        ┌──────────────┐
        │   ⌥ Space    │
        └──────────────┘

         Press to change

          [ Continue ]
```

Secondary footer:

`You can change this anytime in Settings.`

## Shortcut component

Use the real shortcut recorder/configuration behavior.

The visual representation may be custom, but the underlying setting must be the production source of truth.

## Default

`⌥ Space`

Do not force customization.

## Validation

If the chosen shortcut conflicts with a known system/app shortcut and KeyboardShortcuts exposes that condition, show a concise inline message.

Do not block on speculative conflicts that cannot be reliably detected.

## Motion

Physical keycaps.

On actual keypress:

- depress `1–2pt`;
- scale approximately `0.97–0.98`;
- shadow compresses;
- controlled spring returns.

If keys are added/removed while configuring, a restrained morph is allowed.

No large goo effect.

## Continue condition

A valid shortcut exists.

---

# 13. Transition — Shortcut to Live Capture

This is the first signature transition.

After Continue:

1. onboarding content simplifies;
2. instruction appears:

   **Try it.**

   **Press ⌥ Space**

3. onboarding window visually recedes;
4. application waits for the actual global shortcut;
5. user invokes Rasc;
6. the real scratchpad appears.

Do not programmatically simulate the shortcut.

The user must perform the actual physical action.

---

# 14. Capture Practice

## Purpose

Teach the fundamental Rasc behavior using the real editor.

## Scratchpad state

Open the production scratchpad.

If necessary, use a temporary onboarding presentation flag that affects hints only.

Do not fork editor behavior.

## Placeholder

Preferred:

**Write something unfinished…**

Optional second-line hint:

`A thought, task, message, idea — anything.`

The placeholder must disappear immediately when typing begins.

## User content

The user should write their own text.

Do not pre-populate the editor with demo text.

Examples must not become saved content automatically.

## Meaningful input threshold

For onboarding progression, meaningful content should be:

- non-whitespace;
- not merely one accidental keystroke.

A simple threshold such as `>= 3 visible characters` is sufficient.

Do not over-engineer semantic validation.

## Persistence

This is a real note.

Existing draft persistence rules apply.

If meaningful content is entered, onboarding must not discard it when completed.

---

# 15. Capture contextual hint

Before typing:

```text
Write something unfinished.
```

After meaningful input exists:

```text
⌘J  Refine
```

The hint should appear in a quiet footer or accessory position.

No tooltip attached to the editor body.

## Motion

The Refine hint may:

- fade in;
- move vertically no more than `4–6pt`.

Duration:
`150–220ms`.

No pulse loop.

---

# 16. Refine Practice

## Trigger

The preferred path is the user pressing actual `⌘J`.

Do not require clicking a Refine button.

A clickable affordance may remain available for accessibility/discoverability, but keyboard interaction is primary.

---

# 17. Foundation Models availability

Check real provider availability.

There are four UX states.

## Available

Proceed normally.

## Apple Intelligence disabled

Show concise inline state:

**Refine needs Apple Intelligence.**

Secondary:

**Rasc still works without it.**

Actions:

- `Open System Settings`
- `Not now`

`Not now` advances onboarding.

## Model preparing / temporarily unavailable

Copy:

**Refine is getting ready on your Mac.**

Secondary:

**You can start using Rasc now.**

Action:

`Continue`

## Unsupported hardware/system

Copy:

**Refine isn't available on this Mac.**

Secondary:

**Capture, search, and history still work normally.**

Action:

`Continue`

Do not display raw framework error types.

---

# 18. Refine animation

When `⌘J` begins:

1. editor stays stable;
2. small Shaping Orb appears;
3. label:

   `refining…`

4. no content streaming;
5. no spinner;
6. no fake progress.

Approximate orb size:

`18–22pt`

The user must still be able to cancel using existing semantics.

---

# 19. Refine result

Use the real Refine Preview implementation.

The preview should feel spatially connected to the editor.

Preferred motion:

- container expansion or matched geometry;
- content transition;
- restrained material appearance.

Avoid:
- modal pop;
- full-screen overlay;
- hard scene cut.

Existing controls remain:

`Esc Cancel`

`↵ Accept`

---

# 20. Accept animation

When the user presses Enter:

1. preview collapses into editor;
2. refined text settles into final layout;
3. Shaping Orb settles/dissolves if still visible;
4. optional temporary status:

   `Refined on this Mac`

Duration:
`≤ 1.5s`

The status must not remain as permanent chrome.

---

# 21. noChange

If Refine returns noChange:

Do not make onboarding look broken.

Show:

**Already useful.**

Optional subtle check state.

Then:

**Press Esc when you're done.**

Treat noChange as a valid Refine experience.

---

# 22. Refine failure

If Refine fails:

Show the normal product error message.

Below it, onboarding may add:

**You can keep using Rasc without Refine.**

Action:

`Continue`

Do not force retry.

Do not block onboarding.

---

# 23. Escape teaching

After meaningful typing and/or Refine:

Display:

`Esc  Hide Rasc`

The user should physically press Escape.

On Escape:

1. production panel hides through its normal code path;
2. onboarding completion window becomes visible;
3. previous-app focus behavior should remain identical to normal Rasc behavior.

This is an important product test.

---

# 24. Screen 3 — Ready

## Purpose

Conclude with confidence and optionally enable Launch at Login.

## Layout

```text
You're ready.

Rasc is always one shortcut away.

        ⌥ Space


Keep Rasc ready after login

[ Enable at Login ]


[ Finish ]
```

Supporting text:

**Recommended if you want Rasc available whenever you need it.**

Do not imply Launch at Login is necessary.

---

# 25. Launch at Login

Use the production `SMAppService` flow.

Do not create a fake preference.

The UI must reflect the real resulting state.

States:

- off;
- requesting/transitioning;
- enabled;
- system rejected/error.

If the system requires external approval, explain concisely.

Never block Finish.

---

# 26. Completion

When user selects Finish:

1. set `onboardingCompleted = true`;
2. clear transient onboarding state;
3. preserve the note created during onboarding;
4. close onboarding surface;
5. leave Rasc running normally in menu bar.

Do not automatically reopen the scratchpad.

The last impression should be calm.

---

# 27. First-run after completion

Normal launches must never show onboarding again unless explicitly requested.

Provide a future entry point:

`Help → Quick Tour`

or:

`Command Palette → Quick Tour`

This can reuse onboarding presentation, but must not reset user settings or create forced tutorial notes.

---

# 28. Contextual discovery after onboarding

Do not front-load advanced shortcuts.

## History hint

After the user has accumulated enough notes to make History meaningful, optionally show once:

```text
Need something from earlier?

⌘P  Find notes
```

Trigger only after a reasonable condition, for example:

- at least 3 saved notes;
- user has reopened Rasc multiple times.

Do not use arbitrary elapsed-time timers.

## Command Palette

No proactive onboarding required.

## New Scratch

Discover naturally or through Command Palette/menu.

---

# 29. Visual rules

The onboarding may be more expressive than the normal app.

Still enforce:

- one focal animation per stage;
- generous whitespace;
- primary content centered;
- no card grids;
- no gradient background;
- no feature carousel.

App visual hierarchy must remain recognizable.

---

# 30. Background

Prefer:

- system-adaptive neutral surface;
- optional extremely subtle grain/dither texture.

Do not place animated shaders behind text.

If grain exists, it must be almost subliminal.

---

# 31. Shaping Orb

The orb appears in only two onboarding contexts:

1. Welcome, extremely subtle ambient state;
2. actual Refine processing.

Do not leave it floating on every screen.

This prevents the orb becoming a generic AI mascot.

---

# 32. Gooey usage

At most one meaningful implementation:

shortcut key configuration.

Even there, fallback to normal matched geometry if the effect reduces legibility or native feel.

Gooey is optional.

Onboarding correctness must not depend on it.

---

# 33. Metal usage

Metal should generally not appear inside the native onboarding.

If used:

- tiny accent only;
- never the primary material.

Prefer native macOS material in the application.

Reserve richer Metal treatment for the website.

---

# 34. Accessibility

## Keyboard

The entire onboarding must be completable without mouse input.

Expected keyboard flow:

```text
Return
→ shortcut interaction
→ Return
→ global shortcut
→ type
→ ⌘J
→ Return or Esc
→ Esc
→ optional Launch at Login
→ Return
```

## VoiceOver

Every:

- CTA;
- shortcut recorder;
- Refine status;
- availability state;
- Launch at Login control

needs meaningful labels.

Do not announce decorative motion.

## Reduce Motion

When enabled:

- shortcut → panel morph becomes quick opacity transition;
- eliminate ambient orb breathing;
- preserve processing state using static/subtle orb + text;
- remove unnecessary scale movement.

## Reduce Transparency

All glass surfaces must remain legible with transparency reduction enabled.

---

# 35. Focus management

Focus correctness is P0.

On every stage change, explicitly define the expected focus target.

## Welcome

Primary CTA.

## Shortcut

Shortcut recorder or Continue based on interaction.

## Capture Practice

Editor cursor.

## Refine Preview

Existing preview behavior.

## Completion

Finish button, unless Launch at Login interaction owns focus.

Never leave keyboard focus in the hidden onboarding window while scratchpad is active.

---

# 36. Multiple displays

First onboarding window:

- center on screen containing active/frontmost app.

Live scratchpad:

- use normal Rasc placement logic.

When returning to completion:

- reopen onboarding on the display where the guided interaction occurred if feasible;
- otherwise use active screen.

Do not add separate onboarding-only monitor logic unless necessary.

---

# 37. Spaces and fullscreen

The live practice must exercise production behavior.

If user triggers the shortcut while another app is fullscreen, Rasc should behave exactly as normal.

Do not disable fullscreen behavior during onboarding.

This doubles as a real-world validation path.

---

# 38. Existing user migration

When onboarding is introduced after users already have Rasc installed:

Do not automatically force the full onboarding on every existing user.

Use a migration rule.

Recommended:

If the app already contains:

- saved notes;
- active user configuration;
- evidence of prior normal usage,

mark full first-run onboarding as skipped/completed.

Optionally surface:

`What's new → Quick Tour`

Never interrupt established users with a mandatory onboarding wizard.

---

# 39. Beta reset

For development/testing only, provide a safe reset mechanism.

Preferred:

launch argument or Debug-only menu item.

Example:

```text
-resetOnboarding
```

Do not expose destructive user-data reset.

Resetting onboarding must not delete notes or settings unless explicitly required for a test.

---

# 40. Analytics

Current Rasc philosophy does not require telemetry.

Do not add analytics solely for onboarding.

For beta evaluation, rely on:

- direct tester feedback;
- observed friction;
- bug reports.

If analytics are introduced later, that requires a separate privacy/product decision.

---

# 41. Performance requirements

Onboarding must not regress production startup.

The onboarding window can initialize independently, but:

- shortcut registration must happen promptly;
- no shader should delay launch;
- no Foundation Models session should be created before Refine is actually invoked;
- decorative assets must be lightweight.

The live scratchpad must retain normal latency.

---

# 42. Error hierarchy

Onboarding-specific failures must never mask product failures.

Priority:

1. preserve note content;
2. preserve keyboard interaction;
3. allow user to continue;
4. explain issue briefly.

Do not terminate onboarding because:

- Refine unavailable;
- Launch at Login fails;
- animation fails;
- material fallback is unavailable.

---

# 43. Acceptance criteria

The implementation is complete only if all of the following hold.

## First launch

- onboarding appears once for a genuinely new installation/profile;
- Welcome renders correctly in light/dark mode;
- Get started works by keyboard.

## Shortcut

- default shortcut is correctly displayed;
- user can change it;
- setting persists;
- actual global shortcut drives practice.

## Live capture

- real Rasc panel appears;
- editor receives immediate keyboard focus;
- typed content uses normal persistence;
- no fake/tutorial note is inserted.

## Refine

- real Foundation Models provider used;
- available/unavailable states handled;
- noChange handled;
- failure does not block onboarding;
- accepted result uses normal revision/persistence behavior.

## Escape

- hides real panel;
- focus restoration remains correct;
- onboarding resumes.

## Completion

- Launch at Login uses real system service;
- Finish marks onboarding completed;
- onboarding does not reappear on normal relaunch.

## Existing users

- users with established Rasc data are not forced through first-run onboarding.

## Accessibility

- full keyboard completion works;
- VoiceOver labels present;
- Reduce Motion respected;
- Reduce Transparency usable.

## Regression

- normal scratchpad behavior unchanged;
- History unchanged;
- Search unchanged;
- Command Palette unchanged;
- Refine semantics unchanged;
- fullscreen behavior unchanged;
- note durability unchanged.

---

# 44. Tests

Add focused automated tests where meaningful.

At minimum:

### Onboarding state

- initial state;
- forward progression;
- persistence;
- resume;
- skip;
- completion.

### Migration

- new user sees onboarding;
- established user does not.

### Refine availability

- available;
- disabled;
- preparing;
- unsupported;
- error.

### Launch at Login

Use existing abstractions rather than talking directly to system service in unit tests.

### Note safety

- onboarding note persists;
- skipping does not create note;
- onboarding reset does not delete notes.

### State isolation

- onboarding state cannot accidentally become ScratchpadSession state;
- hidden onboarding cannot steal focus from real scratchpad.

---

# 45. Manual validation matrix

Test on:

- light mode;
- dark mode;
- Reduce Motion;
- Reduce Transparency;
- Apple Intelligence enabled;
- Apple Intelligence disabled;
- fresh user state;
- existing user state;
- external display if available;
- another app fullscreen;
- cold app launch;
- relaunch after interrupted onboarding.

---

# 46. Implementation boundaries

Do not:

- redesign ScratchpadView;
- redesign Refine semantics;
- introduce backend;
- add account state;
- add telemetry;
- add payment;
- add Sparkle;
- add new note fields;
- expand command system;
- change persistence model.

This milestone is strictly first-run experience.

---

# 47. Implementation order

Recommended sequence:

### Phase 1
State model + persistence + existing-user migration.

### Phase 2
Welcome + Shortcut screens.

### Phase 3
handoff from onboarding window to real scratchpad.

### Phase 4
capture/refine contextual guidance.

### Phase 5
completion + Launch at Login.

### Phase 6
motion polish.

### Phase 7
accessibility + edge-case validation.

Do not start with animation polish.

Interaction correctness comes first.

---

# 48. Design invariant

The onboarding should not feel like something the user completes before reaching Rasc.

It should feel like:

> **the first time they use Rasc.**

---

# 49. Implementation notes (M7)

This section documents intentional differences between the specification above and the M7 implementation.

## Default shortcut display

**Original requirement:** examples use `⌥ Space` as the default shortcut.

**Implemented behavior:** onboarding displays the production `KeyboardShortcuts` value for `.toggleScratchpad`. The app default is currently `⌥ \` (migrated from `⌥ Space` via `GlobalShortcutMigration`). The recorder and displayed shortcut always reflect the real configured value.

## Existing-user migration signals

**Original requirement:** saved notes, active configuration, evidence of prior usage.

**Implemented behavior:** migration auto-completes onboarding when any of the following is true on first launch with onboarding enabled:

- at least one saved note in SQLite;
- `ActiveNoteStore.hasEstablishedState`;
- a persisted scratchpad window frame in `WindowFrameStore`.

Notes, shortcuts, Launch at Login, and window placement are never modified by migration.

## Activation without Refine

**Original requirement:** Refine encouraged but must not block activation.

**Implemented behavior:** live practice completes after the user enters meaningful content (≥ 3 non-whitespace characters) and hides the production panel. Refine attempt is encouraged via `⌘J` guidance but is not required to reach the completion screen.

## Contextual History hint

**Original requirement:** optional post-onboarding History hint.

**Implemented behavior:** deferred in M7. No proactive `⌘P` discovery UI was added.

## Debug reset

**Implemented behavior:**

- launch argument: `-resetOnboarding`
- Debug menu bar item: `Reset Onboarding`

Both reset only onboarding `UserDefaults` keys. They do not delete notes, shortcuts, window frames, or Launch at Login state.
# M8 Core Surface Visual Refinement Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Polish the scratchpad, refinement surfaces, and targeted onboarding compositions into one quiet, premium native Mac visual system without changing product behavior.

**Architecture:** Keep the existing `ScratchpadSession`, onboarding coordinator, persistence, shortcuts, and panel behavior untouched. Centralize only small visual metrics and adaptive colors in the existing UI style file, then compose those styles around the existing editor and transient states. Preserve every existing action, keyboard shortcut, accessibility label, and transition trigger.

**Tech Stack:** Swift 6, SwiftUI, AppKit, Swift Testing, Xcode 26.

---

### Task 1: Lock the surface-system invariants

**Files:**
- Modify: `RascTests/OnboardingBehaviorTests.swift`
- Modify: `Rasc/UI/TransientSurfaceStyle.swift`

1. Add a focused test that requires the placeholder origin to derive from the editor padding, requires a larger continuous preview radius than the compact feedback radius, and fixes the official inline orb size at 20 points.
2. Run `xcodebuild test -project Rasc.xcodeproj -scheme Rasc -destination 'platform=macOS' -only-testing:RascTests/OnboardingBehaviorTests` and confirm the test fails because the new visual metrics do not exist.
3. Add the minimal internal visual-metrics namespace and adaptive warm-light/graphite-dark palette in `TransientSurfaceStyle.swift`.
4. Re-run the focused test and confirm it passes.

### Task 2: Unify the scratchpad shell and writing surface

**Files:**
- Modify: `Rasc/Features/Scratchpad/ScratchpadView.swift`
- Modify: `Rasc/UI/TransientSurfaceStyle.swift`
- Modify: `Rasc/Platform/PanelController.swift`

1. Place all scratchpad states on the same adaptive solid canvas and hide the native `TextEditor` scroll background.
2. Use system editorial typography for note content and consistent editor insets in both macOS 15 selection-aware and fallback editors.
3. Add a non-interactive top-leading placeholder aligned to the text insertion origin and shown only for an empty editor.
4. Give the panel background the same adaptive AppKit color so titlebar and hosted content read as one object.
5. Build the app target to catch availability, material, and AppKit/SwiftUI integration errors.

### Task 3: Polish refining, preview, and inline feedback

**Files:**
- Modify: `Rasc/Features/Scratchpad/ScratchpadView.swift`
- Modify: `Rasc/UI/RascOrb.swift`
- Modify: `Rasc/UI/TransientSurfaceStyle.swift`

1. Keep `RascOrb(state: .shaping, size: .inline)` unchanged semantically and compose the 20-point orb with “refining…” in a quiet micro-surface.
2. Restyle the preview as a continuation of the note: editorial body type, restrained inset material, clearer header rhythm, a quiet footer separator, and keyboard-first action labels.
3. Restyle `.alreadyUseful` as a compact confirmation surface while retaining the existing two-second message lifecycle and accessibility label.
4. Run the refinement/session tests to verify no state, acceptance, cancellation, or no-change behavior regressed.

### Task 4: Separate onboarding guidance from the writing placeholder

**Files:**
- Modify: `Rasc/Features/Onboarding/OnboardingScratchpadOverlay.swift`
- Modify: `Rasc/Features/Onboarding/OnboardingView.swift`
- Modify: `Rasc/UI/ShortcutKeycapView.swift`

1. Replace the onboarding overlay’s duplicate writing placeholder with a clearly separate bottom contextual hint, leaving its timing and gating unchanged.
2. Improve Shortcut hierarchy using a restrained shortcut presentation surface and cleaner title/subtitle rhythm.
3. Improve “Try it” density with a short instructional line and balanced shortcut composition, without adding a stage or action.
4. Soften keycap fill, border, highlight, and shadow consistently in both appearances while preserving press/hover interaction.
5. Run onboarding behavior and eligibility/store tests.

### Task 5: Verify the complete milestone

**Files:**
- Review all modified files and `git diff`.

1. Run the full suite with `xcodebuild test -project Rasc.xcodeproj -scheme Rasc -destination 'platform=macOS'`.
2. Run a clean app build with `xcodebuild build -project Rasc.xcodeproj -scheme Rasc -destination 'platform=macOS'`.
3. Inspect warnings and confirm there are no test failures or build errors.
4. Record manual checks still required: light/dark appearance, reduced transparency/motion, placeholder baseline and disappearance, refine processing/preview/no-change, resizing, and live onboarding composition.
5. Do not commit or push; repository instructions require an explicit request for those actions.

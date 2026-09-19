# M9A Scratchpad Identity Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Give the production scratchpad a distinctive single-surface Rasc identity with a persistent semantic orb, refined mono typography, violet state language, and preserved native panel behavior.

**Architecture:** Keep the existing `NSPanel`, session, persistence, and Refine lifecycle intact. Add a presentation-only orb activity model and resolve its semantic state from the existing scratchpad surface, then compose editor, preview, and transient feedback around one shared top anchor and canvas.

**Tech Stack:** Swift 6, SwiftUI, AppKit, Observation, ThinkingOrbsKit, Swift Testing

---

### Task 1: Protect native panel behavior while hiding traffic lights

**Files:**
- Modify: `RascTests/PanelControllerTests.swift`
- Modify: `Rasc/Platform/PanelController.swift`

1. Add a failing test asserting that the production panel retains its titled/resizable/full-size/nonactivating masks while all standard traffic-light buttons are hidden.
2. Run the focused panel tests and confirm the new assertion fails.
3. Hide the close, miniaturize, and zoom buttons without changing the style mask.
4. Re-run the focused panel tests and confirm they pass.

### Task 2: Add the Rasc-owned semantic orb model

**Files:**
- Modify: `RascTests/OverlayStateTests.swift`
- Modify: `Rasc/UI/RascOrb.swift`

1. Add failing tests for semantic states, priority resolution, ThinkingOrbsKit mapping, tuning, and the 850 ms typing-idle debounce.
2. Run the focused state tests and confirm they fail because the presentation model is absent.
3. Implement `RascOrbState` and `ScratchpadOrbPresentation` without exposing ThinkingOrbsKit state names outside `RascOrb`.
4. Re-run the focused tests and confirm they pass.

### Task 3: Integrate the single-surface scratchpad presentation

**Files:**
- Modify: `Rasc/Features/Scratchpad/ScratchpadView.swift`
- Modify: `Rasc/UI/TransientSurfaceStyle.swift`
- Modify: `Rasc/UI/RascMotion.swift`
- Modify: `Rasc/Features/Search/HistorySearchView.swift`
- Modify: `Rasc/Features/Commands/CommandPaletteView.swift`

1. Reserve the shared top anchor area and update note/placeholder/preview typography to the same 16 pt system mono treatment.
2. Move Refine progress, `Already useful`, and preview state into the single persistent anchor; remove the bottom orb and nested preview card.
3. Add adaptive violet canvas/border/state tokens while retaining a separate orange action accent.
4. Add a restrained key-window violet stroke and Reduce Motion-aware 140 ms orb / 200 ms surface transitions.
5. Build to catch SwiftUI integration errors.

### Task 4: Verify the milestone without changing behavior

**Files:**
- Review: all modified files

1. Run the complete test suite.
2. Run a clean app build.
3. Inspect the final diff for persistence, lifecycle, shortcut, Spaces/fullscreen, onboarding, search/history, or provider changes.
4. Report automated evidence and explicitly call out that Spaces/fullscreen/multi-monitor behavior still requires manual macOS verification.

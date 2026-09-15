# M3B Local Refine Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:test-driven-development while implementing each behavior and superpowers:verification-before-completion before reporting completion.

**Goal:** Deliver the first usable, reversible Refine flow using only Apple's on-device Foundation Models framework.

**Architecture:** Extend the existing `ScratchpadSession` into a small mutually exclusive surface state machine that coordinates immutable requests, provider execution, stale-result rejection, preview, cancellation, and acceptance. Keep Foundation Models behind `RefinementProvider`, instantiate one ephemeral `LanguageModelSession` per request, and commit an accepted note mutation plus its local revision in one GRDB transaction.

**Tech Stack:** Swift 6, SwiftUI, AppKit, Foundation Models on macOS 26+, GRDB, Swift Testing, Xcode 26 SDK.

---

### Task 1: Lock down the domain/provider contract

**Files:**
- Modify: `Rasc/Domain/Refinement.swift`
- Modify: `Rasc/AI/RefinementProvider.swift`
- Modify: `RascTests/RefinementContractTests.swift`

**Steps:**

1. Add failing tests for provider availability categories, versioned provider metadata, preview identity, and result validation.
2. Run the focused contract suite and confirm failures are caused by the missing M3B types.
3. Add the minimal availability/error/metadata/preview types and extend `RefinementProvider` with dynamic availability.
4. Re-run the contract suite and keep the existing M3A snapshot tests green.

### Task 2: Add atomic accepted-revision persistence

**Files:**
- Create: `Rasc/Domain/RefinementRevision.swift`
- Modify: `Rasc/Data/NoteRepository.swift`
- Modify: `RascTests/NoteRepositoryTests.swift`
- Modify: `Rasc.xcodeproj/project.pbxproj`

**Steps:**

1. Add failing tests proving an accepted mutation updates the note and inserts exactly one complete `refinement_revisions` row.
2. Add tests proving a stale `before_content` or no-op does not update the note or insert a revision.
3. Run the repository suite and verify the new tests fail for missing APIs.
4. Implement a single GRDB write transaction guarded by current note content.
5. Re-run the repository suite.

### Task 3: Implement deterministic Refine coordination

**Files:**
- Create: `RascTests/RefinementSessionTests.swift`
- Modify: `Rasc/Features/Scratchpad/ScratchpadView.swift`
- Modify: `Rasc.xcodeproj/project.pbxproj`

**Steps:**

1. Build a controllable fake `RefinementProvider` whose suspended requests can complete after cancellation.
2. Add failing tests for request creation, full-note and selection snapshots, changed preview, no-change, accept, cancel, stale revision, stale request ID, edits while running, note switch, Unicode selection replacement, persistence timing, provider failure, unavailability, and late cancelled results.
3. Run the focused session suite and confirm it fails because the coordinator does not exist.
4. Implement one active-request task, immutable snapshots, cancellation/invalidation hooks, stale guards, preview state, and atomic acceptance.
5. Re-run the session suite and the existing Scratchpad session suite.

### Task 4: Add the Foundation Models provider and refine-v1 prompt

**Files:**
- Create: `Rasc/AI/RefinementPrompt.swift`
- Create: `Rasc/AI/FoundationModelsRefinementProvider.swift`
- Create: `RascTests/FoundationModelsProviderContractTests.swift`
- Modify: `Rasc.xcodeproj/project.pbxproj`

**Steps:**

1. Add failing tests for the exact `refine-v1` prompt contract and prompt/content separation.
2. Implement a macOS-26-gated provider using `SystemLanguageModel.default`, dynamic `availability`, a fresh `LanguageModelSession`, `@Generable`, `@Guide(.anyOf)`, and one non-streaming guided `respond` call.
3. Map unavailable reasons and context-window errors into provider-neutral domain errors.
4. Validate empty/unknown structured output before returning it.
5. Run provider contract tests and build for the macOS 14 deployment target.

### Task 5: Wire the keyboard-first UI

**Files:**
- Modify: `Rasc/Features/Scratchpad/ScratchpadView.swift`
- Modify: `Rasc/Platform/PanelController.swift`
- Modify: `Rasc/App/AppDelegate.swift`
- Modify: `Rasc/App/RascApp.swift`

**Steps:**

1. Add `TextSelection` capture on macOS 15+ with a macOS 14 full-note fallback.
2. Add the `Command-J` app command and route it to the session.
3. Render editor, subtle refining footer, read-only preview, and transient message as mutually exclusive states.
4. Route Escape by priority and Enter to preview acceptance.
5. Cancel active Refine work on note changes, new note, search transition, and panel hide/close.

### Task 6: Document and verify M3B

**Files:**
- Create: `docs/M3B-FOUNDATION-MODELS.md`

**Steps:**

1. Document the exact Foundation Models APIs, full `refine-v1` instructions, session isolation, stale-result checks, atomic acceptance, and remaining manual tests.
2. Run all tests with `xcodebuild test`.
3. Run `xcodebuild build` against the supported macOS SDK.
4. Run `git diff --check` and inspect the complete diff for scope and privacy regressions.

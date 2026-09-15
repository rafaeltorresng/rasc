# Selection Refine Safety Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Prevent selection Refine from treating a local fragment as a whole note or accepting runaway replacements.

**Architecture:** Add an explicit `RefinementScope` derived from the immutable snapshot. Preserve `inputText` as the only transformable text, but construct a selection-only JSON prompt that carries the full note as read-only surrounding context. Reject disproportionate changed selection output in the coordinator before preview; whole-note behavior continues unchanged.

**Tech Stack:** Swift 6, SwiftUI, Foundation Models, Swift Testing.

---

### Task 1: Capture the selection contract in domain and prompt tests

**Files:**
- Modify: `RascTests/RefinementContractTests.swift`
- Modify: `RascTests/FoundationModelsProviderContractTests.swift`
- Modify: `RascTests/Fixtures/RefinementEvals.v1.json`

1. Write failing tests for `wholeNote` versus `selection`, preserving a full snapshot while exposing only selected input.
2. Write a failing prompt test proving selection payloads include read-only full-note context and an editable fragment, while whole-note prompt output remains unchanged.
3. Add the supplied Portuguese regression and five additional selection eval cases with scope/context expectations.
4. Run focused contract/provider suites and verify failures are due to missing scope/prompt APIs.

### Task 2: Introduce explicit scope and selection prompt contract

**Files:**
- Modify: `Rasc/Domain/Refinement.swift`
- Modify: `Rasc/AI/RefinementPrompt.swift`
- Modify: `Rasc/AI/FoundationModelsRefinementProvider.swift`

1. Add `RefinementScope` and derive it from immutable selection state.
2. Keep `inputText` equal to the selected fragment for selection scope; keep the complete snapshot text available as context.
3. Add selection-only instructions that prohibit continuing surrounding text, expansion, invented facts, greetings, explanations, and new ideas.
4. JSON-encode all note-derived data in the response prompt, retaining it outside session instructions.
5. Use scope-aware prompt construction in the provider without changing whole-note prompt behavior.
6. Re-run focused tests.

### Task 3: Reject selection runaway output before preview

**Files:**
- Modify: `Rasc/Domain/Refinement.swift`
- Modify: `Rasc/Features/Scratchpad/ScratchpadView.swift`
- Modify: `RascTests/RefinementSessionTests.swift`

1. Add a failing deterministic session test returning a long unrelated paragraph for a short selected fragment.
2. Implement a generous selection-only character-count threshold and map rejected output to the existing non-destructive error state.
3. Add a control test proving equally long whole-note output is not filtered by that guard.
4. Re-run session tests.

### Task 4: Document and verify

**Files:**
- Modify: `docs/M3B-FOUNDATION-MODELS.md`

1. Document scope-specific context, the selection instructions, and the expansion guard.
2. Run `xcodebuild test`.
3. Run `xcodebuild build`.
4. Run `git diff HEAD --check`.

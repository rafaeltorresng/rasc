# M12B-005B Exact Protected Literals Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add one deterministic post-generation validator that rejects changed Refine proposals when an exact high-confidence literal from the relevant input scope is missing or changed.

**Architecture:** A focused production-owned validator extracts only URLs, emails, handles, technical identifiers, code-like/quoted/opaque literals, and standalone integers. `ScratchpadSession` and the evaluation runner apply it exactly once after the provider returns; invalid proposals become the existing `noChange` result with content-free diagnostic tracing. Foundation Models generation, language validation, M12B-004C preflight, selection boundaries, prompts, and UI remain unchanged.

**Tech Stack:** Swift 6, Foundation regular expressions, Swift Testing, existing Refine evaluation CLI/artifacts, Python analysis tooling.

---

### Task 1: Freeze the exact-literal contract in tests

**Files:**
- Modify: `RascTests/RefinementContractTests.swift`
- Modify: `RascTests/RefinementSessionTests.swift`

**Steps:**
1. Add table-driven extraction/validation tests for every included and excluded class.
2. Add selection-boundary and multiple-token tests.
3. Add a session test proving an unsafe result becomes existing `alreadyUseful`/`noChange` behavior after exactly one provider request.
4. Run the focused tests and verify they fail because the validator does not exist.

### Task 2: Implement the smallest production validator

**Files:**
- Create: `Rasc/AI/RefineProtectedLiteralValidator.swift`
- Modify: `Rasc/Domain/Refinement.swift`
- Modify: `Rasc/Features/Scratchpad/ScratchpadView.swift`
- Modify: `Rasc.xcodeproj/project.pbxproj`

**Steps:**
1. Add exact protected-literal classes, content-free violation diagnostics, and deterministic extraction with precedence/overlap suppression.
2. Exclude money, dates, times, percentages, decimals, and formatted numbers before integer extraction.
3. Apply the validator only to `.changed` provider results using `request.inputText`, which is already selection-local.
4. Return the existing `.noChange/.alreadyGood` result and retain a diagnostic trace without token contents.
5. Run the focused tests and verify green.

### Task 3: Preserve evaluation visibility

**Files:**
- Modify: `Rasc/Eval/RefineReliability/RefineEvalModels.swift`
- Modify: `Rasc/Eval/RefineReliability/RefineEvalRunner.swift`
- Modify: `Rasc/Eval/RefineReliability/RefineEvalReport.swift`
- Modify: `RascTests/RefineReliabilityTests.swift`

**Steps:**
1. Add optional protected-literal diagnostics to run records.
2. Apply the same production validator after the provider in the runner.
3. Record raw proposal failure separately from final user-visible safety without treating safe rejection as an objective failure.
4. Add/report `userVisibleProtectedLiteralCorruptionCount` and per-class rejection metrics.
5. Run focused evaluator tests.

### Task 4: Execute the isolated experiment

**Files:**
- Create: `Evals/Refine/experiments/M12B-005B-exact-protected-literals/**`
- Create: `Scripts/analyze-m12b-005b-exact-protected-literals.py`

**Steps:**
1. Run full dev, validation, permanent regression, and critical stability ×5 using the accepted prompt/options.
2. Do not run or inspect holdout.
3. Compare with accepted M12B-004C and report every M12B-005A predicted in-scope case.
4. Separate out-of-scope money/time/date/percentage/decimal findings.
5. Generate `experiment.md`, `report.md`, `analysis.json`, `production-diff.md`, and `token-policy.md`.

### Task 5: Verify and decide

**Files:**
- Verify all changed files and artifacts.

**Steps:**
1. Run focused validator/session/evaluator tests.
2. Run the complete project test suite and Debug build.
3. Verify M12B-004C zero-provider-call behavior and selection tests.
4. Audit the diff for forbidden changes and holdout access.
5. Apply acceptance criteria, record ACCEPT/REJECT, recommend exactly one next experiment, and stop.

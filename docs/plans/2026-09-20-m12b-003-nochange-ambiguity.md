# M12B-003 noChange & Ambiguity Calibration Implementation Plan

**Status:** Completed 2026-09-20. Experiment decision: **REJECT**. Accepted M12B-001 prompt restored; evaluation instrumentation and isolated experiment artifacts retained.

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Run one isolated prompt-semantics experiment that calibrates Refine toward safe `noChange` on ambiguous or already-useful text while measuring over-abstention and retained utility.

**Architecture:** Keep the accepted M12B-001 provider, language resolver, language validator, generation options, and production guards unchanged. Change only `RefinementPrompt` instructions/version, then extend the DEBUG-only reliability report with token-length decision metrics and over-abstention metrics derived from existing corpus expectations. Run dev, validation, regression, and critical stability ×5 without holdout, compare primarily to M12B-001 and secondarily to baseline-v2, and record the decision in a new experiment directory.

**Tech Stack:** Swift 6, Foundation Models guided generation, Swift Testing, existing Refine reliability runner, shell experiment orchestration, JSON/Markdown reports.

---

### Task 1: Lock the M12B-003 prompt contract with failing tests

**Files:**
- Modify: `RascTests/FoundationModelsProviderContractTests.swift`

**Steps:**

1. Update the expected prompt version to `refine-v3-nochange-ambiguity`.
2. Add exact assertions for the conservative decision boundary, abstention triggers, functional-grammar distinction, and a small multilingual example set.
3. Assert that the M12B-001 language contract remains appended unchanged.
4. Run the focused contract tests and verify they fail only because the prompt/version has not changed yet.

### Task 2: Implement the smallest coherent prompt change

**Files:**
- Modify: `Rasc/AI/RefinementPrompt.swift`

**Steps:**

1. Change only the prompt version and base instruction text.
2. State that invoking Refine does not imply a rewrite and that `noChange` is successful.
3. Add the four abstention boundaries and two positive functional-cleanup examples, keeping Portuguese examples in Portuguese and technical fragments untranslated.
4. Preserve selection instructions and every M12B-001 resolved-language contract branch unchanged.
5. Run the focused contract tests and verify green.

### Task 3: Specify evaluation metrics test-first

**Files:**
- Modify: `RascTests/RefineReliabilityTests.swift`
- Modify: `Rasc/Eval/RefineReliability/RefineEvalModels.swift`
- Modify: `Rasc/Eval/RefineReliability/RefineEvalReport.swift`

**Steps:**

1. Add failing tests that require token-count buckets `1`, `2-3`, `4-8`, and `9+`.
2. Add failing report tests for changed/noChange counts, appropriate noChange, useful changed, harmful-edit indicators, and over-abstention.
3. Define over-abstention eligibility only when `preferredAction` is cleanup/structure or `allowedActions` excludes noChange while allowing cleanup/structure.
4. Ensure cases allowing both noChange and change are not counted as over-abstention.
5. Add per-bucket stability/action-flapping counts and an explicit `noChangeChangedFlapping` alias in stability decomposition.
6. Run focused reliability tests and verify the intended failures.

### Task 4: Implement evaluation-only decision calibration reporting

**Files:**
- Modify: `Rasc/Eval/RefineReliability/RefineEvalModels.swift`
- Modify: `Rasc/Eval/RefineReliability/RefineEvalReport.swift`

**Steps:**

1. Change `inputLengthBucket` from character count to whitespace-token count with the four required buckets.
2. Add optional aggregate decision metrics so historical M12B-001/baseline summaries remain decodable.
3. Compute overall, tiny/ambiguous, already-good, telegraphic, structural/list, and per-length metrics from existing cases/scores/records.
4. Report changed, noChange, objective pass, deterministic harmful edit, excessive expansion, invented-information indicator, wrong-language changed output, appropriate noChange, useful changed, and over-abstention.
5. Compute action and pass/fail flapping per bucket for repeated runs.
6. Render the new metrics in Markdown without changing corpus expectations.
7. Run focused and full tests.

### Task 5: Add isolated M12B-003 execution/log scaffolding

**Files:**
- Create: `Scripts/run-m12b-003-nochange-ambiguity.sh`
- Create: `Evals/Refine/experiments/M12B-003-nochange-ambiguity/experiment.md`

**Steps:**

1. Run full dev, validation, regression, and critical stability ×5 only.
2. Compare generated reports to canonical baseline-v2 during execution.
3. Preserve candidate reports in the new M12B-003 directory and never overwrite earlier experiments.
4. Record hypothesis, exact prompt diff, prompt version, unchanged generation options, corpus version, and comparison references before results.

### Task 6: Execute the experiment and analyze against M12B-001

**Files:**
- Generate: `Evals/Refine/experiments/M12B-003-nochange-ambiguity/reports/{dev,validation,regression,stability}/...`
- Modify: `Evals/Refine/experiments/M12B-003-nochange-ambiguity/experiment.md`

**Steps:**

1. Run the four required candidate evaluations; do not run holdout.
2. Compare candidate bundles directly to M12B-001 run-zero results and to canonical baseline-v2.
3. Analyze frontier adjudications only as a secondary lens without modifying corpus or maintainer artifacts.
4. Report the 17 previously failed tiny changed cases and 3 changed already-good cases individually in aggregate.
5. Record objective, safety, utility, language, length, stability, latency, and regression results.
6. Make one ACCEPT/REJECT decision from the stated criteria.
7. Recommend one next experiment without implementing it.

### Task 7: Verify scope and artifacts

**Files:**
- Verify all files above.

**Steps:**

1. Run focused prompt/reliability tests, then the full relevant test suite and Debug build.
2. Validate all generated JSON and report counts.
3. Confirm prompt is the only production behavior change.
4. Confirm resolver, validator, policy, provider generation options, guards, corpus, adjudications, and holdout were not modified or run.
5. Inspect the final diff and report exact evidence; do not commit.

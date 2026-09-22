# M12B-002.5 — Human Adjudication & Evaluation Ground Truth

**Status:** instrumentation only (no production Refine behavior change)  
**Production candidate:** M12B-001 (`refine-v2-language`)  
**Scope:** maintainer review workflow, adjudication artifacts, decomposed language metrics, safety metric

## Goal

Before further optimization, give maintainers a local workflow to adjudicate cases where production resolver, production validator, independent evaluator, and corpus expectations disagree.

## Deliverables

### Review tool

- `Scripts/refine-review.sh` — builds Debug app, optionally regenerates queue, launches localhost review UI
- `Scripts/refine-review-server.py` — static HTML + JSON API on `127.0.0.1` (no external networking)
- Two-stage blind review UI reduces anchoring bias:
  - **Stage 1 (blind):** input, selection/context, final output, changed/noChange only
  - **Stage 2:** benchmark expectations, diagnostics, queue sources
- Adjudications append to `Evals/Refine/adjudications.v2.jsonl` (schema v2; `adjudications.v1.jsonl` preserved for compatibility)
- Priority queue review order is a deterministic stable shuffle (membership unchanged)

### Corpus correction workflow

- Maintainer marks `benchmarkExpectationWrong` or `needsConstraintEdit` with optional `constraintCorrection`
- `Scripts/refine-adjudicate-apply.sh` runs `--refine-review-apply-adjudications`
- Accepted corrections write `corpus.v2.jsonl` + `corpus.v2.changelog.json`

### Priority queue

- Generated to `Evals/Refine/priority-queue.v1.json`
- Sources: M12B-001 dev language drift, validator false negatives, evaluator disagreements, M12B-001 dev regressions (when baseline artifact present), permanent regression set, tiny/mixed from 75-case queue
- Holdout excluded by default (`--include-holdout` to override)

### Metrics

Decomposed language axes in eval reports:

1. `inputLanguageResolution`
2. `rawGenerationLanguageCorrect`
3. `languageValidatorOutcome`
4. `finalUserVisibleLanguageSafe`
5. `technicalTermPreservation`

Safety metric: `userVisibleHarmfulEditRate` (final changed outputs violating critical constraints). Model proposals rejected into `noChange` tracked separately as `modelProposalFailureRate`.

Evaluator disagreements and low-confidence drift set `requiresHumanReview` / `evaluatorDisagreement` without auto-fail.

## Commands

```bash
# Regenerate priority queue + open review UI
Scripts/refine-review.sh --generate-queue

# Review 75-case queue instead
Scripts/refine-review.sh --queue review-queue-75

# Status only
Scripts/refine-review.sh --status

# Apply accepted benchmark corrections
Scripts/refine-adjudicate-apply.sh
```

## Maintainer action required

### Adjudication schema v2

Product and benchmark judgments are stored independently:

- Product: `outputAcceptable`, `productFailure`, `languageAmbiguous`, `defer`
- Benchmark: `benchmarkCorrect`, `benchmarkExpectationWrong`, `needsConstraintEdit`, `deferBenchmarkReview`

Status per case: `productReviewed`, `benchmarkReviewed`, `fullyReviewed`, `deferred`, `productNotApplicable`.

Legacy v1 records are migrated on read (not overwritten).

Human adjudication has **not** been performed in this experiment. Review the priority queue and 75-case queue, then record decisions via the review UI.

# M12B-002 — Language Diagnostics & Hardening

| Field | Value |
|---|---|
| **Experiment ID** | M12B-002-language-diagnostics |
| **Baseline** | `baseline-*-v2` (canonical) |
| **Comparison** | Also vs `M12B-001-language-contract` |
| **Prompt version** | `refine-v2-language` (unchanged) |
| **GenerationOptions** | Default (unchanged) |
| **Production change** | Validator hardening only — marker-shift unauthorized-translation detection in `RefineLanguageValidator` |
| **Eval changes** | Independent `NLLanguageRecognizer` assessor, per-run `languageDiagnostics`, stability decomposition |
| **Decision** | **REJECT** validator hardening; **KEEP** diagnostics infrastructure |

## M12B-001 root-cause distribution (dev, retroactive)

From [`m12b-001-root-cause-table.md`](m12b-001-root-cause-table.md) (21 language-drift failures):

| Root cause | Count |
|---|---:|
| evaluator_disagreement | 11 |
| validator_false_negative | 9 |
| low_confidence_unclassifiable | 1 |

Dominant production gap: **validator false negatives** (unauthorized translation reached `changed` output).

## Independent evaluator design

- **Authoritative:** dataset `expectedLanguage` metadata.
- **Independent signal:** Apple `NLLanguageRecognizer` for text ≥12 chars (`RefineEvalIndependentLanguageAssessor`).
- **Secondary:** marker heuristic (`RefineEvalLanguageAnalyzer`) — reported as `markerLabel`; disagreements flagged `evaluatorDisagreement`.
- **Tiny/ambiguous:** `requiresReview` — not fabricated as high-confidence drift.
- **Production** continues using `RefineLanguageDetection` + `RefineLanguageValidator`; eval does **not** reuse production validator for scoring.

Per-run fixture diagnostics: `language-diagnostics.jsonl` (no private notes logged outside eval corpus).

## Stability metric clarification

Legacy `unstableCases` = **pass/fail flapping** only (objective pass differs across repetitions).

M12B-001 stability: pass/fail unstable **30** cases while pass rate improved — wording mixed “stability pass” with pass/fail instability.

M12B-002 decomposition (stability ×5):

| Axis | M12B-002 unstable cases |
|---|---:|
| Pass/fail | 31 |
| Action (changed vs noChange) | 26 |
| Language-output | 18 |
| Exact-output | (see summary) |
| Language-resolution | 0 |

Different correct wording across runs ≠ Portuguese/English flapping.

## Hypothesis (recorded before implementation)

> M12B-001 validator false negatives are caused by top-label `RefineLanguageDetection` missing marker-shift translations (e.g. `amanhã`→`tomorrow`). Adding input→output marker-shift detection in `RefineLanguageValidator` will catch unauthorized translation without prompt/resolver changes.

## Metrics

### Dev

| Metric | baseline-v2 | M12B-001 | M12B-002 |
|---|---:|---:|---:|
| Objective pass | 43.0% | 53.4% | 47.7% |
| Critical failures | 84 | 65 | 85 |
| p50 latency | 707 ms | 758 ms | 754 ms |
| Language drift cases (scored) | — | 21 | 47* |
| Generation language correct | — | — | 75.9% |
| User-visible language safe | — | — | 77.0% |
| Validator catches | — | — | 2 |
| Validator misses (visible) | — | — | 0 |
| Safety rejections (changed→noChange) | — | — | 4 |

\*M12B-002 uses stricter independent drift scorer; not directly comparable to M12B-001 drift count.

### vs M12B-001 (dev per-case)

- Improved: 24
- Regressed: 35

### Language-specific (M12B-002 dev diagnostics)

- PT→EN drift (scored): 39
- ES→EN drift (scored): 2
- Validator catches: 2
- Safety rejections: 4

## Remaining generation-incorrect case IDs (dev, M12B-002)

`already-good-001`, `already-good-006`, `already-good-010`, `emoji-003`, `es-003`, `es-010`, `factual-003`, `incomplete-008`, `legacy-casual-intentional-pt-001`, `long-pt-002`, `long-pt-005`, `medium-en-009`, `medium-pt-001`, `medium-pt-010`, `message-draft-001`, `numbers-005`, `selection-extra-001`, `selection-extra-007`, `short-en-003`, `short-pt-005`, … (46 total with `generationLanguageCorrect=false`)

Full list: `reports/dev/language-diagnostics.jsonl`

## Review queue

75-case review queue remains **maintainer-unapproved** — see `Evals/Refine/review-queue.md`.

## Rationale for REJECT

1. Validator hardening did not improve objective pass vs M12B-001 (53.4% → 47.7% dev).
2. Net per-case regression vs M12B-001 (35 regressions / 24 improvements on dev).
3. Independent evaluator shows **46** generation-incorrect dev cases — language not solved; validator catches remain low (2).
4. Stricter independent scoring increases measured drift vs M12B-001; cannot claim zero critical language drift.

**Keep:** diagnostics, independent assessor, stability decomposition, `RefinementLanguageTrace` for future experiments.

**Next:** address generation-contract violations (model ignoring locale instructions) or resolver failures — not bundled with evaluator changes.

**Post-decision:** production `RefineLanguageValidator` reverted to M12B-001 implementation; eval diagnostics retained.

## Reports

- `reports/dev/`, `validation/`, `regression/`, `stability/`
- `language-diagnostics.jsonl` per split
- `m12b-001-root-cause-table.md`

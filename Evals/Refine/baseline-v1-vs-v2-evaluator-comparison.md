# Baseline v1 → v2 Comparison

Baseline **v1** used the pre-correction language analyzer and corpus expectations.
Baseline **v2** is the canonical M12B comparison baseline with corrected PT/ES detection and corpus `mustPreserve` fixes.

Model behavior is unchanged (`refine-v1`). Metric deltas below therefore reflect evaluator/corpus corrections unless noted.

| Split | v1 objective pass | v2 objective pass | Δ | v1 critical failures | v2 critical failures | Δ |
|---|---:|---:|---:|---:|---:|---:|
| dev | 46.6% | 43.0% | -3.6% | 74 | 84 | +10 |
| validation | 35.1% | 43.9% | 8.8% | 26 | 25 | -1 |
| holdout | 45.8% | 36.1% | -9.7% | 20 | 29 | +9 |
| regression | — | — | — | — | — | — |
| stability | 33.4% | 38.0% | 4.6% | 175 | 169 | -6 |

## Evaluator-only corrections in v2

1. **PT/ES marker separation** in `RefineLanguageDetection` — Spanish markers (`quizás`, `mañana`, `hola`, `gracias`) were incorrectly counted as Portuguese in v1, inflating false language-drift and mislabeling ES inputs.
2. **Corpus `mustPreserve` fixes** — `es-003` now requires only `tal vez`; `es-009` requires only `quizás`, matching actual input tokens.
3. **Shared detection core** — eval and production now share `RefineLanguageDetection` for consistent labeling.

## Expected metric shifts (not model improvements)

- **Spanish subset pass rate** should rise when outputs were already Spanish but mis-scored.
- **Protected-token failures** on `es-003` / `es-009` should drop when outputs preserve the single required marker.
- **PT→EN and ES→EN drift counts** in summaries should better reflect true model translation, not analyzer contamination.
- **Overall objective pass** may move modestly; large swings on PT/ES language-drift without prompt changes indicate scoring fixes, not Refine behavior changes.

## Usage

- M12B experiments compare against **baseline-v2** only.
- Holdout (`baseline-holdout-v2`) is frozen and must not inform tuning.

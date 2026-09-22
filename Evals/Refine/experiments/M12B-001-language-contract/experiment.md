# M12B-001 — Language Contract

| Field | Value |
|---|---|
| **Experiment ID** | M12B-001-language-contract |
| **Baseline** | `baseline-*-v2` (corrected evaluator, production `refine-v1`) |
| **Prompt version** | `refine-v2-language` |
| **GenerationOptions** | Default Foundation Models session options (unchanged) |
| **Decision** | **ACCEPT** |

## Hypothesis

Portuguese and Spanish notes are translated to English under `refine-v1`. Explicit locale instructions plus post-generation language validation will preserve note language without other Refine changes.

## Exact production change (isolated)

1. `RefineLanguagePolicy` — `matchNote` (default) + `fixed(Locale)` infrastructure (no Settings UI).
2. `RefineLanguageResolver` — resolves target locale from note + selection context; ambiguous tiny notes fall back to `Locale.preferredLanguages` without post-validation enforcement.
3. `RefinementPrompt.instructions(for:resolvedLanguage:)` — explicit language contract block appended to existing v1 instructions.
4. `RefineLanguageValidator` — when resolution confidence is high, reject changed output that clearly violates contract → safe `noChange` (no second generative repair).

**Not changed:** tiny-input expansion guard, protected-token production guards, noChange prompt overhaul, custom instructions, settings picker, two-stage classifier.

## Metrics vs baseline-v2

| Split | Objective pass (base → cand) | Δ | Critical failures | Language drift failures | p50 latency Δ |
|---|---:|---:|---:|---:|---:|
| dev | 43.0% → 53.4% | +10.4pp | 84 → 65 | 34 → 21 | +51 ms |
| validation | 43.9% → 52.6% | +8.8pp | 25 → 20 | 9 → 4 | +25 ms |
| regression | 33.3% → 50.0% | +16.7pp | 4 → 3 | 3 → 1 | +17 ms |
| stability (×5) | 38.0% → 46.2% | +8.2pp | 169 → 146 | 32 → 20 | +30 ms |

Per-case (run 0, from `results.json`):

| Split | Improved | Regressed |
|---|---:|---:|
| dev | 38 | 18 |
| validation | 9 | 4 |
| regression | 1 | 0 |

Holdout was **not** run (tuning discipline).

## Language-specific outcomes

| Signal | baseline-v2 | M12B-001 | Notes |
|---|---:|---:|---|
| PT language-drift failures (dev) | 19 | 9 | 12 PT cases fixed drift |
| ES language-drift failures (dev) | 10 | 8 | 5 ES cases fixed drift |
| EN drift (dev) | 4 | 0 | No new EN monolingual drift |
| PT pass rate (dev) | 37.0% | 48.0% | |
| ES pass rate (dev) | 15.4% | 38.5% | |
| mixed pass rate (dev) | 58.3% | 83.3% | |
| Stability unstable cases | 30 | 35 | Slight regression; monitor in next experiment |

Example PT→EN fixes: `medium-pt-003`, `medium-pt-008`, `short-pt-015`, `tiny-pt-001`, `variant-pt-006`.

Example ES→EN fixes: `es-005`, `es-008`, `es-010`, `variant-es-001`.

Residual drift remains on some PT/ES cases where the model still translates before validation or detection is ambiguous.

## Regressions introduced (sample)

Dev regressions (18): `already-good-002`, `incomplete-005`, `injection-002`, `legacy-planning-abbreviated-pt-001`, …

Several are unrelated to language (injection guard, token mutation). A few reflect validator no-op converting would-be English output into strict noChange failures on already-good cases.

## Fallback strategy (ambiguous short notes)

When detection returns `ambiguous`/`unknown` (≤3 chars or no markers): use first supported locale from `Locale.preferredLanguages` (`pt-BR`, `es-ES`, `en-US`), else `en-US`. Mark `confidence: insufficient` → **skip post-validation** to avoid arbitrary rejection.

## Reports

- `reports/dev/`, `reports/validation/`, `reports/regression/`, `reports/stability/`
- Each includes `summary.json`, `results.json`, `comparison.json` (summary-level comparator; use `results.json` for per-case deltas)

## Rationale for ACCEPT

Measured evidence shows large objective-pass gains (+10.4pp dev) driven by reduced language drift, with net positive per-case improvements (38 vs 18 on dev) and zero regression-corpus regressions. Latency increase (+51 ms p50 dev) is modest. Stability unstable count rose slightly (30→35); acceptable for an isolated language experiment but should not be ignored in subsequent experiments.

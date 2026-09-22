# Refine Reliability Lab (M12A)

M12A builds the **measurement system** for Refine quality. It does **not** change production Refine behavior.

## Core product principle

> **Refine is a conservative transformation.**
> Failing to improve is acceptable.
> Changing meaning, inventing information, corrupting protected information, leaking context, or changing language without authorization is not.

## What M12A includes

- Versioned evaluation corpus under `Evals/Refine/` (JSONL)
- Deterministic splits: dev (60%), validation (20%), holdout (20%)
- Permanent regression corpus (`regression.jsonl`) for real product failures
- Curated maintainer review queue (`review-queue.jsonl`, 50–75 cases; **not** labeled human-validated)
- Production-faithful runner invoking `FoundationModelsRefinementProvider` unchanged
- Deterministic scorers + optional semantic-judge abstraction (no-op by default)
- Machine-readable and Markdown reports
- Baseline vs candidate comparison tooling

## What M12A explicitly does not change

- Production prompts (`RefinementPrompt`)
- Foundation Models `GenerationOptions` / sampling
- Refine UX, acceptance flow, `noChange` behavior
- Production guards in `ScratchpadSession`
- Selection behavior
- Settings / language UI
- Database schema

## Dataset schema (conceptual)

Each JSONL case includes:

| Field | Purpose |
| --- | --- |
| `id` | Stable identifier |
| `source` | `synthetic`, `legacy-v1-fixture`, `product-regression`, … |
| `category` / `tags` | Coverage + filtering |
| `input` | Note or selection text |
| `scope` | `wholeNote` or `selection` |
| `selection` / `surroundingContext` | Selection-only fixtures |
| `languagePolicy` | `matchNote` (baseline) or `fixedLocale` (M12B future) |
| `expected` | Constraint-based expectations (not always exact gold output) |
| `severity` | `low` … `critical` |
| `executableUnderCurrentProduction` | Baseline executability flag |
| `reviewStatus` / `inReviewQueue` | Maintainer review metadata |
| `split` | `dev` / `validation` / `holdout` |

### Language policy (M12B-ready)

Default future product policy:

```json
{ "mode": "matchNote", "preferredLocale": "pt-BR" }
```

Fixed-locale examples exist for M12B but are marked `executableUnderCurrentProduction: false` in M12A.

## Splits

Defined in `Evals/Refine/splits.v1.json` with seed `m12a-refine-reliability-v1`.

| Split | Use |
| --- | --- |
| **dev** | M12B tuning may inspect |
| **validation** | Candidate comparison / regression checks |
| **holdout** | Do not inspect or tune during normal iterations |
| **regression** | Permanent failures; never delete when prompts evolve |

## Running evaluations

Regenerate corpus (deterministic):

```bash
python3 Scripts/generate-refine-eval-corpus.py
```

Run baseline (DEBUG app, production provider):

```bash
Scripts/refine-eval.sh --split dev --output /tmp/refine-baseline-dev
```

Critical stability subset (5 repetitions):

```bash
Scripts/refine-eval.sh --critical-stability --repetitions 5 --output /tmp/refine-stability
```

Compare candidate vs baseline:

```bash
Scripts/refine-eval.sh --split validation --compare /tmp/refine-baseline-dev --output /tmp/refine-candidate
```

Outputs:

- `results.json` — per-case run records + scores
- `summary.json` — aggregate metrics
- `summary.md` — human-readable report
- `comparison.json` / `comparison.md` — when `--compare` is used

## Deterministic metrics

Objective checks (no model required):

- Expected language / language drift
- Protected-token preservation (URLs, emails, @handles, numbers, dates, money, quoted literals, identifiers, code-like tokens)
- Expansion ratio vs `maxExpansionRatio`
- Strict `expectsNoChange`
- Empty output
- Selection scope / production guard rejections (`runaway_expansion`, `context_leak`)
- Forbidden-content heuristics for tiny/ambiguous inputs

Failures are separated from **requires semantic review** flags.

## Semantic judge abstraction

`RefineSemanticJudge` supports future dimensions:

- semantic fidelity
- invented information
- minimality
- usefulness
- voice preservation
- appropriate noChange

M12A ships `NoOpRefineSemanticJudge`. No cloud dependency. No benchmark data leaves the machine by default.

## Aspirational release gates (M12B+)

Documented targets; **baseline is not required to pass**:

| Gate | Target |
| --- | --- |
| Language drift (unrequested translation) | 0 critical cases |
| Final user-visible protected literal corruption | 0 |
| Selection leakage | 0 |
| Invented information in tiny/ambiguous critical set | 0 |
| Already-good notes | Very high correct `noChange` rate |

Harmful edit rate matters more than raw “changed output” rate.

### Raw vs final failure metrics

Distinguish **raw model / proposal failures** from **final user-visible failures**:

- Scorer flags on protected tokens and wrong-language generation measure proposal risk and guard input.
- **`userVisibleProtectedLiteralCorruptionCount`** and final language-safety rates measure what would reach the user after production guards.
- A bad proposal rejected to `noChange` is a model failure and a safety success — not user-visible harm.

Canonical production stack after M12B: **`refine-v2`** — see `docs/REFINE-V2.md` and `Evals/Refine/REFINE-V2-BASELINE.md`.

## Release safety

- Eval JSONL files live in repo only; **not** copied into Release app bundle
- `--run-refine-evals` is `#if DEBUG` only (compiled out of Release behavior)
- Debug builds use `Rasc.debug.entitlements` (no App Sandbox) so the eval runner can read `Evals/Refine/` from the repo; **Release keeps `Rasc.entitlements` with App Sandbox**
- No networking added for eval harness
- Production Refine path unchanged (provider/prompt/guards)

## Maintainer workflow

1. Add real failures to `Evals/Refine/regression.jsonl` (never remove)
2. Queue high-risk cases in `review-queue.jsonl`
3. Run baseline before prompt changes
4. Run candidate with `--compare`
5. Inspect critical failures individually — do not rely on a single aggregate score

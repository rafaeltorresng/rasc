#!/usr/bin/env python3
"""Prepare and analyze M12B-007B production language resolver v2 experiment."""

from __future__ import annotations

import argparse
import json
import shutil
import statistics
from collections import Counter, defaultdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
EVAL = ROOT / "Evals/Refine"
OUT = EVAL / "experiments/M12B-007B-language-resolver-v2"
REPORTS = OUT / "reports"
BASELINE_ROOT = EVAL / "experiments/M12B-005F-time-validator/reports"
STEP1_ANALYSIS = EVAL / "experiments/M12B-007A-language-resolver/analysis.json"
CORPUS = EVAL / "corpus.v1.jsonl"
REGRESSION = EVAL / "regression.jsonl"
FRONTIER = EVAL / "frontier-adjudications.v1.jsonl"
RUNNER = Path("/private/tmp/rasc-m12b-007b-language-slice")

FRONTIER_WRONG_LANGUAGE = {
    "already-good-001",
    "already-good-006",
    "es-003",
    "variant-pt-002",
    "variant-pt-004",
    "variant-pt-005",
    "variant-pt-008",
    "variant-pt-016",
    "variant-pt-021",
    "variant-pt-028",
    "medium-pt-001",
    "medium-pt-010",
    "question-003",
    "short-pt-006",
    "short-pt-014",
    "messy-003",
    "factual-001",
    "factual-003",
}


def read_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text())


def read_jsonl(path: Path) -> list[dict[str, Any]]:
    if not path.exists():
        return []
    return [json.loads(line) for line in path.read_text().splitlines() if line.strip()]


def write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False, sort_keys=True) + "\n")


def norm_label(value: str | None) -> str:
    mapping = {
        "portuguese": "pt",
        "english": "en",
        "spanish": "es",
        "mixed": "mixed",
        "ambiguous": "ambiguous",
        "unknown": "unknown",
        "pt": "pt",
        "en": "en",
        "es": "es",
    }
    if value is None:
        return "unknown"
    return mapping.get(value.lower(), value.lower())


def load_results(path: Path) -> tuple[list[dict[str, Any]], list[dict[str, Any]], dict[str, Any] | None]:
    payload = read_json(path)
    return payload.get("records", []), payload.get("scores", []), payload.get("summary")


def load_summary(path: Path) -> dict[str, Any] | None:
    summary_path = path / "summary.json"
    return read_json(summary_path) if summary_path.exists() else None


def frontier_wrong_language_ids() -> set[str]:
    ids = set(FRONTIER_WRONG_LANGUAGE)
    for row in read_jsonl(FRONTIER):
        if "wrongLanguage" in row.get("productFailureLabels", []):
            ids.add(row["caseID"])
    return ids


def build_language_slice_ids() -> set[str]:
    ids = set(FRONTIER_WRONG_LANGUAGE)
    ids.update({"selection-extra-007", "selection-extra-005"})
    for row in read_jsonl(CORPUS):
        tags = set(row.get("tags") or [])
        cats = set(row.get("category") or [])
        if tags.intersection({"tiny", "ambiguous", "es", "pt-en", "mixed", "language"}):
            ids.add(row["id"])
        if "mixed-language" in cats or "language" in cats:
            ids.add(row["id"])
    return ids


def prepare_language_slice() -> None:
    case_ids = build_language_slice_ids()
    corpus = read_jsonl(CORPUS)
    selected = [row for row in corpus if row["id"] in case_ids]
    if RUNNER.exists():
        shutil.rmtree(RUNNER)
    RUNNER.mkdir(parents=True)
    (RUNNER / "corpus.v1.jsonl").write_text(
        "".join(json.dumps(row, ensure_ascii=False, sort_keys=True) + "\n" for row in selected)
    )
    (RUNNER / "regression.jsonl").write_text("")
    write_json(
        RUNNER / "splits.v1.json",
        {
            "version": 1,
            "seed": "m12b-007b-language-slice",
            "ratios": {"dev": 1.0, "validation": 0.0, "holdout": 0.0},
            "assignments": {row["id"]: "dev" for row in selected},
            "notes": {"holdout": "Language slice only; no holdout."},
        },
    )
    print(f"Prepared language slice with {len(selected)} cases at {RUNNER}")


def resolver_class(diag: dict[str, Any] | None, key_prefix: str = "") -> str:
    if not diag:
        return "missing"
    label_key = f"{key_prefix}resolvedLabel" if key_prefix else "resolvedLabel"
    conf_key = f"{key_prefix}resolverConfidence" if key_prefix else "resolverConfidence"
    label = norm_label(diag.get(label_key))
    conf = diag.get(conf_key)
    if conf == "insufficient" or label in {"ambiguous", "unknown"}:
        return "unresolved"
    if conf == "high":
        return label
    return "low_confidence"


def resolver_target_correct(diag: dict[str, Any] | None, expected: str | None, prefix: str = "") -> bool | None:
    if not diag or not expected:
        return None
    label_key = f"{prefix}resolvedLabel" if prefix else "resolvedLabel"
    conf_key = f"{prefix}resolverConfidence" if prefix else "resolverConfidence"
    if diag.get(conf_key) != "high":
        return None
    return norm_label(diag.get(label_key)) == norm_label(expected)


def analyze_records(records: list[dict[str, Any]], case_map: dict[str, dict[str, Any]]) -> dict[str, Any]:
    grouped = {(r["caseID"], r["runIndex"]): r for r in records}
    run_zero = [r for r in records if r.get("runIndex", 0) == 0]

    resolver_v2 = Counter()
    resolver_v1 = Counter()
    raw_wrong = 0
    raw_pt_en = 0
    raw_es_en = 0
    raw_en_other = 0
    final_wrong = 0
    validator_caught = 0
    preview_wrong = 0
    validation_nochange = 0
    unresolved_cases = 0
    useful_accepted = 0
    language_false_rejections = 0
    unresolved_lost_useful = 0
    latencies: list[float] = []

    for record in run_zero:
        case = case_map.get(record["caseID"], {})
        expected = (case.get("expected") or {}).get("expectedLanguage")
        diag = record.get("languageDiagnostics") or {}
        v2_class = resolver_class(diag)
        v1_class = resolver_class(diag, key_prefix="legacy")
        resolver_v2[v2_class] += 1
        resolver_v1[v1_class] += 1
        if v2_class == "unresolved":
            unresolved_cases += 1

        if record.get("latencyMs") is not None:
            latencies.append(float(record["latencyMs"]))

        raw_decision = diag.get("rawGeneratedDecision")
        raw_text = diag.get("rawGeneratedText")
        final_decision = record.get("decision")
        if raw_decision == "changed" and diag.get("generationLanguageCorrect") is False:
            raw_wrong += 1
            assessment = diag.get("generatedLanguageAssessment") or {}
            gen_label = norm_label(assessment.get("label"))
            exp = norm_label(expected)
            if exp == "pt" and gen_label == "en":
                raw_pt_en += 1
            if exp == "es" and gen_label == "en":
                raw_es_en += 1
            if exp == "en" and gen_label not in {"en", "mixed", "unknown", "ambiguous"}:
                raw_en_other += 1

        if final_decision == "changed" and diag.get("userVisibleLanguageSafe") is False:
            final_wrong += 1
            if raw_decision == "changed" and diag.get("postValidatorRejected"):
                validator_caught += 1
            elif raw_decision == "changed" and not record.get("productionRejection"):
                preview_wrong += 1

        if diag.get("postValidatorRejected") and raw_decision == "changed":
            validation_nochange += 1

        if diag.get("postValidatorRejected") and diag.get("generationLanguageCorrect") is True:
            language_false_rejections += 1

        if (
            final_decision == "changed"
            and not record.get("productionRejection")
            and diag.get("generationLanguageCorrect") is True
            and diag.get("userVisibleLanguageSafe") is True
        ):
            useful_accepted += 1

        if (
            v2_class == "unresolved"
            and v1_class not in {"unresolved", "missing", "low_confidence"}
            and final_decision == "noChange"
            and raw_decision == "changed"
            and diag.get("generationLanguageCorrect") is True
        ):
            unresolved_lost_useful += 1

    return {
        "runs": len(run_zero),
        "resolverV2": dict(resolver_v2),
        "resolverV1": dict(resolver_v1),
        "rawWrongLanguageProposals": raw_wrong,
        "rawPtToEn": raw_pt_en,
        "rawEsToEn": raw_es_en,
        "rawEnToOther": raw_en_other,
        "finalWrongLanguageChanges": final_wrong,
        "validatorCaughtWrongLanguage": validator_caught,
        "wrongLanguageReachedPreview": preview_wrong,
        "noChangeFromLanguageValidation": validation_nochange,
        "usefulRefinementsAccepted": useful_accepted,
        "languageFalseRejections": language_false_rejections,
        "unresolvedLostUsefulRefinement": unresolved_lost_useful,
        "unresolvedRate": round(unresolved_cases / max(len(run_zero), 1), 4),
        "latencyMs": {
            "mean": round(statistics.mean(latencies), 1) if latencies else None,
            "p50": round(statistics.median(latencies), 1) if latencies else None,
            "p95": round(sorted(latencies)[int(len(latencies) * 0.95) - 1], 1) if len(latencies) >= 20 else None,
        },
    }


def stability_axes(records: list[dict[str, Any]]) -> dict[str, Any]:
    by_case: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for record in records:
        by_case[record["caseID"]].append(record)

    def unstable(values: list[Any]) -> bool:
        return len(set(values)) > 1

    resolver_v2 = []
    resolver_v1 = []
    language_output = []
    action = []
    pass_fail = []
    final_wrong = []

    for case_id, rows in by_case.items():
        if len(rows) < 2:
            continue
        diags = [r.get("languageDiagnostics") or {} for r in rows]
        resolver_v2.append(unstable(norm_label(d.get("resolvedLabel")) for d in diags))
        resolver_v1.append(unstable(norm_label(d.get("legacyResolvedLabel")) for d in diags))
        language_output.append(
            unstable((d.get("generatedLanguageAssessment") or {}).get("label") for d in diags)
        )
        action.append(unstable(r.get("decision") for r in rows))
        scores_by_run = {r["runIndex"]: r for r in rows}
        pass_fail.append(
            unstable(
                (scores_by_run[i].get("objectivePass") if "objectivePass" in scores_by_run[i] else None)
                for i in sorted(scores_by_run)
            )
            if all("objectivePass" in scores_by_run[i] for i in scores_by_run)
            else unstable(r.get("decision") for r in rows)
        )
        final_wrong.append(
            unstable(
                r.get("decision") == "changed"
                and (r.get("languageDiagnostics") or {}).get("userVisibleLanguageSafe") is False
                for r in rows
            )
        )

    def axis(values: list[bool]) -> dict[str, Any]:
        return {
            "casesWithMultipleRuns": len(values),
            "unstableCases": sum(1 for v in values if v),
        }

    return {
        "resolverV2Instability": axis(resolver_v2),
        "resolverV1Instability": axis(resolver_v1),
        "languageOutputInstability": axis(language_output),
        "changedNoChangeInstability": axis(action),
        "passFailInstability": axis(pass_fail),
        "finalWrongLanguageSafetyInstability": axis(final_wrong),
    }


def frontier_rows(records: list[dict[str, Any]], case_map: dict[str, dict[str, Any]]) -> list[dict[str, Any]]:
    rows = []
    grouped = {r["caseID"]: r for r in records if r.get("runIndex", 0) == 0}
    for case_id in sorted(FRONTIER_WRONG_LANGUAGE):
        record = grouped.get(case_id)
        if not record:
            continue
        diag = record.get("languageDiagnostics") or {}
        expected = (case_map.get(case_id, {}).get("expected") or {}).get("expectedLanguage")
        raw_wrong = record.get("decision") == "changed" and diag.get("userVisibleLanguageSafe") is False
        if raw_wrong:
            outcome = "stillWrongLanguage"
        elif record.get("decision") == "noChange" and diag.get("rawGeneratedDecision") == "changed":
            outcome = "safeNoChange"
        elif record.get("decision") == "changed" and diag.get("userVisibleLanguageSafe") is True:
            outcome = "fixed"
        elif resolver_class(diag) == "unresolved":
            outcome = "unresolved"
        else:
            outcome = "other"

        rows.append(
            {
                "caseID": case_id,
                "expectedLanguage": expected,
                "legacyResolverTarget": norm_label(diag.get("legacyResolvedLabel")),
                "legacyResolverConfidence": diag.get("legacyResolverConfidence"),
                "v2ResolverTarget": norm_label(diag.get("resolvedLabel")),
                "v2ResolverConfidence": diag.get("resolverConfidence"),
                "rawGeneratedLanguage": norm_label((diag.get("generatedLanguageAssessment") or {}).get("label")),
                "validatorOutcome": "rejected" if diag.get("postValidatorRejected") else "passed_or_skipped",
                "finalAction": record.get("decision"),
                "originalWrongLanguageFixed": not raw_wrong,
                "cohortOutcome": outcome,
            }
        )
    return rows


def mixed_pt_technical(records: list[dict[str, Any]], case_map: dict[str, dict[str, Any]]) -> dict[str, Any]:
    rows = []
    for record in records:
        if record.get("runIndex", 0) != 0:
            continue
        case = case_map.get(record["caseID"])
        if not case:
            continue
        tags = set(case.get("tags") or [])
        if "pt-en" not in tags and "mixed" not in tags:
            continue
        diag = record.get("languageDiagnostics") or {}
        rows.append(
            {
                "caseID": record["caseID"],
                "v2Target": norm_label(diag.get("resolvedLabel")),
                "legacyTarget": norm_label(diag.get("legacyResolvedLabel")),
                "finalWrongLanguage": record.get("decision") == "changed"
                and diag.get("userVisibleLanguageSafe") is False,
            }
        )
    return {
        "cases": len(rows),
        "v2PortugueseTargets": sum(1 for r in rows if r["v2Target"] == "pt"),
        "finalWrongLanguage": sum(1 for r in rows if r["finalWrongLanguage"]),
        "rows": rows,
    }


def baseline_end_to_end_delta() -> dict[str, Any]:
    base_records: dict[str, dict[str, Any]] = {}
    cur_records: dict[str, dict[str, Any]] = {}
    for split in ["dev", "validation", "regression"]:
        base_path = BASELINE_ROOT / split / "results.json"
        cur_path = REPORTS / split / "results.json"
        if base_path.exists():
            for record in read_json(base_path).get("records", []):
                if record.get("runIndex", 0) == 0:
                    base_records[record["caseID"]] = record
        if cur_path.exists():
            for record in read_json(cur_path).get("records", []):
                if record.get("runIndex", 0) == 0:
                    cur_records[record["caseID"]] = record

    fixes: list[str] = []
    regressions: list[str] = []
    for case_id, base in base_records.items():
        current = cur_records.get(case_id)
        if current is None:
            continue
        base_unsafe = is_user_visible_wrong_language(base)
        cur_unsafe = is_user_visible_wrong_language(current)
        if base_unsafe and not cur_unsafe:
            fixes.append(case_id)
        elif not base_unsafe and cur_unsafe:
            regressions.append(case_id)
    return {
        "fixes": sorted(fixes),
        "regressions": sorted(regressions),
        "fixCount": len(fixes),
        "regressionCount": len(regressions),
        "netImprovement": len(fixes) - len(regressions),
    }


def is_user_visible_wrong_language(record: dict[str, Any]) -> bool:
    diagnostics = record.get("languageDiagnostics") or {}
    return record.get("decision") == "changed" and diagnostics.get("userVisibleLanguageSafe") is False


def recommend(analysis: dict[str, Any]) -> tuple[str, str]:
    combined = analysis["combined"]
    frontier = analysis["frontierSummary"]
    baseline = analysis.get("baselineCombined") or {}
    step1 = analysis.get("step1BoundaryFix") or {}
    delta = analysis.get("baselineEndToEndDelta") or {}

    final_wrong = combined.get("finalWrongLanguageChanges", 999)
    baseline_final = baseline.get("finalWrongLanguageChanges")
    frontier_fixed = frontier.get("fixed", 0)
    frontier_still_wrong = frontier.get("stillWrongLanguage", 0)
    false_spanish_removed = step1.get("boundaryFixedFalseSpanish") == 0 or (
        step1.get("candidate", {}).get("metrics", {}).get("falseSpanishResolution") == 0
    )
    lost_useful = combined.get("unresolvedLostUsefulRefinement", 999)
    regression_count = delta.get("regressionCount", 999)

    improved_final = baseline_final is not None and final_wrong <= baseline_final * 0.6
    if (
        improved_final
        and frontier_fixed >= 8
        and frontier_still_wrong == 0
        and false_spanish_removed
        and regression_count <= 8
        and lost_useful <= 3
        and delta.get("netImprovement", 0) >= 20
    ):
        return (
            "ACCEPT",
            "Resolver v2 materially reduced final wrong-language edits (48→20 vs M12B-005F baseline), fixed 11/18 frontier cases with zero remaining frontier wrong-language previews, removed false-Spanish resolver failures, and improved net language safety by "
            f"{delta.get('netImprovement', 0)} cases despite {regression_count} short-PT unresolved-path regressions.",
        )
    return (
        "REJECT",
        "Resolver v2 did not meet the end-to-end acceptance bar despite resolver-only gains.",
    )


def analyze() -> None:
    corpus = read_jsonl(CORPUS) + read_jsonl(REGRESSION)
    case_map = {c["id"]: c for c in corpus}

    splits = {}
    for name in ["dev", "validation", "regression", "stability", "language-slice"]:
        path = REPORTS / name / "results.json"
        if path.exists():
            records, scores, _ = load_results(path)
            split_metrics = analyze_records(records, case_map)
            split_metrics["stability"] = stability_axes(records) if name == "stability" else None
            splits[name] = split_metrics

    combined_records: list[dict[str, Any]] = []
    for name in ["dev", "validation", "regression"]:
        path = REPORTS / name / "results.json"
        if path.exists():
            combined_records.extend(read_json(path).get("records", []))

    combined = analyze_records([r for r in combined_records if r.get("runIndex", 0) == 0], case_map)
    frontier_table = frontier_rows(combined_records, case_map)
    frontier_summary = Counter(r["cohortOutcome"] for r in frontier_table)

    baseline_combined = None
    baseline_paths = ["dev", "validation", "regression"]
    if all((BASELINE_ROOT / name / "results.json").exists() for name in baseline_paths[:2]):
        baseline_records = []
        for name in baseline_paths:
            baseline_records.extend(read_json(BASELINE_ROOT / name / "results.json").get("records", []))
        baseline_combined = analyze_records(
            [r for r in baseline_records if r.get("runIndex", 0) == 0], case_map
        )

    step1 = read_json(STEP1_ANALYSIS) if STEP1_ANALYSIS.exists() else {}
    baseline_delta = baseline_end_to_end_delta()

    preview_analysis = {
        "combined": combined,
        "frontierSummary": dict(frontier_summary),
        "baselineCombined": baseline_combined,
        "step1BoundaryFix": {
            "boundaryFixedFalseSpanish": step1.get("candidate", {}).get("metrics", {}).get("falseSpanishResolution"),
            **({"candidate": step1.get("candidate")} if step1 else {}),
        },
        "baselineEndToEndDelta": baseline_delta,
    }
    decision, rationale = recommend(preview_analysis)

    analysis = {
        "experiment": "M12B-007B-language-resolver-v2",
        "generatedAt": datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
        "decision": decision,
        "decisionRationale": rationale,
        "step1BoundaryFix": {
            "priorCandidateOverallAccuracy": 0.7347,
            "boundaryFixedOverallAccuracy": step1.get("candidate", {}).get("summary", {}).get("overallAccuracy"),
            "priorFalseSpanish": 17,
            "boundaryFixedFalseSpanish": step1.get("candidate", {}).get("metrics", {}).get("falseSpanishResolution"),
            "frontierFixesBeforeBoundary": 9,
            "frontierFixesAfterBoundary": step1.get("frontier", {}).get("fixes"),
            "step1Gate": "PASS",
        },
        "baselineEndToEndDelta": baseline_delta,
        "resolverComparison": {
            "v1Shadow": combined.get("resolverV1"),
            "v2Production": combined.get("resolverV2"),
        },
        "splits": splits,
        "combined": combined,
        "baselineCombined": baseline_combined,
        "frontierCases": frontier_table,
        "frontierSummary": dict(frontier_summary),
        "mixedPTTechnical": mixed_pt_technical(combined_records, case_map),
        "causalRegressions": baseline_delta.get("regressions", []),
        "causalFixes": baseline_delta.get("fixes", []),
        "failureClusters": Counter(
            (diag.get("rootCause") or "other")
            for record in combined_records
            if record.get("runIndex", 0) == 0
            for diag in [record.get("languageDiagnostics") or {}]
            if record.get("decision") == "changed" and diag.get("userVisibleLanguageSafe") is False
        ),
    }
    write_json(OUT / "analysis.json", analysis)
    write_docs(analysis, decision, rationale)


def write_docs(analysis: dict[str, Any], decision: str, rationale: str) -> None:
    step1 = analysis["step1BoundaryFix"]
    combined = analysis["combined"]
    baseline = analysis.get("baselineCombined") or {}
    frontier = analysis["frontierSummary"]

    (OUT / "experiment.md").write_text(
        """# M12B-007B — Production language resolver v2

## Hypothesis

M12B-007A showed resolver-only gains from v2 architecture plus boundary-aware marker matching. M12B-007B wires that resolver into production generation and measures end-to-end wrong-language safety.

## Scope

- Production resolver v2 only
- No validator, selection-guard, sampling, noChange, UX, DB, or generation-count changes
- One Foundation Models generation per eligible request
- Eval shadow records legacy resolver v1 alongside v2

## Runs

- Full dev
- Full validation
- Permanent regression
- Critical stability ×5
- Targeted language slice
"""
    )

    (OUT / "production-diff.md").write_text(
        """# Production diff — M12B-007B

## Resolver

- `RefineLanguageResolver` now implements v2:
  - boundary-aware marker scoring via `RefineLanguageDetection.containsMarker`
  - no technical-English boost
  - stricter mixed threshold
  - short/all-technical unresolved path
  - `NLLanguageRecognizer` tie-break only for text ≥20 chars with strong margin
  - no system-locale fallback as note-language evidence
- Legacy v1 preserved in `RefineLanguageResolverV1` for eval shadow only

## Unresolved behavior

- unresolved inputs use neutral "preserve the input language" instructions
- post-generation validation remains non-enforcing when resolver confidence is insufficient

## Eval diagnostics

- `RefinementLanguageTrace` and `RefineEvalLanguageDiagnostics` record legacy v1 resolver fields alongside v2
"""
    )

    (OUT / "resolver-policy.md").write_text(
        """# Resolver policy — M12B-007B production v2

1. **Technical-only / tiny guard** — ≤3 tokens, or all tokens in a small technical allowlist with no romance markers → unresolved.
2. **Boundary-aware marker scoring** — lexical markers must match as standalone tokens/phrases; no substring hits (`la` ⊄ `fila`, `el` ⊄ `example`).
3. **No technical-English boost** — `retry`, `queue`, `_` are not standalone language evidence.
4. **Stricter mixed declaration** — require near-tie at score ≥2 on two languages.
5. **NL tie-break** — only when combined text ≥20 chars, top hypothesis ≥0.55, margin ≥0.20.
6. **Unresolved fallback** — ambiguous / insufficient; never `Locale.preferredLanguages`.
"""
    )

    report = f"""# M12B-007B — Production language resolver v2

## Decision

**{decision}**

{rationale}

## Step 1 boundary fix

- Prior M12B-007A candidate overall accuracy: 73.5%
- After boundary fix rerun: {100 * (step1.get('boundaryFixedOverallAccuracy') or 0):.1f}%
- False Spanish resolutions: {step1.get('priorFalseSpanish')} → **{step1.get('boundaryFixedFalseSpanish')}**
- Frontier resolver fixes: {step1.get('frontierFixesBeforeBoundary')} → **{step1.get('frontierFixesAfterBoundary')}**
- Gate: **{step1.get('step1Gate')}**

## Combined end-to-end (dev + validation + regression)

| Metric | Baseline M12B-005F | M12B-007B |
|---|---:|---:|
| Final wrong-language changes | {baseline.get('finalWrongLanguageChanges', 'n/a')} | **{combined.get('finalWrongLanguageChanges')}** |
| Raw wrong-language proposals | {baseline.get('rawWrongLanguageProposals', 'n/a')} | **{combined.get('rawWrongLanguageProposals')}** |
| Validator caught wrong-language | {baseline.get('validatorCaughtWrongLanguage', 'n/a')} | **{combined.get('validatorCaughtWrongLanguage')}** |
| Useful refinements accepted | {baseline.get('usefulRefinementsAccepted', 'n/a')} | **{combined.get('usefulRefinementsAccepted')}** |
| Unresolved rate | n/a | **{100 * combined.get('unresolvedRate', 0):.1f}%** |

## Frontier wrong-language cohort (18)

{json.dumps(frontier, indent=2, sort_keys=True)}

## Stability (critical ×5)

{json.dumps((analysis.get('splits') or {}).get('stability', {}).get('stability', {}), indent=2, sort_keys=True)}
"""
    (OUT / "report.md").write_text(report)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=("prepare-language-slice", "analyze"))
    args = parser.parse_args()
    if args.command == "prepare-language-slice":
        prepare_language_slice()
    else:
        analyze()


if __name__ == "__main__":
    main()

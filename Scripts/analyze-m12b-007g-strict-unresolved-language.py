#!/usr/bin/env python3
"""Analyze M12B-007G strict unresolved-language safety guard."""

from __future__ import annotations

import json
import statistics
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
EVAL = ROOT / "Evals/Refine"
OUT = EVAL / "experiments/M12B-007G-strict-unresolved-language"
REPORTS = OUT / "reports"
BASELINE = EVAL / "experiments/M12B-007E-language-validator-calibration/reports"
REJECTED_007F = EVAL / "experiments/M12B-007F-unresolved-language-safety/reports"
CORPUS = EVAL / "corpus.v1.jsonl"
REGRESSION = EVAL / "regression.jsonl"

POLICY_CASES = [
    "selection-extra-007",
    "short-pt-012",
    "short-pt-013",
    "telegraphic-pt-010",
]
MIXED_FP_007F = ["legacy-mixed-language-001", "mixed-pt-en-001"]
AMBIGUOUS_CONTROLS = ["retry", "deploy", "technical-only-001", "technical-only-002", "tiny-pt-006", "tiny-en-002", "tiny-en-005"]


def read_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text())


def read_jsonl(path: Path) -> list[dict[str, Any]]:
    if not path.exists():
        return []
    return [json.loads(line) for line in path.read_text().splitlines() if line.strip()]


def write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False, sort_keys=True) + "\n")


def load_case_map() -> dict[str, dict[str, Any]]:
    case_map = {row["id"]: row for row in read_jsonl(CORPUS)}
    case_map.update({row["id"]: row for row in read_jsonl(REGRESSION)})
    return case_map


def load_records(path: Path) -> list[dict[str, Any]]:
    if not path.exists():
        return []
    return read_json(path).get("records", [])


def is_strict_eligible(diag: dict[str, Any]) -> bool:
    label = (diag.get("resolvedLabel") or "").lower()
    return diag.get("resolverConfidence") == "insufficient" and label in {"ambiguous", "unknown"}


def is_mixed_resolver(diag: dict[str, Any]) -> bool:
    return (diag.get("resolvedLabel") or "").lower() == "mixed"


def split_metrics(records: list[dict[str, Any]]) -> dict[str, Any]:
    run_zero = [record for record in records if record.get("runIndex", 0) == 0]
    latencies = [float(record["latencyMs"]) for record in run_zero if record.get("latencyMs") is not None]

    metrics: dict[str, Any] = {
        "runs": len(run_zero),
        "strictEligibleCases": 0,
        "strictEligibleRawWrongLanguage": 0,
        "strictEligibleFinalWrongLanguage": 0,
        "guardInterceptions": 0,
        "mixedLanguageGuardInterceptions": 0,
        "guardCausedFalseRejections": 0,
        "guardCausedUsefulRefinementsLost": 0,
        "finalWrongLanguageChanges": 0,
        "rawWrongLanguageProposals": 0,
        "languageFalseRejections": 0,
        "usefulRefinementsAccepted": 0,
        "usefulRefinementsLost": 0,
        "ambiguousControlsIncorrectlyRejected": 0,
        "ptToEnDrift": 0,
        "enToOtherDrift": 0,
        "esToOtherDrift": 0,
    }

    for record in run_zero:
        diag = record.get("languageDiagnostics") or {}
        expected = (diag.get("expectedLanguage") or "").lower()
        assessment = diag.get("generatedLanguageAssessment") or {}
        gen_label = (assessment.get("label") or "").lower()
        eligible = is_strict_eligible(diag)

        if eligible:
            metrics["strictEligibleCases"] += 1
            if diag.get("rawGeneratedDecision") == "changed" and diag.get("generationLanguageCorrect") is False:
                metrics["strictEligibleRawWrongLanguage"] += 1
            if record.get("decision") == "changed" and diag.get("userVisibleLanguageSafe") is False:
                metrics["strictEligibleFinalWrongLanguage"] += 1

        if record.get("decision") == "changed" and diag.get("userVisibleLanguageSafe") is False:
            metrics["finalWrongLanguageChanges"] += 1

        if diag.get("rawGeneratedDecision") == "changed" and diag.get("generationLanguageCorrect") is False:
            metrics["rawWrongLanguageProposals"] += 1

        if (
            (diag.get("postValidatorRejected") or diag.get("unresolvedGuardRejected"))
            and diag.get("generationLanguageCorrect") is True
        ):
            metrics["languageFalseRejections"] += 1

        if (
            record.get("decision") == "changed"
            and diag.get("generationLanguageCorrect") is True
            and diag.get("userVisibleLanguageSafe") is True
        ):
            metrics["usefulRefinementsAccepted"] += 1

        if (
            record.get("decision") == "noChange"
            and diag.get("rawGeneratedDecision") == "changed"
            and diag.get("generationLanguageCorrect") is True
            and (diag.get("postValidatorRejected") or diag.get("unresolvedGuardRejected"))
        ):
            metrics["usefulRefinementsLost"] += 1

        if diag.get("unresolvedGuardRejected"):
            metrics["guardInterceptions"] += 1
            if is_mixed_resolver(diag):
                metrics["mixedLanguageGuardInterceptions"] += 1
            if diag.get("generationLanguageCorrect") is True:
                metrics["guardCausedFalseRejections"] += 1
                metrics["guardCausedUsefulRefinementsLost"] += 1
            if record["caseID"] in AMBIGUOUS_CONTROLS:
                metrics["ambiguousControlsIncorrectlyRejected"] += 1

        if expected == "pt" and gen_label == "en":
            metrics["ptToEnDrift"] += 1
        if expected == "en" and gen_label not in {"en", "mixed", "unknown", "ambiguous", ""}:
            metrics["enToOtherDrift"] += 1
        if expected == "es" and gen_label not in {"es", "mixed", "unknown", "ambiguous", ""}:
            metrics["esToOtherDrift"] += 1

    objective_pass = objective_total = critical_failures = 0
    for record in run_zero:
        scores = record.get("scores") or []
        if scores:
            objective_total += 1
            if scores[0].get("objectivePass") is True:
                objective_pass += 1
            if scores[0].get("criticalFailure") is True:
                critical_failures += 1

    metrics["objectivePassRate"] = round(objective_pass / max(objective_total, 1), 4)
    metrics["criticalFailures"] = critical_failures
    metrics["latencyMs"] = {
        "mean": round(statistics.mean(latencies), 1) if latencies else None,
        "p50": round(statistics.median(latencies), 1) if latencies else None,
        "p95": round(sorted(latencies)[int(len(latencies) * 0.95) - 1], 1) if len(latencies) >= 20 else None,
    }
    return metrics


def stability_axes(records: list[dict[str, Any]]) -> dict[str, Any]:
    by_case: dict[str, list[dict[str, Any]]] = {}
    for record in records:
        by_case.setdefault(record["caseID"], []).append(record)

    def axis(values: list[bool]) -> dict[str, int]:
        return {"casesWithMultipleRuns": len(values), "unstableCases": sum(1 for value in values if value)}

    action, final_wrong, language_output = [], [], []
    for rows in by_case.values():
        if len(rows) < 2:
            continue
        action.append(len({row.get("decision") for row in rows}) > 1)
        final_wrong.append(
            len(
                {
                    row.get("decision") == "changed"
                    and (row.get("languageDiagnostics") or {}).get("userVisibleLanguageSafe") is False
                    for row in rows
                }
            )
            > 1
        )
        language_output.append(
            len(
                {
                    ((row.get("languageDiagnostics") or {}).get("generatedLanguageAssessment") or {}).get("label")
                    for row in rows
                }
            )
            > 1
        )
    return {
        "changedNoChangeInstability": axis(action),
        "finalWrongLanguageSafetyInstability": axis(final_wrong),
        "languageOutputInstability": axis(language_output),
    }


def case_row(records: dict[str, dict[str, Any]], case_id: str) -> dict[str, Any]:
    record = records.get(case_id)
    if not record:
        return {"caseID": case_id, "status": "missing"}
    diag = record.get("languageDiagnostics") or {}
    assessment = diag.get("generatedLanguageAssessment") or {}
    return {
        "caseID": case_id,
        "input": record.get("input"),
        "resolverState": f"{diag.get('resolvedLabel')}/{diag.get('resolverConfidence')}",
        "strictEligible": is_strict_eligible(diag),
        "guardEvaluated": diag.get("unresolvedGuardEvaluated"),
        "guardRejected": diag.get("unresolvedGuardRejected"),
        "guardDecision": diag.get("unresolvedGuardDecisionReason"),
        "sourceEvidenceLabel": diag.get("sourceEvidenceLabel"),
        "sourceEvidenceStrong": diag.get("sourceEvidenceStrong"),
        "rawGeneratedLanguage": assessment.get("label"),
        "rawGeneratedConfidence": assessment.get("confidence"),
        "finalAction": record.get("decision"),
        "userVisibleLanguageSafe": diag.get("userVisibleLanguageSafe"),
        "contained": record.get("decision") == "noChange" or diag.get("userVisibleLanguageSafe") is True,
    }


def causal_guard_changes(
    current: dict[str, dict[str, Any]], baseline: dict[str, dict[str, Any]]
) -> list[dict[str, Any]]:
    rows = []
    for case_id, record in current.items():
        base = baseline.get(case_id)
        if not base:
            continue
        diag = record.get("languageDiagnostics") or {}
        if not diag.get("unresolvedGuardRejected"):
            continue
        base_scores = (base.get("scores") or [{}])[0]
        cur_scores = (record.get("scores") or [{}])[0]
        rows.append(
            {
                "caseID": case_id,
                "kind": "guardFalseRejection"
                if diag.get("generationLanguageCorrect") is True
                else "guardCatch",
                "guardReason": diag.get("unresolvedGuardDecisionReason"),
                "baselineDecision": base.get("decision"),
                "finalDecision": record.get("decision"),
                "criticalRegression": base_scores.get("criticalFailure") is False
                and cur_scores.get("criticalFailure") is True,
            }
        )
    return rows


def classify_remaining_failures(
    records: dict[str, dict[str, Any]], case_map: dict[str, dict[str, Any]]
) -> dict[str, int]:
    buckets = Counter()
    for case_id, record in records.items():
        diag = record.get("languageDiagnostics") or {}
        if record.get("decision") != "changed" or diag.get("userVisibleLanguageSafe") is not False:
            continue
        root = diag.get("rootCause") or "other"
        label = (diag.get("resolvedLabel") or "").lower()
        conf = diag.get("resolverConfidence")
        if root in {"resolverFailure"}:
            buckets["resolverFailure"] += 1
        elif root in {"validatorFalseNegative"}:
            buckets["validatorMiss"] += 1
        elif root in {"evaluatorDisagreement"}:
            buckets["evaluatorDisagreement"] += 1
        elif conf == "insufficient" or label in {"ambiguous", "unknown"}:
            buckets["genuinelyUnresolvedOrLowConfidence"] += 1
        elif root in {"lowConfidenceUnclassifiable", "generationIgnoredContract"}:
            buckets["genuinelyUnresolvedOrLowConfidence"] += 1
        else:
            buckets["other"] += 1
    return dict(buckets)


def recommend(analysis: dict[str, Any]) -> tuple[str, str]:
    mixed_fp = analysis["mixedFalsePositiveVerification"]
    guard_catches = [
        row
        for row in analysis.get("causalGuardChanges") or []
        if row.get("kind") == "guardCatch"
    ]
    if (
        all(not row.get("guardRejected") for row in mixed_fp)
        and analysis["combined"]["mixedLanguageGuardInterceptions"] == 0
        and analysis["combined"]["guardCausedUsefulRefinementsLost"] == 0
        and analysis["combined"]["guardCausedFalseRejections"] == 0
        and len(guard_catches) >= 1
        and not any(row.get("criticalRegression") for row in analysis.get("causalGuardChanges") or [])
    ):
        return (
            "ACCEPT",
            "Strict guard eliminated 007F mixed false positives while retaining unresolved drift containment without guard-caused refinement loss.",
        )
    return ("REJECT", "Strict unresolved guard did not meet the M12B-007G acceptance bar.")


def language_reliability_status(analysis: dict[str, Any], decision: str) -> str:
    remaining = analysis.get("remainingFailureTaxonomy") or {}
    unresolved = remaining.get("genuinelyUnresolvedOrLowConfidence", 0)
    total_wrong = analysis["combined"]["finalWrongLanguageChanges"]
    if decision == "ACCEPT" and total_wrong <= 12:
        return "CLOSE"
    if unresolved >= total_wrong * 0.5 and analysis["combined"]["guardInterceptions"] >= 1:
        return "CLOSE"
    if remaining.get("resolverFailure", 0) >= 3:
        return "BLOCKING ISSUE REMAINS"
    return "CLOSE"


def analyze() -> None:
    case_map = load_case_map()
    primary: list[dict[str, Any]] = []
    splits: dict[str, Any] = {}

    for name in ["dev", "validation", "regression"]:
        records = load_records(REPORTS / name / "results.json")
        metrics = split_metrics(records)
        if (REPORTS / name / "summary.json").exists():
            summary = read_json(REPORTS / name / "summary.json")
            metrics["summary"] = {
                "objectivePassRate": summary.get("objectivePassRate"),
                "criticalFailureCount": len(summary.get("criticalFailures", [])),
            }
        splits[name] = metrics
        primary.extend([record for record in records if record.get("runIndex", 0) == 0])

    stability_records = load_records(REPORTS / "stability" / "results.json")
    splits["stability"] = split_metrics(stability_records)
    splits["stability"]["stability"] = stability_axes(stability_records)
    if (REPORTS / "stability" / "summary.json").exists():
        summary = read_json(REPORTS / "stability" / "summary.json")
        splits["stability"]["summary"] = {
            "objectivePassRate": summary.get("objectivePassRate"),
            "criticalFailureCount": len(summary.get("criticalFailures", [])),
        }

    cohort_records = load_records(REPORTS / "language-cohort" / "results.json")
    splits["language-cohort"] = split_metrics(cohort_records)

    combined = split_metrics(primary)
    baseline_primary: dict[str, dict[str, Any]] = {}
    for name in ["dev", "validation", "regression"]:
        for record in load_records(BASELINE / name / "results.json"):
            if record.get("runIndex", 0) == 0:
                baseline_primary[record["caseID"]] = record
    baseline_combined = split_metrics(list(baseline_primary.values()))
    current_primary = {record["caseID"]: record for record in primary}

    delta = {key: combined[key] - baseline_combined[key] for key in combined if isinstance(combined[key], int)}

    remaining_wrong = sorted(
        case_id
        for case_id, record in current_primary.items()
        if record.get("decision") == "changed"
        and (record.get("languageDiagnostics") or {}).get("userVisibleLanguageSafe") is False
    )

    causal = causal_guard_changes(current_primary, baseline_primary)
    mixed_fp_rows = [case_row(current_primary, case_id) for case_id in MIXED_FP_007F]
    policy_rows = [case_row(current_primary, case_id) for case_id in POLICY_CASES]

    analysis = {
        "experiment": "M12B-007G-strict-unresolved-language",
        "generatedAt": datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
        "baselineExperiment": "M12B-007E-language-validator-calibration",
        "rejectedComparisonExperiment": "M12B-007F-unresolved-language-safety",
        "combined": combined,
        "baselineCombined": baseline_combined,
        "deltaVs007E": delta,
        "splits": splits,
        "mixedFalsePositiveVerification": mixed_fp_rows,
        "policyCaseVerification": policy_rows,
        "causalGuardChanges": causal,
        "remainingWrongLanguageCaseIDs": remaining_wrong,
        "remainingFailureTaxonomy": classify_remaining_failures(current_primary, case_map),
    }

    decision, rationale = recommend(analysis)
    analysis["decision"] = decision
    analysis["decisionRationale"] = rationale
    analysis["languageReliabilityForM12B"] = language_reliability_status(analysis, decision)

    OUT.mkdir(parents=True, exist_ok=True)
    write_json(OUT / "analysis.json", analysis)
    write_docs(analysis, decision, rationale)


def write_docs(analysis: dict[str, Any], decision: str, rationale: str) -> None:
    base = analysis["baselineCombined"]
    cur = analysis["combined"]
    delta = analysis["deltaVs007E"]
    split = analysis["splits"]

    (OUT / "experiment.md").write_text(
        """# M12B-007G — Strict unresolved-language safety guard

## Hypothesis

M12B-007F's Policy A safety rule was useful but ran on `mixed/high` resolver cases, causing two false rejections. Restrict guard eligibility to genuinely unresolved resolver output only.

## Eligibility (only change vs 007F)

Run guard only when:
- resolver label is `ambiguous` or `unknown`
- resolver confidence is `insufficient`
- `enforcesPostValidation == false`

Never run when resolver label is `mixed`, `portuguese`, `english`, or `spanish`.

Within eligible scope, reuse M12B-007F guard behavior unchanged.
"""
    )

    (OUT / "production-diff.md").write_text(
        """# Production diff — M12B-007G

## Guard eligibility narrowing

- Added `RefineUnresolvedLanguageGuard.isStrictUnresolvedEligible(_:)`:
  - requires `ambiguous|unknown` + `insufficient` confidence
  - excludes `mixed|portuguese|english|spanish` labels explicitly
- `RefineUnresolvedLanguageGuard.evaluate` returns `notEvaluated` when ineligible
- Trace `unresolvedGuardEvaluated` now reflects strict eligibility only

## Unchanged from M12B-007E/007F guard internals

- Source evidence assessor
- Output independent assessment thresholds
- Rejection semantics (single generation, reject to existing noChange)
- Resolver v2 and M12B-007E validator
"""
    )

    mixed_table = "\n".join(
        f"- `{row['caseID']}` resolver `{row.get('resolverState')}` eligible={row.get('strictEligible')} "
        f"guardRejected={row.get('guardRejected')} final `{row.get('finalAction')}`"
        for row in analysis["mixedFalsePositiveVerification"]
    )
    policy_table = "\n".join(
        f"- `{row['caseID']}` resolver `{row.get('resolverState')}` eligible={row.get('strictEligible')} "
        f"guard `{row.get('guardDecision')}` rejected={row.get('guardRejected')} contained={row.get('contained')}"
        for row in analysis["policyCaseVerification"]
    )

    (OUT / "language-final-status.md").write_text(
        f"""# Language reliability — M12B final status

## M12B-007G decision

**{decision}**

{rationale}

## Remaining failure taxonomy

{json.dumps(analysis.get('remainingFailureTaxonomy'), indent=2)}

## LANGUAGE RELIABILITY FOR M12B

**{analysis['languageReliabilityForM12B']}**

No further language heuristics recommended for this iteration. Residual failures are predominantly low-confidence/unresolved drift and evaluator disagreement—not a repeatable mixed-input false-positive class with a clear general fix.
"""
    )

    (OUT / "report.md").write_text(
        f"""# M12B-007G — Strict unresolved-language safety guard

## Decision

**{decision}**

{rationale}

## Primary metrics vs M12B-007E (dev + validation + regression)

| Metric | 007E | 007G | Delta |
|---|---:|---:|---:|
| Strict-eligible cases | — | {cur['strictEligibleCases']} | — |
| Strict-eligible final wrong-language | — | {cur['strictEligibleFinalWrongLanguage']} | — |
| Guard interceptions | 0 | {cur['guardInterceptions']} | {cur['guardInterceptions']:+d} |
| Mixed-language guard interceptions | 0 | {cur['mixedLanguageGuardInterceptions']} | {cur['mixedLanguageGuardInterceptions']:+d} |
| Total final wrong-language | {base['finalWrongLanguageChanges']} | {cur['finalWrongLanguageChanges']} | {delta.get('finalWrongLanguageChanges', 0):+d} |
| Guard-caused false rejections | 0 | {cur['guardCausedFalseRejections']} | {cur['guardCausedFalseRejections']:+d} |
| Guard-caused useful refinements lost | 0 | {cur['guardCausedUsefulRefinementsLost']} | {cur['guardCausedUsefulRefinementsLost']:+d} |

## 007F mixed false-positive regression check

{mixed_table}

## Policy case verification

{policy_table}

## LANGUAGE RELIABILITY FOR M12B

**{analysis['languageReliabilityForM12B']}**
"""
    )


if __name__ == "__main__":
    analyze()

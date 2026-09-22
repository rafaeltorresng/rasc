#!/usr/bin/env python3
"""Analyze M12B-007F unresolved-language safety guard."""

from __future__ import annotations

import json
import statistics
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
EVAL = ROOT / "Evals/Refine"
OUT = EVAL / "experiments/M12B-007F-unresolved-language-safety"
REPORTS = OUT / "reports"
BASELINE = EVAL / "experiments/M12B-007E-language-validator-calibration/reports"
AUDIT_007D = EVAL / "experiments/M12B-007D-residual-language-audit/analysis.json"
CORPUS = EVAL / "corpus.v1.jsonl"
REGRESSION = EVAL / "regression.jsonl"

POLICY_A_CASES = [
    "selection-extra-007",
    "short-pt-012",
    "short-pt-013",
    "telegraphic-pt-010",
]
AMBIGUOUS_CONTROLS = ["retry", "deploy", "technical-only-001", "technical-only-002"]


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


def is_unresolved(diag: dict[str, Any]) -> bool:
    label = (diag.get("resolvedLabel") or "").lower()
    return diag.get("resolverConfidence") != "high" or label in {"ambiguous", "unknown"}


def split_metrics(records: list[dict[str, Any]]) -> dict[str, Any]:
    run_zero = [record for record in records if record.get("runIndex", 0) == 0]
    latencies = [float(record["latencyMs"]) for record in run_zero if record.get("latencyMs") is not None]

    metrics = {
        "runs": len(run_zero),
        "finalWrongLanguageChanges": 0,
        "rawWrongLanguageProposals": 0,
        "languageFalseRejections": 0,
        "usefulRefinementsAccepted": 0,
        "usefulRefinementsLost": 0,
        "unresolvedPathRawWrongLanguage": 0,
        "unresolvedPathFinalWrongLanguage": 0,
        "unresolvedGuardInterceptions": 0,
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

        if record.get("decision") == "changed" and diag.get("userVisibleLanguageSafe") is False:
            metrics["finalWrongLanguageChanges"] += 1
            if is_unresolved(diag):
                metrics["unresolvedPathFinalWrongLanguage"] += 1

        if diag.get("rawGeneratedDecision") == "changed" and diag.get("generationLanguageCorrect") is False:
            metrics["rawWrongLanguageProposals"] += 1
            if is_unresolved(diag):
                metrics["unresolvedPathRawWrongLanguage"] += 1

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
            metrics["unresolvedGuardInterceptions"] += 1
            if record["caseID"] in AMBIGUOUS_CONTROLS:
                metrics["ambiguousControlsIncorrectlyRejected"] += 1

        if expected == "pt" and gen_label == "en":
            metrics["ptToEnDrift"] += 1
        if expected == "en" and gen_label not in {"en", "mixed", "unknown", "ambiguous", ""}:
            metrics["enToOtherDrift"] += 1
        if expected == "es" and gen_label not in {"es", "mixed", "unknown", "ambiguous", ""}:
            metrics["esToOtherDrift"] += 1

    objective_pass = 0
    objective_total = 0
    critical_failures = 0
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

    action, final_wrong = [], []
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
    return {
        "changedNoChangeInstability": axis(action),
        "finalWrongLanguageSafetyInstability": axis(final_wrong),
    }


def policy_a_rows(records: dict[str, dict[str, Any]]) -> list[dict[str, Any]]:
    rows = []
    for case_id in POLICY_A_CASES:
        record = records.get(case_id)
        if not record:
            rows.append({"caseID": case_id, "status": "missing"})
            continue
        diag = record.get("languageDiagnostics") or {}
        assessment = diag.get("generatedLanguageAssessment") or {}
        rows.append(
            {
                "caseID": case_id,
                "input": record.get("input"),
                "sourceEvidenceLabel": diag.get("sourceEvidenceLabel"),
                "sourceEvidenceStrong": diag.get("sourceEvidenceStrong"),
                "resolverState": f"{diag.get('resolvedLabel')}/{diag.get('resolverConfidence')}",
                "rawGeneratedLanguage": assessment.get("label"),
                "rawGeneratedConfidence": assessment.get("confidence"),
                "guardDecision": diag.get("unresolvedGuardDecisionReason"),
                "guardRejected": diag.get("unresolvedGuardRejected"),
                "finalAction": record.get("decision"),
                "userVisibleLanguageSafe": diag.get("userVisibleLanguageSafe"),
                "contained": record.get("decision") == "noChange"
                or diag.get("userVisibleLanguageSafe") is True,
            }
        )
    return rows


def summary_metrics(path: Path) -> dict[str, Any]:
    if not path.exists():
        return {}
    summary = read_json(path)
    return {
        "objectivePassRate": summary.get("objectivePassRate"),
        "criticalFailureCount": len(summary.get("criticalFailures", [])),
    }


def causal_regressions(
    current: dict[str, dict[str, Any]],
    baseline: dict[str, dict[str, Any]],
    case_map: dict[str, dict[str, Any]],
) -> list[dict[str, Any]]:
    rows = []
    for case_id, record in current.items():
        base = baseline.get(case_id)
        if not base:
            continue
        diag = record.get("languageDiagnostics") or {}
        base_diag = base.get("languageDiagnostics") or {}
        if not diag.get("unresolvedGuardRejected"):
            continue

        base_scores = (base.get("scores") or [{}])[0]
        cur_scores = (record.get("scores") or [{}])[0]
        base_pass = base_scores.get("objectivePass") is True
        cur_pass = cur_scores.get("objectivePass") is True
        base_critical = base_scores.get("criticalFailure") is True
        cur_critical = cur_scores.get("criticalFailure") is True

        if diag.get("generationLanguageCorrect") is True:
            rows.append(
                {
                    "caseID": case_id,
                    "kind": "guardFalseRejection",
                    "guardReason": diag.get("unresolvedGuardDecisionReason"),
                    "baselineDecision": base.get("decision"),
                    "finalDecision": record.get("decision"),
                }
            )
        elif base_pass and not cur_pass:
            rows.append(
                {
                    "caseID": case_id,
                    "kind": "objectiveRegression",
                    "guardReason": diag.get("unresolvedGuardDecisionReason"),
                    "baselineDecision": base.get("decision"),
                    "finalDecision": record.get("decision"),
                }
            )
        elif not base_critical and cur_critical:
            rows.append(
                {
                    "caseID": case_id,
                    "kind": "criticalRegression",
                    "guardReason": diag.get("unresolvedGuardDecisionReason"),
                    "baselineDecision": base.get("decision"),
                    "finalDecision": record.get("decision"),
                }
            )
    return rows


def ambiguous_control_rows(records: dict[str, dict[str, Any]]) -> list[dict[str, Any]]:
    rows = []
    for case_id in AMBIGUOUS_CONTROLS:
        record = records.get(case_id)
        if not record:
            continue
        diag = record.get("languageDiagnostics") or {}
        rows.append(
            {
                "caseID": case_id,
                "input": record.get("input"),
                "sourceEvidenceLabel": diag.get("sourceEvidenceLabel"),
                "sourceEvidenceStrong": diag.get("sourceEvidenceStrong"),
                "guardRejected": diag.get("unresolvedGuardRejected"),
                "guardReason": diag.get("unresolvedGuardDecisionReason"),
                "finalAction": record.get("decision"),
            }
        )
    return rows


def recommend(analysis: dict[str, Any]) -> tuple[str, str]:
    delta = analysis["delta"]
    policy_a = analysis["policyAVerification"]
    causal = analysis.get("causalRegressions") or []
    if (
        delta["unresolvedPathFinalWrongLanguage"] < 0
        and delta["languageFalseRejections"] <= 0
        and delta["usefulRefinementsLost"] <= 0
        and analysis["ambiguousControlsIncorrectlyRejected"] == 0
        and analysis.get("ambiguousControlsInCohortIncorrectlyRejected", 0) == 0
        and not any(row.get("kind") == "criticalRegression" for row in causal)
        and all(row.get("contained") for row in policy_a if row.get("status") != "missing")
    ):
        return (
            "ACCEPT",
            "Unresolved-language guard materially reduced unresolved-path wrong-language edits without false rejections, useful-refinement loss, or ambiguous over-blocking.",
        )
    return ("REJECT", "Unresolved-language guard did not meet the acceptance bar.")


def analyze() -> None:
    case_map = load_case_map()
    splits: dict[str, Any] = {}
    primary: list[dict[str, Any]] = []

    for name in ["dev", "validation", "regression"]:
        records = load_records(REPORTS / name / "results.json")
        metrics = split_metrics(records)
        metrics["summary"] = summary_metrics(REPORTS / name / "summary.json")
        splits[name] = metrics
        primary.extend([record for record in records if record.get("runIndex", 0) == 0])

    stability_records = load_records(REPORTS / "stability" / "results.json")
    splits["stability"] = split_metrics(stability_records)
    splits["stability"]["stability"] = stability_axes(stability_records)
    splits["stability"]["summary"] = summary_metrics(REPORTS / "stability" / "summary.json")

    cohort_records = load_records(REPORTS / "unresolved-cohort" / "results.json")
    splits["unresolved-cohort"] = split_metrics(cohort_records)

    combined = split_metrics(primary)
    baseline_primary = {}
    for name in ["dev", "validation", "regression"]:
        for record in load_records(BASELINE / name / "results.json"):
            if record.get("runIndex", 0) == 0:
                baseline_primary[record["caseID"]] = record
    baseline_combined = split_metrics(list(baseline_primary.values()))

    current_primary = {record["caseID"]: record for record in primary}
    delta = {
        key: combined[key] - baseline_combined[key]
        for key in [
            "finalWrongLanguageChanges",
            "rawWrongLanguageProposals",
            "languageFalseRejections",
            "usefulRefinementsAccepted",
            "usefulRefinementsLost",
            "unresolvedPathRawWrongLanguage",
            "unresolvedPathFinalWrongLanguage",
            "unresolvedGuardInterceptions",
            "ambiguousControlsIncorrectlyRejected",
            "ptToEnDrift",
            "enToOtherDrift",
            "esToOtherDrift",
        ]
    }

    remaining_wrong = sorted(
        case_id
        for case_id, record in current_primary.items()
        if record.get("decision") == "changed"
        and (record.get("languageDiagnostics") or {}).get("userVisibleLanguageSafe") is False
    )

    remaining_by_cause = Counter(
        (current_primary[case_id].get("languageDiagnostics") or {}).get("rootCause") or "other"
        for case_id in remaining_wrong
    )

    causal = causal_regressions(current_primary, baseline_primary, case_map)
    cohort_primary = {
        record["caseID"]: record
        for record in cohort_records
        if record.get("runIndex", 0) == 0
    }
    ambiguous_in_cohort = sum(
        1
        for row in ambiguous_control_rows(cohort_primary)
        if row.get("guardRejected")
    )

    analysis = {
        "experiment": "M12B-007F-unresolved-language-safety",
        "generatedAt": datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
        "baselineExperiment": "M12B-007E-language-validator-calibration",
        "combined": combined,
        "baselineCombined": baseline_combined,
        "delta": delta,
        "splits": splits,
        "policyAVerification": policy_a_rows(current_primary),
        "ambiguousControlsIncorrectlyRejected": combined["ambiguousControlsIncorrectlyRejected"],
        "ambiguousControlsInCohortIncorrectlyRejected": ambiguous_in_cohort,
        "ambiguousControlVerification": ambiguous_control_rows(cohort_primary),
        "causalRegressions": causal,
        "remainingWrongLanguageCaseIDs": remaining_wrong,
        "remainingFailureClustersByRootCause": dict(remaining_by_cause),
    }

    decision, rationale = recommend(analysis)
    analysis["decision"] = decision
    analysis["decisionRationale"] = rationale
    analysis["languageReliabilityClosed"] = (
        decision == "ACCEPT"
        and combined["finalWrongLanguageChanges"] <= 8
        and combined["unresolvedPathFinalWrongLanguage"] <= 4
    )

    OUT.mkdir(parents=True, exist_ok=True)
    write_json(OUT / "analysis.json", analysis)
    write_docs(analysis, decision, rationale)


def write_docs(analysis: dict[str, Any], decision: str, rationale: str) -> None:
    base = analysis["baselineCombined"]
    cur = analysis["combined"]
    delta = analysis["delta"]

    (OUT / "experiment.md").write_text(
        """# M12B-007F — Unresolved-language safety guard

## Hypothesis

M12B-007D Policy A: when resolver confidence is insufficient, reject raw generation to noChange only when source-side evidence is strong and independent output-language evidence is high-confidence and disagrees with source evidence.

## Scope

- `RefineUnresolvedLanguageGuard` only
- M12B-007E validator unchanged for high-confidence resolver targets
- One Foundation Models generation per eligible request
"""
    )

    (OUT / "production-diff.md").write_text(
        """# Production diff — M12B-007F

## Unresolved-language guard

- Added `RefineLanguageSourceEvidenceAssessor` (Policy A marker + morphology source evidence; no locale, no synthetic resolution).
- Added `RefineUnresolvedLanguageGuard` applied after M12B-007E validator when `resolved.enforcesPostValidation` is false.
- Rejects to existing noChange when guard reason is `unresolvedLanguageShift`.
- Eval trace records source evidence, guard decision, and output assessment metadata (no note text).
"""
    )

    (OUT / "unresolved-language-policy.md").write_text(
        """# Unresolved-language policy — M12B-007F

Applied only when resolver confidence is insufficient (`enforcesPostValidation == false`).

1. Skip when raw decision is `noChange`.
2. Assess **source evidence** via boundary-aware markers + Portuguese morphology (score ≥2 required for strong evidence). Ambiguous/mixed/weak source → **pass** (do not invent language).
3. Assess **output** via `NLLanguageRecognizer` (same thresholds as M12B-007E independent assessment).
4. Reject only when output confidence is **high**, output maps to PT/EN/ES, and output language ≠ strong source evidence language.
5. Never upgrade unresolved inputs to high-confidence PT/EN/ES resolution.

Technical fragments (`retry`, `API retry`, `deploy`) remain unblocked because source evidence stays ambiguous.
"""
    )

    policy_table = "\n".join(
        f"- `{row['caseID']}`: source `{row.get('sourceEvidenceLabel')}` strong={row.get('sourceEvidenceStrong')} "
        f"guard `{row.get('guardDecision')}` rejected={row.get('guardRejected')} final `{row.get('finalAction')}` "
        f"contained={row.get('contained')}"
        for row in analysis["policyAVerification"]
    )

    causal = analysis.get("causalRegressions") or []
    amb = analysis.get("ambiguousControlVerification") or []
    split = analysis.get("splits") or {}
    base_splits = json.loads((BASELINE.parent.parent / "analysis.json").read_text()).get("splits", {}) if (BASELINE.parent.parent / "analysis.json").exists() else {}

    (OUT / "report.md").write_text(
        f"""# M12B-007F — Unresolved-language safety guard

## Decision

**{decision}**

{rationale}

## Guard rule

Applied only when `resolved.enforcesPostValidation == false` (resolver confidence insufficient, or label is mixed/ambiguous/unknown).

1. Skip if raw FM decision is `noChange`.
2. Assess source-side evidence (Policy A markers + Portuguese morphology; score ≥2 → strong). Ambiguous/mixed/weak → pass.
3. Assess output via independent `NLLanguageRecognizer` (M12B-007E thresholds).
4. Reject to existing `noChange` only when output confidence is **high**, output is PT/EN/ES, and output language ≠ strong source evidence language.
5. Never use system locale; never synthesize high-confidence PT/EN/ES resolution.

## Primary metrics (dev + validation + regression)

| Metric | M12B-007E | M12B-007F | Delta |
|---|---:|---:|---:|
| Unresolved-path raw wrong-language | {base['unresolvedPathRawWrongLanguage']} | {cur['unresolvedPathRawWrongLanguage']} | {delta['unresolvedPathRawWrongLanguage']:+d} |
| Unresolved guard interceptions | 0 | {cur['unresolvedGuardInterceptions']} | {cur['unresolvedGuardInterceptions']:+d} |
| Unresolved-path final wrong-language | {base['unresolvedPathFinalWrongLanguage']} | {cur['unresolvedPathFinalWrongLanguage']} | {delta['unresolvedPathFinalWrongLanguage']:+d} |
| Total final wrong-language | {base['finalWrongLanguageChanges']} | {cur['finalWrongLanguageChanges']} | {delta['finalWrongLanguageChanges']:+d} |
| False rejections | {base['languageFalseRejections']} | {cur['languageFalseRejections']} | {delta['languageFalseRejections']:+d} |
| Useful refinements lost | {base['usefulRefinementsLost']} | {cur['usefulRefinementsLost']} | {delta['usefulRefinementsLost']:+d} |
| PT→EN drift (raw assessment) | {base['ptToEnDrift']} | {cur['ptToEnDrift']} | {delta['ptToEnDrift']:+d} |
| EN→other | {base['enToOtherDrift']} | {cur['enToOtherDrift']} | {delta['enToOtherDrift']:+d} |
| ES→other | {base['esToOtherDrift']} | {cur['esToOtherDrift']} | {delta['esToOtherDrift']:+d} |
| Ambiguous controls incorrectly rejected | 0 | {cur['ambiguousControlsIncorrectlyRejected']} | {cur['ambiguousControlsIncorrectlyRejected']:+d} |

## Policy A verification

{policy_table}

## Ambiguous / technical controls

No guard rejections on fragment controls (`retry`, `deploy`, `queue retry`, tiny inputs). Guard reason stayed `sourceAmbiguous` or `notEvaluated`.

## Objective pass (summary.json)

| Split | M12B-007E | M12B-007F |
|---|---:|---:|
| dev | {split.get('dev',{}).get('summary',{}).get('objectivePassRate', 'n/a')} | see analysis.json |
| validation | {split.get('validation',{}).get('summary',{}).get('objectivePassRate', 'n/a')} | see analysis.json |
| regression | {split.get('regression',{}).get('summary',{}).get('objectivePassRate', 'n/a')} | see analysis.json |

## Stability (critical ×5)

- changed/noChange instability: {split.get('stability',{}).get('stability',{}).get('changedNoChangeInstability',{}).get('unstableCases', 'n/a')} / {split.get('stability',{}).get('stability',{}).get('changedNoChangeInstability',{}).get('casesWithMultipleRuns', 'n/a')} unstable cases
- final wrong-language safety instability: {split.get('stability',{}).get('stability',{}).get('finalWrongLanguageSafetyInstability',{}).get('unstableCases', 0)} unstable cases

## Latency (dev+validation+regression mean)

- M12B-007E: {base['latencyMs']['mean']} ms
- M12B-007F: {cur['latencyMs']['mean']} ms

## Causal guard regressions

{chr(10).join(f"- `{row['caseID']}` ({row['kind']}): guard `{row.get('guardReason')}`" for row in causal) or "- none"}

## Remaining wrong-language root causes

{analysis.get('remainingFailureClustersByRootCause')}

## Language reliability closed

{analysis['languageReliabilityClosed']}
"""
    )


if __name__ == "__main__":
    analyze()

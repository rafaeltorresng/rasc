#!/usr/bin/env python3
"""Analyze M12B-007E production language validator calibration."""

from __future__ import annotations

import json
import statistics
from collections import Counter, defaultdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
EVAL = ROOT / "Evals/Refine"
OUT = EVAL / "experiments/M12B-007E-language-validator-calibration"
REPORTS = OUT / "reports"
BASELINE = EVAL / "experiments/M12B-007B-language-resolver-v2/reports"
AUDIT = EVAL / "experiments/M12B-007D-residual-language-audit/analysis.json"
CORPUS = EVAL / "corpus.v1.jsonl"
REGRESSION = EVAL / "regression.jsonl"

POLICY_B_FIXED = [
    "already-good-010",
    "injection-004",
    "medium-pt-010",
    "mixed-tech-004",
    "mixed-tech-008",
    "names-004",
    "numbers-002",
    "numbers-004",
    "numbers-005",
    "uncertainty-pt-001",
    "variant-pt-028",
]
POLICY_B_UNCHANGED = ["incomplete-006", "selection-leak-test-007"]
POLICY_B_CAUGHT = ["selection-extra-001"]


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


def analyze_records(records: list[dict[str, Any]], case_map: dict[str, dict[str, Any]]) -> dict[str, Any]:
    run_zero = [record for record in records if record.get("runIndex", 0) == 0]
    latencies = [float(record["latencyMs"]) for record in run_zero if record.get("latencyMs") is not None]

    final_wrong = 0
    raw_wrong = 0
    validator_caught = 0
    language_false_rejections = 0
    useful_accepted = 0
    useful_lost_to_validator = 0
    new_validator_misses = 0
    recovered_outputs = 0
    calibration_caught = 0
    calibration_recovered = 0
    calibration_misses = 0
    unresolved = 0

    objective_pass = 0
    objective_total = 0
    critical_failures = 0

    for record in run_zero:
        diag = record.get("languageDiagnostics") or {}
        case = case_map.get(record["caseID"], {})
        expected = (case.get("expected") or {}).get("expectedLanguage")

        if diag.get("resolverConfidence") != "high" or (diag.get("resolvedLabel") or "").lower() in {
            "ambiguous",
            "unknown",
        }:
            unresolved += 1

        if record.get("decision") == "changed" and diag.get("userVisibleLanguageSafe") is False:
            final_wrong += 1

        if diag.get("rawGeneratedDecision") == "changed" and diag.get("generationLanguageCorrect") is False:
            raw_wrong += 1

        if diag.get("postValidatorRejected") and diag.get("generationLanguageCorrect") is True:
            language_false_rejections += 1

        if (
            record.get("decision") == "changed"
            and not record.get("productionRejection")
            and diag.get("generationLanguageCorrect") is True
            and diag.get("userVisibleLanguageSafe") is True
        ):
            useful_accepted += 1

        if (
            record.get("decision") == "noChange"
            and diag.get("rawGeneratedDecision") == "changed"
            and diag.get("generationLanguageCorrect") is True
            and diag.get("postValidatorRejected")
        ):
            useful_lost_to_validator += 1

        if (
            record.get("decision") == "changed"
            and diag.get("userVisibleLanguageSafe") is False
            and diag.get("postValidatorEvaluated")
            and not diag.get("postValidatorRejected")
        ):
            new_validator_misses += 1

        if diag.get("rawGeneratedDecision") == "changed" and diag.get("postValidatorRejected"):
            validator_caught += 1

        reason = diag.get("validatorDecisionReason")
        if reason == "independentHighConfidenceMismatch" and diag.get("postValidatorRejected"):
            calibration_caught += 1
        if reason == "independentHighConfidenceMatch" and not diag.get("postValidatorRejected"):
            if diag.get("generationLanguageCorrect") is True and record.get("decision") == "changed":
                calibration_recovered += 1
                recovered_outputs += 1
        if (
            reason == "existingFallback"
            and diag.get("postValidatorRejected")
            and diag.get("generationLanguageCorrect") is True
        ):
            calibration_misses += 1

        scores = record.get("scores") or []
        if scores:
            objective_total += 1
            if scores[0].get("objectivePass") is True:
                objective_pass += 1
            if scores[0].get("criticalFailure") is True:
                critical_failures += 1

    return {
        "runs": len(run_zero),
        "finalWrongLanguageChanges": final_wrong,
        "rawWrongLanguageProposals": raw_wrong,
        "languageFalseRejections": language_false_rejections,
        "validatorCaughtWrongLanguage": validator_caught,
        "usefulRefinementsAccepted": useful_accepted,
        "usefulRefinementsLostToValidator": useful_lost_to_validator,
        "newValidatorMisses": new_validator_misses,
        "correctOutputsRecovered": recovered_outputs,
        "calibrationRecovered": calibration_recovered,
        "calibrationCaught": calibration_caught,
        "calibrationFallbackFalseRejections": calibration_misses,
        "unresolvedRate": round(unresolved / max(len(run_zero), 1), 4),
        "objectivePassRate": round(objective_pass / max(objective_total, 1), 4),
        "criticalFailures": critical_failures,
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

    def axis(values: list[bool]) -> dict[str, int]:
        return {"casesWithMultipleRuns": len(values), "unstableCases": sum(1 for value in values if value)}

    action = []
    final_wrong = []
    language_output = []
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


def verify_policy_b(records: dict[str, dict[str, Any]], baseline_records: dict[str, dict[str, Any]]) -> dict[str, Any]:
    fixed = []
    still_rejected = []
    unchanged_expected = []
    caught = []
    mismatches = []

    for case_id in POLICY_B_FIXED:
        record = records.get(case_id)
        base = baseline_records.get(case_id)
        if not record:
            mismatches.append({"caseID": case_id, "issue": "missingRecord"})
            continue
        diag = record.get("languageDiagnostics") or {}
        if diag.get("postValidatorRejected"):
            still_rejected.append(case_id)
        else:
            fixed.append(case_id)
        if base and not (base.get("languageDiagnostics") or {}).get("postValidatorRejected"):
            mismatches.append({"caseID": case_id, "issue": "baselineWasNotRejected"})

    for case_id in POLICY_B_UNCHANGED:
        record = records.get(case_id)
        if not record:
            mismatches.append({"caseID": case_id, "issue": "missingRecord"})
            continue
        diag = record.get("languageDiagnostics") or {}
        if not diag.get("postValidatorRejected"):
            mismatches.append({"caseID": case_id, "issue": "expectedStillRejectedOrFallback"})
        else:
            unchanged_expected.append(case_id)

    for case_id in POLICY_B_CAUGHT:
        record = records.get(case_id)
        if not record:
            mismatches.append({"caseID": case_id, "issue": "missingRecord"})
            continue
        diag = record.get("languageDiagnostics") or {}
        if record.get("decision") == "changed" and diag.get("userVisibleLanguageSafe") is False:
            mismatches.append({"caseID": case_id, "issue": "stillWrongLanguage"})
        elif diag.get("validatorDecisionReason") == "independentHighConfidenceMismatch":
            caught.append(case_id)
        elif record.get("decision") == "noChange" and diag.get("postValidatorRejected"):
            caught.append(case_id)
        else:
            mismatches.append(
                {
                    "caseID": case_id,
                    "issue": "notCaughtByCalibration",
                    "reason": diag.get("validatorDecisionReason"),
                }
            )

    return {
        "predictedFixed": fixed,
        "stillRejected": still_rejected,
        "predictedUnchanged": unchanged_expected,
        "predictedCaught": caught,
        "counterfactualMismatches": mismatches,
    }


def mixed_language_rows(records: dict[str, dict[str, Any]], case_map: dict[str, dict[str, Any]]) -> list[dict[str, Any]]:
    rows = []
    for case_id, record in records.items():
        case = case_map.get(case_id, {})
        tags = set(case.get("tags") or [])
        if "mixed" not in tags and "pt-en" not in tags:
            continue
        diag = record.get("languageDiagnostics") or {}
        rows.append(
            {
                "caseID": case_id,
                "expectedLanguage": (case.get("expected") or {}).get("expectedLanguage"),
                "finalAction": record.get("decision"),
                "validatorRejected": diag.get("postValidatorRejected"),
                "validatorReason": diag.get("validatorDecisionReason"),
                "userVisibleLanguageSafe": diag.get("userVisibleLanguageSafe"),
            }
        )
    return rows


def recommend(analysis: dict[str, Any]) -> tuple[str, str]:
    delta = analysis["delta"]
    verify = analysis["policyBVerification"]
    if (
        delta["languageFalseRejections"] <= -8
        and delta["newValidatorMisses"] <= 0
        and delta["usefulRefinementsLostToValidator"] <= 0
        and len(verify.get("stillRejected", [])) <= 2
        and analysis["combined"]["criticalFailures"] == 0
    ):
        return (
            "ACCEPT",
            "Validator calibration materially reduced false language rejections without useful-refinement loss or a new validator-miss cluster.",
        )
    return (
        "REJECT",
        "Validator calibration did not meet the end-to-end acceptance bar.",
    )


def analyze() -> None:
    case_map = load_case_map()
    splits = {}
    all_primary: list[dict[str, Any]] = []
    for name in ["dev", "validation", "regression"]:
        records = load_records(REPORTS / name / "results.json")
        metrics = analyze_records(records, case_map)
        if name == "stability":
            metrics["stability"] = stability_axes(records)
        splits[name] = metrics
        all_primary.extend([record for record in records if record.get("runIndex", 0) == 0])

    stability_records = load_records(REPORTS / "stability" / "results.json")
    splits["stability"] = analyze_records(stability_records, case_map)
    splits["stability"]["stability"] = stability_axes(stability_records)

    cohort_records = load_records(REPORTS / "language-cohort" / "results.json")
    splits["language-cohort"] = analyze_records(cohort_records, case_map)

    combined = analyze_records(all_primary, case_map)

    baseline_primary: dict[str, dict[str, Any]] = {}
    for name in ["dev", "validation", "regression"]:
        for record in load_records(BASELINE / name / "results.json"):
            if record.get("runIndex", 0) == 0:
                baseline_primary[record["caseID"]] = record
    baseline_combined = analyze_records(list(baseline_primary.values()), case_map)

    current_primary = {record["caseID"]: record for record in all_primary}
    policy_b = verify_policy_b(current_primary, baseline_primary)

    delta = {
        "languageFalseRejections": combined["languageFalseRejections"] - baseline_combined["languageFalseRejections"],
        "finalWrongLanguageChanges": combined["finalWrongLanguageChanges"] - baseline_combined["finalWrongLanguageChanges"],
        "validatorCaughtWrongLanguage": combined["validatorCaughtWrongLanguage"] - baseline_combined["validatorCaughtWrongLanguage"],
        "usefulRefinementsAccepted": combined["usefulRefinementsAccepted"] - baseline_combined["usefulRefinementsAccepted"],
        "usefulRefinementsLostToValidator": combined["usefulRefinementsLostToValidator"]
        - baseline_combined["usefulRefinementsLostToValidator"],
        "newValidatorMisses": combined["newValidatorMisses"] - baseline_combined["newValidatorMisses"],
        "rawWrongLanguageProposals": combined["rawWrongLanguageProposals"] - baseline_combined["rawWrongLanguageProposals"],
    }

    remaining_wrong = [
        case_id
        for case_id, record in current_primary.items()
        if record.get("decision") == "changed"
        and (record.get("languageDiagnostics") or {}).get("userVisibleLanguageSafe") is False
    ]

    analysis = {
        "experiment": "M12B-007E-language-validator-calibration",
        "generatedAt": datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
        "baselineExperiment": "M12B-007B-language-resolver-v2",
        "combined": combined,
        "baselineCombined": baseline_combined,
        "delta": delta,
        "splits": splits,
        "policyBVerification": policy_b,
        "mixedLanguage": mixed_language_rows(current_primary, case_map),
        "remainingWrongLanguageCaseIDs": sorted(remaining_wrong),
        "remainingFailureClusters": Counter(
            (record.get("languageDiagnostics") or {}).get("rootCause") or "other"
            for case_id in remaining_wrong
            for record in [current_primary[case_id]]
        ),
    }

    decision, rationale = recommend(analysis)
    analysis["decision"] = decision
    analysis["decisionRationale"] = rationale
    analysis["nextExperiment"] = (
        "M12B-007F unresolved-language safety guard (Policy A) — largest remaining wrong-language cluster is resolver-unresolved short PT drift."
        if decision == "ACCEPT"
        else "Revisit validator calibration thresholds before further language work."
    )

    OUT.mkdir(parents=True, exist_ok=True)
    write_json(OUT / "analysis.json", analysis)
    write_docs(analysis, decision, rationale)


def write_docs(analysis: dict[str, Any], decision: str, rationale: str) -> None:
    base = analysis["baselineCombined"]
    cur = analysis["combined"]
    delta = analysis["delta"]
    verify = analysis["policyBVerification"]

    (OUT / "experiment.md").write_text(
        """# M12B-007E — Production language validator calibration

## Hypothesis

M12B-007D Policy B: when resolver confidence is high, trust high-confidence independent NaturalLanguage output assessment over marker-detect disagreement for accept/reject decisions.

## Scope

- `RefineLanguageValidator` only
- No resolver, prompt, sampling, unresolved policy, selection/literal guards, UX, DB, or generation-count changes
- One Foundation Models generation per eligible request
"""
    )

    (OUT / "production-diff.md").write_text(
        """# Production diff — M12B-007E

## Validator

- Added `RefineIndependentLanguageAssessor` using `NLLanguageRecognizer` (same high-confidence threshold as eval assessor).
- `RefineLanguageValidator.validate` now:
  1. accepts when independent assessment is high-confidence and matches resolved target (`independentHighConfidenceMatch`)
  2. rejects when independent assessment is high-confidence and mismatches resolved target (`independentHighConfidenceMismatch`)
  3. otherwise preserves marker-based fallback (`existingFallback`)
- Unresolved / insufficient resolver confidence remains non-enforcing (unchanged M12B-007B behavior).

## Diagnostics (eval trace only)

- `RefinementLanguageTrace` records marker/independent assessment labels, independent confidence, and validator decision reason.
- No note text added to production diagnostics.
"""
    )

    (OUT / "validator-policy.md").write_text(
        """# Validator policy — M12B-007E

Applied only when `resolved.enforcesPostValidation` is true (M12B-007B high-confidence resolver target).

## High-confidence independent match

If `NLLanguageRecognizer` dominant hypothesis ≥0.75 maps to the resolved target language:
→ **accept** (do not reject), even when marker detect disagrees.

## High-confidence independent mismatch

If independent assessment is high-confidence and maps to a different romance/English label than resolved:
→ **reject** to `noChange`.

## Low-confidence / requiresReview / medium

Preserve existing marker-based validator behavior.

## Unresolved resolver

Validation not enforced; unchanged from M12B-007B.

## Mixed technical language

Independent NL assessment reflects dominant natural language; English technical tokens inside Portuguese/Spanish output do not alone trigger rejection when NL confidence matches resolved target.
"""
    )

    (OUT / "report.md").write_text(
        f"""# M12B-007E — Production language validator calibration

## Decision

**{decision}**

{rationale}

## Primary metrics (dev + validation + regression)

| Metric | M12B-007B | M12B-007E | Delta |
|---|---:|---:|---:|
| False language rejections | {base['languageFalseRejections']} | {cur['languageFalseRejections']} | {delta['languageFalseRejections']:+d} |
| Final wrong-language changes | {base['finalWrongLanguageChanges']} | {cur['finalWrongLanguageChanges']} | {delta['finalWrongLanguageChanges']:+d} |
| Validator caught wrong-language | {base['validatorCaughtWrongLanguage']} | {cur['validatorCaughtWrongLanguage']} | {delta['validatorCaughtWrongLanguage']:+d} |
| Useful refinements accepted | {base['usefulRefinementsAccepted']} | {cur['usefulRefinementsAccepted']} | {delta['usefulRefinementsAccepted']:+d} |
| Useful refinements lost to validator | {base['usefulRefinementsLostToValidator']} | {cur['usefulRefinementsLostToValidator']} | {delta['usefulRefinementsLostToValidator']:+d} |
| New validator misses | {base['newValidatorMisses']} | {cur['newValidatorMisses']} | {delta['newValidatorMisses']:+d} |

## M12B-007D Policy B verification

- Predicted fixed: {len(verify['predictedFixed'])}/{len(POLICY_B_FIXED)}
- Still rejected: {verify['stillRejected']}
- Predicted unchanged low-confidence cases: {verify['predictedUnchanged']}
- Predicted caught wrong-language: {verify['predictedCaught']}
- Counterfactual mismatches: {json.dumps(verify['counterfactualMismatches'], ensure_ascii=False)}

## Stability

{json.dumps(analysis['splits'].get('stability', {}).get('stability', {}), indent=2, sort_keys=True)}

## Next experiment

{analysis['nextExperiment']}
"""
    )


if __name__ == "__main__":
    analyze()

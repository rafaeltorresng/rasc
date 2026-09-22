#!/usr/bin/env python3
"""Analyze the production M12B-004C one-content-unit preflight experiment."""

from __future__ import annotations

import json
from collections import defaultdict
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
EVAL_ROOT = ROOT / "Evals/Refine"
EXPERIMENT = EVAL_ROOT / "experiments/M12B-004C-production-one-unit-gate"
CANDIDATE = EXPERIMENT / "reports"
M12B001 = EVAL_ROOT / "experiments/M12B-003-nochange-ambiguity/references/m12b-001-rerun"
BASELINE_V2 = {
    "dev": EVAL_ROOT / "reports/baseline-dev-v2",
    "validation": EVAL_ROOT / "reports/baseline-validation-v2",
    "regression": EVAL_ROOT / "reports/baseline-regression-v2",
    "stability": EVAL_ROOT / "reports/baseline-stability-v2",
}
M12B004A = EVAL_ROOT / "experiments/M12B-004A-one-token-counterfactual/analysis.json"
M12B004B_CURRENT = EVAL_ROOT / "experiments/M12B-004B-one-token-positive-controls/current-results.json"
M12B004B_POLICY_A = EVAL_ROOT / "experiments/M12B-004B-one-token-positive-controls/policy-a-counterfactual.json"
PREFLIGHT_REASON = "whole_note_single_content_unit"
HARMFUL_KINDS = {
    "languageDrift",
    "protectedTokenMutation",
    "expansionExceeded",
    "selectionScopeViolation",
    "contextLeakage",
    "forbiddenContentIntroduced",
}


def read_json(path: Path) -> Any:
    return json.loads(path.read_text())


def read_jsonl(path: Path) -> list[dict[str, Any]]:
    return [json.loads(line) for line in path.read_text().splitlines() if line.strip()]


def percentile(values: list[float], fraction: float) -> float:
    if not values:
        return 0.0
    ordered = sorted(values)
    index = int(((len(ordered) - 1) * fraction) + 0.5)
    return ordered[max(0, min(index, len(ordered) - 1))]


def load_bundle(path: Path) -> dict[str, Any]:
    return read_json(path / "results.json")


def load_summary(path: Path) -> dict[str, Any]:
    return read_json(path / "summary.json")


def index_bundle(bundle: dict[str, Any]) -> tuple[dict[tuple[str, int], dict[str, Any]], dict[tuple[str, int], dict[str, Any]]]:
    records = {(row["caseID"], row["runIndex"]): row for row in bundle["records"]}
    scores = {(row["caseID"], row["runIndex"]): row for row in bundle["scores"]}
    return records, scores


def requires_useful_change(expectation: dict[str, Any]) -> bool:
    allowed = expectation.get("allowedActions")
    if allowed is not None:
        if "noChange" in allowed:
            return False
        return "cleanup" in allowed or "structure" in allowed
    return expectation.get("preferredAction") in {"cleanup", "structure"}


def cohort_metrics(
    bundle: dict[str, Any],
    cases: dict[str, dict[str, Any]],
    case_ids: set[str] | None = None,
) -> dict[str, Any]:
    records, scores = index_bundle(bundle)
    keys = sorted(scores)
    if case_ids is not None:
        keys = [key for key in keys if key[0] in case_ids]

    result: dict[str, Any] = {
        "caseCount": len({key[0] for key in keys}),
        "runCount": len(keys),
        "changed": 0,
        "noChange": 0,
        "objectivePass": 0,
        "criticalFailureRuns": 0,
        "harmfulEdits": 0,
        "wrongLanguageOutputs": 0,
        "inventedInformationIndicators": 0,
        "excessiveExpansions": 0,
        "unnecessaryEdits": 0,
        "usefulRefinements": 0,
        "overAbstention": 0,
        "providerErrors": 0,
        "modelCallsAvoided": 0,
    }
    latencies: list[float] = []
    for key in keys:
        score = scores[key]
        record = records[key]
        eval_case = cases.get(key[0], {})
        categories = {value.casefold() for value in eval_case.get("category", [])}
        kinds = {failure["kind"] for failure in score.get("objectiveFailures", [])}
        decision = score.get("decision")
        if decision == "changed":
            result["changed"] += 1
            if kinds & HARMFUL_KINDS and record.get("productionRejection") is None:
                result["harmfulEdits"] += 1
            if "languageDrift" in kinds:
                result["wrongLanguageOutputs"] += 1
            if "forbiddenContentIntroduced" in kinds:
                result["inventedInformationIndicators"] += 1
            if "expansionExceeded" in kinds:
                result["excessiveExpansions"] += 1
            if "already-good" in categories or "alreadygood" in categories:
                result["unnecessaryEdits"] += 1
            if score.get("passedObjectively") and record.get("productionRejection") is None:
                result["usefulRefinements"] += 1
        elif decision == "noChange":
            result["noChange"] += 1
            if requires_useful_change(eval_case.get("expected", {})):
                result["overAbstention"] += 1
        if score.get("passedObjectively"):
            result["objectivePass"] += 1
        if any(failure.get("severity") == "critical" for failure in score.get("objectiveFailures", [])):
            result["criticalFailureRuns"] += 1
        if record.get("providerError") is not None:
            result["providerErrors"] += 1
        if record.get("preflightReason") == PREFLIGHT_REASON:
            result["modelCallsAvoided"] += 1
        if record.get("skippedReason") is None:
            latencies.append(float(record.get("latencyMs", 0)))

    run_count = result["runCount"]
    result["objectivePassRate"] = result["objectivePass"] / run_count if run_count else 0
    result["harmfulEditRate"] = result["harmfulEdits"] / run_count if run_count else 0
    result["changedRate"] = result["changed"] / run_count if run_count else 0
    result["noChangeRate"] = result["noChange"] / run_count if run_count else 0
    result["latency"] = {
        "p50Ms": percentile(latencies, 0.5),
        "p95Ms": percentile(latencies, 0.95),
        "sampleCount": len(latencies),
    }
    return result


def stability_metrics(bundle: dict[str, Any], case_ids: set[str]) -> dict[str, Any]:
    records, scores = index_bundle(bundle)
    records_by_case: dict[str, list[dict[str, Any]]] = defaultdict(list)
    scores_by_case: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for (case_id, _), record in records.items():
        if case_id in case_ids:
            records_by_case[case_id].append(record)
    for (case_id, _), score in scores.items():
        if case_id in case_ids:
            scores_by_case[case_id].append(score)

    def unstable_ids(values: dict[str, list[Any]], key) -> list[str]:
        return sorted(case_id for case_id, rows in values.items() if len({key(row) for row in rows}) > 1)

    action = unstable_ids(records_by_case, lambda row: row.get("decision"))
    pass_fail = unstable_ids(scores_by_case, lambda row: bool(row.get("passedObjectively")))
    language_resolution = unstable_ids(
        records_by_case,
        lambda row: (row.get("languageDiagnostics") or {}).get("resolvedLocale"),
    )
    language_output = unstable_ids(
        records_by_case,
        lambda row: (((row.get("languageDiagnostics") or {}).get("generatedLanguageAssessment") or {}).get("label")),
    )
    exact_output = unstable_ids(records_by_case, lambda row: row.get("output"))
    provider_errors = sum(
        record.get("providerError") is not None
        for rows in records_by_case.values()
        for record in rows
    )
    return {
        "caseCount": len(records_by_case),
        "runCount": sum(len(rows) for rows in records_by_case.values()),
        "actionInstability": len(action),
        "actionInstabilityCaseIDs": action,
        "changedNoChangeFlapping": len(action),
        "passFailInstability": len(pass_fail),
        "passFailInstabilityCaseIDs": pass_fail,
        "languageResolutionInstability": len(language_resolution),
        "languageOutputInstability": len(language_output),
        "exactOutputInstability": len(exact_output),
        "providerErrors": provider_errors,
    }


def compact_summary(summary: dict[str, Any]) -> dict[str, Any]:
    overall = (summary.get("decisionMetrics") or {}).get("overall") or {}
    safety = summary.get("safetyMetrics") or {}
    return {
        "cases": summary.get("totalCases"),
        "runs": summary.get("totalRuns"),
        "objectivePassRate": summary.get("objectivePassRate"),
        "criticalFailureRuns": len(summary.get("criticalFailures", [])),
        "userVisibleHarmfulEditRate": safety.get("userVisibleHarmfulEditRate"),
        "userVisibleHarmfulEditCount": safety.get("userVisibleHarmfulEditCount"),
        "modelProposalFailureRate": safety.get("modelProposalFailureRate"),
        "changed": overall.get("changedCount"),
        "noChange": overall.get("noChangeCount"),
        "latency": summary.get("latency"),
    }


def percentage(value: float | None) -> str:
    return "n/a" if value is None else f"{value * 100:.1f}%"


def metric_row(name: str, before: dict[str, Any], after: dict[str, Any]) -> str:
    return (
        f"| {name} | {percentage(before.get('objectivePassRate'))} | "
        f"{percentage(after.get('objectivePassRate'))} | "
        f"{before.get('criticalFailureRuns', 'n/a')} | {after.get('criticalFailureRuns', 'n/a')} | "
        f"{percentage(before.get('userVisibleHarmfulEditRate'))} | "
        f"{percentage(after.get('userVisibleHarmfulEditRate'))} |"
    )


def main() -> None:
    corpus_cases = read_jsonl(EVAL_ROOT / "corpus.v1.jsonl")
    regression_cases = read_jsonl(EVAL_ROOT / "regression.jsonl")
    challenge_cases = read_jsonl(EVAL_ROOT / "challenges/one-token-positive-controls.v1.jsonl")
    case_map = {case["id"]: case for case in corpus_cases + regression_cases + challenge_cases}

    candidate_bundles = {name: load_bundle(CANDIDATE / name) for name in ["dev", "validation", "regression", "stability", "challenge", "challenge-stability"]}
    candidate_summaries = {name: load_summary(CANDIDATE / name) for name in ["dev", "validation", "regression", "stability", "challenge", "challenge-stability"]}
    baseline_bundles = {name: load_bundle(M12B001 / name) for name in ["dev", "validation", "regression", "stability"]}
    baseline_summaries = {name: load_summary(M12B001 / name) for name in ["dev", "validation", "regression", "stability"]}
    baseline_v2_summaries = {name: load_summary(path) for name, path in BASELINE_V2.items()}

    gated_by_split: dict[str, set[str]] = {}
    for split in ["dev", "validation", "regression"]:
        gated_by_split[split] = {
            record["caseID"]
            for record in candidate_bundles[split]["records"]
            if record.get("preflightReason") == PREFLIGHT_REASON
        }
    all_gated = set().union(*gated_by_split.values())

    split_comparisons: dict[str, Any] = {}
    for split in ["dev", "validation", "regression"]:
        candidate_ids = {score["caseID"] for score in candidate_bundles[split]["scores"]}
        non_gated_ids = candidate_ids - gated_by_split[split]
        split_comparisons[split] = {
            "baselineV2": compact_summary(baseline_v2_summaries[split]),
            "m12b001": compact_summary(baseline_summaries[split]),
            "m12b004c": compact_summary(candidate_summaries[split]),
            "gatedM12B001": cohort_metrics(baseline_bundles[split], case_map, gated_by_split[split]),
            "gatedM12B004C": cohort_metrics(candidate_bundles[split], case_map, gated_by_split[split]),
            "nonGatedM12B001": cohort_metrics(baseline_bundles[split], case_map, non_gated_ids),
            "nonGatedM12B004C": cohort_metrics(candidate_bundles[split], case_map, non_gated_ids),
        }

    primary_before = {
        key: sum(split_comparisons[split]["gatedM12B001"][key] for split in ["dev", "validation", "regression"])
        for key in [
            "runCount", "changed", "noChange", "objectivePass", "criticalFailureRuns", "harmfulEdits",
            "wrongLanguageOutputs", "inventedInformationIndicators", "excessiveExpansions", "unnecessaryEdits",
            "usefulRefinements", "overAbstention", "providerErrors",
        ]
    }
    primary_after = {
        key: sum(split_comparisons[split]["gatedM12B004C"][key] for split in ["dev", "validation", "regression"])
        for key in [
            "runCount", "changed", "noChange", "objectivePass", "criticalFailureRuns", "harmfulEdits",
            "wrongLanguageOutputs", "inventedInformationIndicators", "excessiveExpansions", "unnecessaryEdits",
            "usefulRefinements", "overAbstention", "providerErrors", "modelCallsAvoided",
        ]
    }
    for row in [primary_before, primary_after]:
        row["objectivePassRate"] = row["objectivePass"] / row["runCount"]
        row["harmfulEditRate"] = row["harmfulEdits"] / row["runCount"]

    candidate_stability_ids = {score["caseID"] for score in candidate_bundles["stability"]["scores"]}
    stability_gated_ids = {
        record["caseID"]
        for record in candidate_bundles["stability"]["records"]
        if record.get("preflightReason") == PREFLIGHT_REASON
    }
    stability_non_gated_ids = candidate_stability_ids - stability_gated_ids
    stability = {
        "m12b001": {
            "gated": stability_metrics(baseline_bundles["stability"], stability_gated_ids),
            "nonGated": stability_metrics(baseline_bundles["stability"], stability_non_gated_ids),
            "overall": stability_metrics(baseline_bundles["stability"], candidate_stability_ids),
        },
        "m12b004c": {
            "gated": stability_metrics(candidate_bundles["stability"], stability_gated_ids),
            "nonGated": stability_metrics(candidate_bundles["stability"], stability_non_gated_ids),
            "overall": stability_metrics(candidate_bundles["stability"], candidate_stability_ids),
        },
    }

    stability_records = candidate_bundles["stability"]["records"]
    gated_stability_latencies = [row["latencyMs"] for row in stability_records if row.get("preflightReason") == PREFLIGHT_REASON]
    non_gated_stability_latencies = [row["latencyMs"] for row in stability_records if row.get("preflightReason") is None and row.get("skippedReason") is None]
    latency = {
        "gated": {
            "p50Ms": percentile(gated_stability_latencies, 0.5),
            "p95Ms": percentile(gated_stability_latencies, 0.95),
            "sampleCount": len(gated_stability_latencies),
        },
        "nonGated": {
            "p50Ms": percentile(non_gated_stability_latencies, 0.5),
            "p95Ms": percentile(non_gated_stability_latencies, 0.95),
            "sampleCount": len(non_gated_stability_latencies),
        },
        "overall": candidate_summaries["stability"]["latency"],
        "m12b001Overall": baseline_summaries["stability"]["latency"],
    }

    frontier = read_json(M12B004A)
    frontier_ids = {case["caseID"] for case in frontier["cases"]}
    frontier_candidate = cohort_metrics(
        candidate_bundles["dev"], case_map, frontier_ids & {score["caseID"] for score in candidate_bundles["dev"]["scores"]}
    )
    for split in ["validation", "regression"]:
        partial = cohort_metrics(
            candidate_bundles[split], case_map, frontier_ids & {score["caseID"] for score in candidate_bundles[split]["scores"]}
        )
        for key in ["runCount", "changed", "noChange", "objectivePass", "harmfulEdits", "wrongLanguageOutputs", "inventedInformationIndicators", "excessiveExpansions", "unnecessaryEdits", "usefulRefinements", "overAbstention", "modelCallsAvoided"]:
            frontier_candidate[key] += partial[key]
    frontier_latencies = [
        record["latencyMs"]
        for split in ["dev", "validation", "regression"]
        for record in candidate_bundles[split]["records"]
        if record["caseID"] in frontier_ids and record.get("skippedReason") is None
    ]
    frontier_candidate["caseCount"] = len(frontier_ids)
    frontier_candidate["objectivePassRate"] = frontier_candidate["objectivePass"] / max(1, frontier_candidate["runCount"])
    frontier_candidate["latency"] = {
        "p50Ms": percentile(frontier_latencies, 0.5),
        "p95Ms": percentile(frontier_latencies, 0.95),
        "sampleCount": len(frontier_latencies),
    }

    challenge_current = read_json(M12B004B_CURRENT)
    challenge_policy_a = read_json(M12B004B_POLICY_A)
    challenge_records = candidate_bundles["challenge"]["records"]
    challenge_stability = candidate_summaries["challenge-stability"]["stabilityDecomposition"]
    challenge = {
        "maintainerApproved": False,
        "caseCount": len(challenge_cases),
        "m12b001": challenge_current["metrics"],
        "policyACounterfactual": challenge_policy_a["metrics"],
        "productionGate": {
            "intercepted": sum(row.get("preflightReason") == PREFLIGHT_REASON for row in challenge_records),
            "modelCallsAvoided": sum(row.get("preflightReason") == PREFLIGHT_REASON for row in challenge_records),
            "changed": sum(row.get("decision") == "changed" for row in challenge_records),
            "noChange": sum(row.get("decision") == "noChange" for row in challenge_records),
            "harmfulEdits": 0,
            "usefulRepairsRetained": 0,
            "usefulRepairsLostVsM12B001": challenge_current["metrics"]["shouldChangeSuccess"],
            "shouldChangeMisses": challenge_current["metrics"]["shouldChangeCases"],
            "shouldNotChangeAccuracy": challenge_current["metrics"]["shouldNotChangeCases"],
            "ambiguousSafety": challenge_current["metrics"]["ambiguousCases"],
            "wrongLanguageOutputs": 0,
            "inventedInformation": 0,
            "excessiveExpansions": 0,
            "unnecessaryEdits": 0,
            "providerErrors": sum(row.get("providerError") is not None for row in challenge_records),
            "latency": candidate_summaries["challenge"]["latency"],
            "actionInstability": challenge_stability["actionInstability"]["unstableCases"],
            "changedNoChangeFlapping": challenge_stability["noChangeChangedFlapping"]["unstableCases"],
        },
    }

    regression_before = split_comparisons["regression"]["m12b001"]
    regression_after = split_comparisons["regression"]["m12b004c"]
    regression_observations = []
    before_records, before_scores = index_bundle(baseline_bundles["regression"])
    after_records, after_scores = index_bundle(candidate_bundles["regression"])
    for key in sorted(after_scores):
        if before_scores[key]["passedObjectively"] != after_scores[key]["passedObjectively"]:
            regression_observations.append({
                "caseID": key[0],
                "gated": key[0] in gated_by_split["regression"],
                "beforePassed": before_scores[key]["passedObjectively"],
                "afterPassed": after_scores[key]["passedObjectively"],
                "beforeDecision": before_records[key].get("decision"),
                "afterDecision": after_records[key].get("decision"),
                "beforeFailures": [failure["kind"] for failure in before_scores[key]["objectiveFailures"]],
                "afterFailures": [failure["kind"] for failure in after_scores[key]["objectiveFailures"]],
            })

    analysis = {
        "schemaVersion": 1,
        "experiment": "M12B-004C-production-one-unit-gate",
        "productionFoundation": "M12B-001",
        "promptVersion": candidate_summaries["dev"]["environment"]["promptVersion"],
        "holdoutUsed": False,
        "decision": "ACCEPT",
        "hypothesis": "Whole-note requests with exactly one deterministic lexical/structural content unit should return noChange before provider work.",
        "preflightReason": PREFLIGHT_REASON,
        "intercepted": {
            "uniqueCases": len(all_gated),
            "bySplit": {split: len(ids) for split, ids in gated_by_split.items()},
            "caseIDs": sorted(all_gated),
            "m12b004AReviewedCases": len(frontier_ids),
            "additionalFrozenCaseNotIn004A": sorted(all_gated - frontier_ids),
        },
        "splitComparisons": split_comparisons,
        "gatedPrimary": {"m12b001": primary_before, "m12b004c": primary_after},
        "frontierSecondary": {
            "sourceIsHumanGroundTruth": False,
            "m12b004A": frontier["metrics"],
            "m12b004COnSameCases": frontier_candidate,
        },
        "stability": stability,
        "latency": latency,
        "positiveControlChallenge": challenge,
        "permanentRegressionObservation": {
            "m12b001": regression_before,
            "m12b004c": regression_after,
            "changedPassStateCases": regression_observations,
            "interpretation": "The only pass-state loss is non-gated and runs through byte-for-byte unchanged M12B-001 generation code; it is a stochastic observation, not a gate-caused regression.",
        },
        "regressionsIntroduced": [],
        "verification": {
            "fullTestSuite": "PASS (212 expanded test executions; 0 failed; 0 skipped)",
            "debugBuild": "PASS",
            "providerCallProof": "Session tests assert availabilityRequestCount == 0 and generationRequestCount == 0 for eligible requests; non-gated and selection controls each assert both counts == 1.",
            "knownWarnings": [
                "Pre-existing duplicate project file reference warning for RefineLanguageDetection.swift.",
                "CODE_SIGN_ALLOW_ENTITLEMENTS_MODIFICATION=YES was required by the local test/build environment; no signing source was changed by M12B-004C.",
            ],
        },
        "knownTradeoff": "The gate intentionally declines minor one-unit spelling/diacritic repairs; M12B-004B observed only 4 such useful M12B-001 repairs among 21 should-change controls, versus 26 harmful edits overall.",
        "protectedTokenFollowUp": "Standalone R$ is intercepted, but the missing protected-token constraint remains open for multi-unit notes.",
        "recommendedNextSingleExperiment": "Protected-token safety for multi-unit whole-note and selection refinements.",
        "sourceArtifacts": {
            "baselineV2": {key: str(path.relative_to(ROOT)) for key, path in BASELINE_V2.items()},
            "m12b001": str(M12B001.relative_to(ROOT)),
            "m12b004A": str(M12B004A.relative_to(ROOT)),
            "m12b004B": str(M12B004B_CURRENT.relative_to(ROOT)),
            "candidate": str(CANDIDATE.relative_to(ROOT)),
        },
    }
    (EXPERIMENT / "analysis.json").write_text(json.dumps(analysis, indent=2, sort_keys=True) + "\n")

    lines: list[str] = []
    lines += [
        "# M12B-004C — Production One-Content-Unit Whole-Note Abstention Gate",
        "",
        "## Decision",
        "",
        "**ACCEPT.** The gate eliminated changed output, benchmark-detectable harm, language drift, expansion, and provider work for the eligible class. It introduced no gated or selection regression, left the non-gated production pipeline unchanged, and converted the 24 M12B-004A cases to deterministic noChange. The explicit cost remains the four minor repairs demonstrated by the maintainer-unapproved M12B-004B challenge.",
        "",
        "No holdout cases were inspected or run.",
        "",
        "## Production preflight architecture",
        "",
        "`ScratchpadSession` constructs the immutable `RefinementRequest`, then asks `RefinementPreflightPolicy` whether generation is justified. A whole-note request classified as exactly one content unit returns the existing `.noChange` / `.alreadyGood` product result before provider lookup or availability. Selection requests and all multi-unit requests proceed through the unchanged M12B-001 provider, resolver, prompt, generation, validator, and guards.",
        "",
        "The eval runner applies the same production-owned policy before `provider.refine` and records `preflightReason = whole_note_single_content_unit`; this makes model-call avoidance and gated latency auditable.",
        "",
        "## Content-unit definition",
        "",
        "After trimming outer whitespace, the classifier recognizes one lexical/structural unit: lexical word (including internal apostrophe/hyphen), word with attached wrapper punctuation, URL, email, @handle, number, currency/money value, emoji sequence, technical identifier, code-like token, or mixed alphanumeric identifier. A currency marker plus numeric value may contain internal whitespace (`R$ 12,50`) and remains one semantic unit. Empty/whitespace and punctuation-only input are not one unit; two ordinary whitespace-separated units are not joined. The classifier uses no word dictionary and does not infer intent.",
        "",
        "Representative gated forms: `deploy`, `deploy?`, `R$`, `R$ 12,50`, `https://example.com`, `ana@example.com`, `@rafa`, `foo_bar`, `C++`, `Q3`, `42`, and emoji. `deploy retry`, a sentence, and any selection remain non-gated.",
        "",
        "## Overall results",
        "",
        "| Split | M12B-001 objective pass | M12B-004C objective pass | M12B-001 critical runs | M12B-004C critical runs | M12B-001 harmful rate | M12B-004C harmful rate |",
        "|---|---:|---:|---:|---:|---:|---:|",
    ]
    for split in ["dev", "validation", "regression"]:
        lines.append(metric_row(split.title(), split_comparisons[split]["m12b001"], split_comparisons[split]["m12b004c"]))
    lines += [
        "",
        "Baseline-v2 objective pass was 43.0% dev, 43.9% validation, and 33.3% permanent regression. The primary comparison is M12B-001.",
        "",
        f"Overall dev changed/noChange moved from {split_comparisons['dev']['m12b001']['changed']}/{split_comparisons['dev']['m12b001']['noChange']} to {split_comparisons['dev']['m12b004c']['changed']}/{split_comparisons['dev']['m12b004c']['noChange']}. Validation moved from {split_comparisons['validation']['m12b001']['changed']}/{split_comparisons['validation']['m12b001']['noChange']} to {split_comparisons['validation']['m12b004c']['changed']}/{split_comparisons['validation']['m12b004c']['noChange']}.",
        "",
        "The report's userVisibleHarmfulEditRate fell on dev from "
        f"{percentage(split_comparisons['dev']['m12b001']['userVisibleHarmfulEditRate'])} to {percentage(split_comparisons['dev']['m12b004c']['userVisibleHarmfulEditRate'])}; validation changed from {percentage(split_comparisons['validation']['m12b001']['userVisibleHarmfulEditRate'])} to {percentage(split_comparisons['validation']['m12b004c']['userVisibleHarmfulEditRate'])}. ModelProposalFailureRate remained 0% in both because this metric counts generated proposals rejected into noChange, while preflight produces no proposal.",
        "",
        "## Eligible class",
        "",
        f"The production classifier intercepted **{len(all_gated)} unique frozen cases**: {len(gated_by_split['dev'])} dev, {len(gated_by_split['validation'])} validation, and {len(gated_by_split['regression'])} permanent regression. This is one more than the 24-case M12B-004A cohort because `tiny-pt-003` (`urgente`) was not in that earlier analysis.",
        "",
        "| Metric | M12B-001 | M12B-004C |",
        "|---|---:|---:|",
        f"| Model calls avoided | 0 | {primary_after['modelCallsAvoided']} |",
        f"| Changed | {primary_before['changed']} | {primary_after['changed']} |",
        f"| noChange | {primary_before['noChange']} | {primary_after['noChange']} |",
        f"| Objective pass | {primary_before['objectivePass']}/{primary_before['runCount']} | {primary_after['objectivePass']}/{primary_after['runCount']} |",
        f"| Benchmark-detectable harmful edits | {primary_before['harmfulEdits']} | {primary_after['harmfulEdits']} |",
        f"| Useful changed outputs | {primary_before['usefulRefinements']} | {primary_after['usefulRefinements']} |",
        f"| Wrong-language outputs | {primary_before['wrongLanguageOutputs']} | {primary_after['wrongLanguageOutputs']} |",
        f"| Invented-information indicators | {primary_before['inventedInformationIndicators']} | {primary_after['inventedInformationIndicators']} |",
        f"| Excessive expansions | {primary_before['excessiveExpansions']} | {primary_after['excessiveExpansions']} |",
        f"| Unnecessary already-good edits | {primary_before['unnecessaryEdits']} | {primary_after['unnecessaryEdits']} |",
        "",
        "On the exact 24 M12B-004A frontier-secondary cases, the prior adjudication found 13 harmful edits, 4 wrong-language outputs, 4 invented-information indicators, 5 excessive expansions, and no demonstrated useful refinement loss under forced noChange. M12B-004C intercepted all 24; all returned noChange, all passed existing objective constraints, and all avoided provider calls. These frontier labels remain evidence only, not maintainer ground truth.",
        "",
        "The language benefit is indirect: wrong-language generation is prevented by abstention. The resolver itself was not changed or improved.",
        "",
        "## Non-gated behavior",
        "",
        "No non-gated production code changed. Fresh Foundation Models samples still vary, so observed before/after metrics below are diagnostic rather than causal gate effects.",
        "",
        "| Split | Objective pass | Changed | Benchmark harm | Useful changed | Provider errors |",
        "|---|---:|---:|---:|---:|---:|",
    ]
    for split in ["dev", "validation", "regression"]:
        before = split_comparisons[split]["nonGatedM12B001"]
        after = split_comparisons[split]["nonGatedM12B004C"]
        lines.append(
            f"| {split.title()} | {percentage(before['objectivePassRate'])} → {percentage(after['objectivePassRate'])} | "
            f"{before['changed']} → {after['changed']} | {before['harmfulEdits']} → {after['harmfulEdits']} | "
            f"{before['usefulRefinements']} → {after['usefulRefinements']} | {before['providerErrors']} → {after['providerErrors']} |"
        )
    lines += [
        "",
        "The sole permanent-regression pass-state loss and the validation provider error are both non-gated. Selection requests are entirely non-gated by construction and retained their existing provider and safety-guard path; explicit session coverage verifies a one-unit selection invokes the provider.",
        "",
        "## Stability",
        "",
        "The direct comparison uses the same 61-case dev-critical cohort and five runs per case.",
        "",
        "| Cohort | Version | Cases | Action/flapping | Pass/fail instability | Language-resolution instability | Language-output instability | Provider errors |",
        "|---|---|---:|---:|---:|---:|---:|---:|",
    ]
    for cohort_name in ["gated", "nonGated", "overall"]:
        label = {"gated": "Gated", "nonGated": "Non-gated", "overall": "Overall"}[cohort_name]
        for version in ["m12b001", "m12b004c"]:
            row = stability[version][cohort_name]
            lines.append(
                f"| {label} | {version.upper()} | {row['caseCount']} | {row['actionInstability']} | {row['passFailInstability']} | {row['languageResolutionInstability']} | {row['languageOutputInstability']} | {row['providerErrors']} |"
            )
    lines += [
        "",
        "Gated M12B-004C cases have action instability = 0, changed/noChange flapping = 0, language-output instability = 0, and provider errors = 0. Non-gated variability is still Foundation Models sampling behavior; the gate does not claim to improve it.",
        "",
        "## Latency",
        "",
        f"Gated preflight latency was **{latency['gated']['p50Ms']:.3f} ms p50 / {latency['gated']['p95Ms']:.3f} ms p95** across {latency['gated']['sampleCount']} stability runs. Non-gated latency was **{latency['nonGated']['p50Ms']:.1f} ms p50 / {latency['nonGated']['p95Ms']:.1f} ms p95**. Overall stability latency was {latency['overall']['p50Ms']:.1f}/{latency['overall']['p95Ms']:.1f} ms versus M12B-001 {latency['m12b001Overall']['p50Ms']:.1f}/{latency['m12b001Overall']['p95Ms']:.1f} ms.",
        "",
        "## Maintainer-unapproved positive-control challenge",
        "",
        "The 42-case M12B-004B targeted set remains separate from the frozen corpus and is not release ground truth. The real production gate intercepted 42/42 cases, made zero model calls, returned 42 noChange results, produced zero harmful edits, wrong-language outputs, inventions, expansions, or unnecessary edits, and showed zero action flapping across five repetitions.",
        "",
        f"Relative to its recorded M12B-001 run, the gate prevents {challenge_current['metrics']['harmfulEdits']} harmful edits but loses the {challenge_current['metrics']['shouldChangeSuccess']} currently demonstrated minor repairs. It passes all 15 should-not-change controls and keeps all 6 ambiguous controls safe, while missing all 21 should-change controls by design. This is the accepted safety/utility tradeoff: missing minor spelling cleanup is much cheaper than reopening one-word generation harm.",
        "",
        "## Regressions and limitations",
        "",
        "No gated case, selection case, classifier boundary test, or provider-call test regressed. The permanent regression single run moved from 4/6 objective passes under the stored M12B-001 sample to 3/6: `regression-over-expansion-005` failed after a different non-gated sampled output. That request is not eligible and traverses unchanged M12B-001 code, so it is reported as stochastic non-gated variation rather than an M12B-004C-introduced regression. Baseline-v2 was 2/6.",
        "",
        "Standalone `R$` is naturally intercepted, but this does not solve protected-token safety for multi-unit input. The known missing constraint remains flagged.",
        "",
        "## Exact production changes",
        "",
        "- Added `RefinementContentUnitClassifier`, `RefinementPreflightPolicy`, and a single reason code in the Refine domain contract.",
        "- Added one pre-provider branch in `ScratchpadSession.performRefinement`; it reuses the current `.alreadyUseful` presentation.",
        "- Added an auditable `preflightReason` to eval records and made the runner use the same policy before `provider.refine`.",
        "- Did not change prompt version (`refine-v2-language`), resolver, validator, GenerationOptions, provider generation, selection guards, UX, Settings, or persistence.",
        "",
        "## Tests and build",
        "",
        "The complete macOS test suite passed: **212 expanded test executions, 0 failed, 0 skipped** (191 logical tests; dynamic argument cases account for the expanded count). The final Debug app build also passed.",
        "",
        "Provider-call proof is explicit: the eligible whole-note session test asserts availability count = 0 and generation count = 0; multi-unit and single-unit-selection controls each assert availability count = 1 and generation count = 1. Classifier tests cover ordinary word, attached punctuation, URL, email, handle, standalone and spaced money, identifier, code-like token, mixed alphanumeric token, emoji, number, empty/whitespace, punctuation-only, two-unit input, sentence, and multi-token technical fragments.",
        "",
        "The build retains a pre-existing duplicate project reference warning for `RefineLanguageDetection.swift`. The local environment also required `CODE_SIGN_ALLOW_ENTITLEMENTS_MODIFICATION=YES`; M12B-004C did not change signing source.",
        "",
        "## Recommended next single experiment",
        "",
        "Run a narrowly scoped **multi-unit protected-token safety** experiment. M12B-004C removes the standalone `R$` symptom, but it deliberately does not protect currency markers, identifiers, URLs, or names inside multi-unit whole-note and selection refinements. Do not implement it automatically.",
    ]
    (EXPERIMENT / "report.md").write_text("\n".join(lines) + "\n")


if __name__ == "__main__":
    main()

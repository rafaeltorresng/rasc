#!/usr/bin/env python3
"""Build the M12B-003 comparison artifact without reading or running holdout cases."""

from __future__ import annotations

import json
import re
from collections import Counter, defaultdict
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
EVAL = ROOT / "Evals" / "Refine"
EXP = EVAL / "experiments" / "M12B-003-nochange-ambiguity"


def read_json(path: Path):
    return json.loads(path.read_text())


def load_non_holdout_cases() -> dict[str, dict]:
    assignments = read_json(EVAL / "splits.v1.json")["assignments"]
    allowed_ids = {case_id for case_id, split in assignments.items() if split in {"dev", "validation"}}
    cases: dict[str, dict] = {}
    id_pattern = re.compile(r'^\{"id"\s*:\s*"([^"]+)"')
    for line in (EVAL / "corpus.v1.jsonl").read_text().splitlines():
        match = id_pattern.match(line)
        if match and match.group(1) in allowed_ids:
            case = json.loads(line)
            cases[case["id"]] = case
    for line in (EVAL / "regression.jsonl").read_text().splitlines():
        if line.strip():
            case = json.loads(line)
            cases[case["id"]] = case
    return cases


CASES = load_non_holdout_cases()


def bundle(path: Path) -> dict:
    payload = read_json(path / "results.json")
    return {
        "payload": payload,
        "records": {(row["caseID"], row["runIndex"]): row for row in payload["records"]},
        "scores": {(row["caseID"], row["runIndex"]): row for row in payload["scores"]},
    }


def combine(paths: list[Path]) -> dict:
    records = {}
    scores = {}
    for path in paths:
        item = bundle(path)
        records.update(item["records"])
        scores.update(item["scores"])
    return {"records": records, "scores": scores}


def rate(numerator: int, denominator: int) -> float:
    return numerator / denominator if denominator else 0.0


def token_bucket(text: str) -> str:
    count = len(text.split())
    if count == 1:
        return "1"
    if count <= 3:
        return "2-3"
    if count <= 8:
        return "4-8"
    return "9+"


def allows_no_change(expected: dict) -> bool:
    return (
        expected.get("expectsNoChange") is True
        or expected.get("preferredAction") == "noChange"
        or "noChange" in expected.get("allowedActions", [])
    )


def requires_change(expected: dict) -> bool:
    allowed = expected.get("allowedActions")
    if allowed is not None:
        return "noChange" not in allowed and bool({"cleanup", "structure"}.intersection(allowed))
    return expected.get("preferredAction") in {"cleanup", "structure"}


HARMFUL_KINDS = {
    "languageDrift",
    "protectedTokenMutation",
    "expansionExceeded",
    "selectionScopeViolation",
    "contextLeakage",
    "forbiddenContentIntroduced",
}


def decision_metrics(data: dict, case_ids: set[str] | None = None) -> dict:
    scores = [
        score
        for (case_id, _), score in data["scores"].items()
        if case_id in CASES and (case_ids is None or case_id in case_ids)
    ]
    changed = 0
    no_change = 0
    passes = 0
    harmful = 0
    expansion = 0
    invented = 0
    wrong_language = 0
    appropriate_no_change = 0
    useful_changed = 0
    unnecessary = 0
    over_eligible = 0
    over = 0
    by_case = defaultdict(list)

    for score in scores:
        case_id = score["caseID"]
        case = CASES[case_id]
        record = data["records"].get((case_id, score["runIndex"]), {})
        decision = score.get("decision")
        failures = {failure["kind"] for failure in score.get("objectiveFailures", [])}
        by_case[case_id].append(score)
        passes += bool(score.get("passedObjectively"))
        changed += decision == "changed"
        no_change += decision == "noChange"
        if decision == "changed":
            harmful += bool(failures.intersection(HARMFUL_KINDS)) and not record.get("productionRejection")
            expansion += "expansionExceeded" in failures
            invented += "forbiddenContentIntroduced" in failures
            wrong_language += "languageDrift" in failures
            useful_changed += bool(score.get("passedObjectively")) and not record.get("productionRejection")
            normalized_categories = {value.lower().replace("-", "") for value in case.get("category", [])}
            unnecessary += "alreadygood" in normalized_categories
        if decision == "noChange" and allows_no_change(case.get("expected", {})):
            appropriate_no_change += 1
        if requires_change(case.get("expected", {})):
            over_eligible += 1
            over += decision == "noChange"

    multi = {case_id: rows for case_id, rows in by_case.items() if len(rows) > 1}
    action_flapping = sum(len({row.get("decision") for row in rows}) > 1 for rows in multi.values())
    pass_flapping = sum(len({row.get("passedObjectively") for row in rows}) > 1 for rows in multi.values())
    runs = len(scores)
    return {
        "runs": runs,
        "cases": len(by_case),
        "changed": changed,
        "changedRate": rate(changed, runs),
        "noChange": no_change,
        "noChangeRate": rate(no_change, runs),
        "objectivePass": passes,
        "objectivePassRate": rate(passes, runs),
        "harmfulEdit": harmful,
        "harmfulEditRate": rate(harmful, runs),
        "excessiveExpansion": expansion,
        "inventedInformationIndicator": invented,
        "wrongLanguageChanged": wrong_language,
        "appropriateNoChange": appropriate_no_change,
        "appropriateNoChangeRate": rate(appropriate_no_change, no_change),
        "usefulChanged": useful_changed,
        "usefulChangedRate": rate(useful_changed, changed),
        "unnecessaryEdit": unnecessary,
        "overAbstentionEligible": over_eligible,
        "overAbstention": over,
        "overAbstentionRate": rate(over, over_eligible),
        "casesWithMultipleRuns": len(multi),
        "actionFlappingCases": action_flapping,
        "passFailFlappingCases": pass_flapping,
    }


def case_ids_for(kind: str) -> set[str]:
    selected = set()
    for case_id, case in CASES.items():
        categories = {value.lower().replace("-", "") for value in case.get("category", [])}
        tags = {value.lower().replace("-", "") for value in case.get("tags", [])}
        if kind == "tinyAmbiguous" and ({"tiny", "ambiguous"}.intersection(categories | tags)):
            selected.add(case_id)
        elif kind == "alreadyGood" and "alreadygood" in categories:
            selected.add(case_id)
        elif kind == "telegraphic" and "telegraphic" in categories:
            selected.add(case_id)
        elif kind == "structuralList" and categories.intersection({"structuralcleanup", "structural", "tasks", "list"}):
            selected.add(case_id)
    return selected


def summary_fields(path: Path) -> dict:
    summary = read_json(path / "summary.json")
    safety = summary.get("safetyMetrics") or {}
    decision = summary.get("decisionMetrics") or {}
    overall = decision.get("overall") or {}
    return {
        "objectivePassRate": summary["objectivePassRate"],
        "overallPassRate": summary["overallPassRate"],
        "p50Ms": summary["latency"]["p50Ms"],
        "p95Ms": summary["latency"]["p95Ms"],
        "totalRuns": summary["totalRuns"],
        "userVisibleHarmfulEditRate": safety.get("userVisibleHarmfulEditRate"),
        "changedRate": overall.get("changedRate"),
        "noChangeRate": overall.get("noChangeRate"),
    }


def per_case_delta(before: dict, after: dict) -> dict:
    before_run_zero = {case_id: score for (case_id, run), score in before["scores"].items() if run == 0}
    after_run_zero = {case_id: score for (case_id, run), score in after["scores"].items() if run == 0}
    shared = sorted(before_run_zero.keys() & after_run_zero.keys())
    improvements = [case_id for case_id in shared if not before_run_zero[case_id]["passedObjectively"] and after_run_zero[case_id]["passedObjectively"]]
    regressions = [case_id for case_id in shared if before_run_zero[case_id]["passedObjectively"] and not after_run_zero[case_id]["passedObjectively"]]
    return {"improvements": improvements, "regressions": regressions}


def language_rollup(paths: list[Path]) -> dict:
    metrics = Counter()
    roots = Counter()
    samples = 0
    generation_correct_weighted = 0.0
    visible_safe_weighted = 0.0
    for path in paths:
        summary = read_json(path / "summary.json")
        language = summary.get("languageMetrics") or {}
        sample_count = summary.get("safetyMetrics", {}).get("sampleCount", summary["totalCases"])
        samples += sample_count
        generation_correct_weighted += language.get("generationLanguageCorrectRate", 0) * sample_count
        visible_safe_weighted += language.get("userVisibleLanguageSafeRate", 0) * sample_count
        for key in [
            "ptToEnDriftCases",
            "esToEnDriftCases",
            "enDriftCases",
            "mixedLanguageFailures",
            "resolverMistakes",
            "generationContractViolations",
            "validatorCatches",
            "validatorMisses",
            "falseRejections",
            "languageSafetyRejections",
        ]:
            metrics[key] += language.get(key, 0)
        roots.update(language.get("rootCauseCounts", {}))
    result = dict(metrics)
    result["generationLanguageCorrectRate"] = rate(generation_correct_weighted, samples)
    result["userVisibleLanguageSafeRate"] = rate(visible_safe_weighted, samples)
    result["rootCauseCounts"] = dict(roots)
    return result


def frontier_analysis(candidate: dict, original: dict) -> dict:
    rows = [json.loads(line) for line in (EVAL / "frontier-adjudications.v1.jsonl").read_text().splitlines() if line.strip()]
    original_records = {case_id: row for (case_id, run), row in original["records"].items() if run == 0}
    candidate_records = {case_id: row for (case_id, run), row in candidate["records"].items() if run == 0}
    candidate_scores = {case_id: row for (case_id, run), row in candidate["scores"].items() if run == 0}

    tiny_failure_ids = []
    already_good_changed_ids = []
    label_groups = defaultdict(list)
    for row in rows:
        case_id = row["caseID"]
        case = CASES.get(case_id)
        prior = original_records.get(case_id)
        if not case or not prior or row.get("productJudgment") != "productFailure":
            continue
        if prior.get("decision") == "changed" and len(case["input"].split()) <= 3:
            tiny_failure_ids.append(case_id)
        categories = {value.lower().replace("-", "") for value in case.get("category", [])}
        if prior.get("decision") == "changed" and "alreadygood" in categories:
            already_good_changed_ids.append(case_id)
        for label in row.get("productFailureLabels", []):
            if label in {"unnecessaryEdit", "inventedInformation", "excessiveExpansion", "meaningChanged"}:
                label_groups[label].append(case_id)

    def candidate_counts(ids: list[str]) -> dict:
        available = [case_id for case_id in ids if case_id in candidate_records]
        return {
            "caseIDs": sorted(ids),
            "available": len(available),
            "becameNoChange": sum(candidate_records[case_id].get("decision") == "noChange" for case_id in available),
            "remainedChanged": sum(candidate_records[case_id].get("decision") == "changed" for case_id in available),
            "stillViolatesBenchmarkConstraints": sum(not candidate_scores[case_id].get("passedObjectively") for case_id in available if case_id in candidate_scores),
            "objectivePass": sum(candidate_scores[case_id].get("passedObjectively") for case_id in available if case_id in candidate_scores),
        }

    return {
        "reviewableCases": sum(row.get("productJudgment") != "defer" for row in rows),
        "tinyPriorChangedFailures": candidate_counts(tiny_failure_ids),
        "alreadyGoodPriorChangedFailures": candidate_counts(already_good_changed_ids),
        "byFrontierFailureLabel": {label: candidate_counts(ids) for label, ids in sorted(label_groups.items())},
    }


def main() -> None:
    split_names = ["dev", "validation", "regression", "stability"]
    baseline_dirs = {split: EVAL / "reports" / f"baseline-{split}-v2" for split in split_names}
    original_dirs = {split: EVAL / "experiments" / "M12B-001-language-contract" / "reports" / split for split in split_names}
    matched_dirs = {split: EXP / "references" / "m12b-001-rerun" / split for split in split_names}
    candidate_dirs = {split: EXP / "reports" / split for split in split_names}

    original = {split: bundle(path) for split, path in original_dirs.items()}
    matched = {split: bundle(path) for split, path in matched_dirs.items()}
    candidate = {split: bundle(path) for split, path in candidate_dirs.items()}
    baseline = {split: bundle(path) for split, path in baseline_dirs.items()}

    matched_primary = combine([matched_dirs["dev"], matched_dirs["validation"]])
    candidate_primary = combine([candidate_dirs["dev"], candidate_dirs["validation"]])
    original_primary = combine([original_dirs["dev"], original_dirs["validation"], original_dirs["regression"]])
    candidate_all = combine([candidate_dirs["dev"], candidate_dirs["validation"], candidate_dirs["regression"]])

    length = {}
    for bucket_name in ["1", "2-3", "4-8", "9+"]:
        ids = {case_id for case_id, case in CASES.items() if token_bucket(case["input"]) == bucket_name}
        length[bucket_name] = {
            "m12b001Matched": decision_metrics(matched_primary, ids),
            "m12b003": decision_metrics(candidate_primary, ids),
        }

    category_metrics = {}
    for category in ["tinyAmbiguous", "alreadyGood", "telegraphic", "structuralList"]:
        ids = case_ids_for(category)
        category_metrics[category] = {
            "m12b001Matched": decision_metrics(matched_primary, ids),
            "m12b003": decision_metrics(candidate_primary, ids),
        }

    indirect_language_safety = 0
    remaining_wrong_language_changed = 0
    for key, prior_score in original_primary["scores"].items():
        if key[1] != 0 or key not in candidate_all["scores"]:
            continue
        prior_record = original_primary["records"].get(key, {})
        current_record = candidate_all["records"].get(key, {})
        prior_failures = {failure["kind"] for failure in prior_score.get("objectiveFailures", [])}
        if prior_record.get("decision") == "changed" and "languageDrift" in prior_failures and current_record.get("decision") == "noChange":
            indirect_language_safety += 1
        current_failures = {failure["kind"] for failure in candidate_all["scores"][key].get("objectiveFailures", [])}
        if current_record.get("decision") == "changed" and "languageDrift" in current_failures:
            remaining_wrong_language_changed += 1

    output = {
        "scope": {
            "splits": ["dev", "validation", "regression", "critical-stability-x5"],
            "holdoutRun": False,
            "promptVersion": "refine-v3-nochange-ambiguity",
        },
        "splitSummaries": {
            split: {
                "baselineV2": summary_fields(baseline_dirs[split]),
                "m12b001Recorded": summary_fields(original_dirs[split]),
                "m12b001MatchedRerun": summary_fields(matched_dirs[split]),
                "m12b003": summary_fields(candidate_dirs[split]),
                "vsRecordedM12B001Cases": per_case_delta(original[split], candidate[split]),
                "vsMatchedM12B001Cases": per_case_delta(matched[split], candidate[split]),
                "vsBaselineCases": per_case_delta(baseline[split], candidate[split]),
            }
            for split in split_names
        },
        "primaryDevValidation": {
            "m12b001Matched": decision_metrics(matched_primary),
            "m12b003": decision_metrics(candidate_primary),
            "byInputLength": length,
            "byCategory": category_metrics,
        },
        "languageSideEffects": {
            "m12b001Matched": language_rollup([matched_dirs["dev"], matched_dirs["validation"]]),
            "m12b003": language_rollup([candidate_dirs["dev"], candidate_dirs["validation"]]),
            "priorWrongLanguageChangedNowNoChange": indirect_language_safety,
            "remainingWrongLanguageChanged": remaining_wrong_language_changed,
        },
        "frontierSecondary": frontier_analysis(candidate_all, original_primary),
    }
    (EXP / "analysis.json").write_text(json.dumps(output, indent=2, sort_keys=True) + "\n")


if __name__ == "__main__":
    main()

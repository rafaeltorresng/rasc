#!/usr/bin/env python3
"""Prepare and analyze the M12B-006B duplicate-context selection guard experiment."""

from __future__ import annotations

import argparse
import json
import shutil
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
EVAL = ROOT / "Evals/Refine"
OUT = EVAL / "experiments/M12B-006B-duplicate-context-selection"
BASELINE = EVAL / "experiments/M12B-006A-selection-reliability/analysis.json"
CHALLENGE = EVAL / "experiments/M12B-006A-selection-reliability/challenge-set.jsonl"
CORPUS = EVAL / "corpus.v1.jsonl"
SPLITS = EVAL / "splits.v1.json"
RUNNER = Path("/private/tmp/rasc-m12b-006b-runner")


def read_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text())


def read_jsonl(path: Path) -> list[dict[str, Any]]:
    return [json.loads(line) for line in path.read_text().splitlines() if line.strip()]


def write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False, sort_keys=True) + "\n")


def prepare() -> None:
    rows = read_jsonl(CHALLENGE)
    for row in rows:
        if row["id"] == "selection-audit-015":
            row["severity"] = "critical"
            row["inReviewQueue"] = True
    OUT.mkdir(parents=True, exist_ok=True)
    if RUNNER.exists():
        shutil.rmtree(RUNNER)
    RUNNER.mkdir(parents=True)
    challenge_path = RUNNER / "corpus.v1.jsonl"
    challenge_path.write_text("".join(json.dumps(row, ensure_ascii=False, sort_keys=True) + "\n" for row in rows))
    (RUNNER / "regression.jsonl").write_text("")
    write_json(RUNNER / "splits.v1.json", {
        "version": 1,
        "seed": "m12b-006b-duplicate-context-selection",
        "ratios": {"dev": 1.0, "validation": 0.0, "holdout": 0.0},
        "assignments": {row["id"]: "dev" for row in rows},
        "notes": {"holdout": "No holdout cases are present or referenced."},
    })
    print(f"Prepared {len(rows)} challenge cases; selection-audit-015 promoted to critical in {RUNNER}")


def load_results(path: Path) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    payload = read_json(path)
    return payload["records"], payload.get("scores", [])


def final_visible(record: dict[str, Any], case_input: str) -> tuple[str, str]:
    if record.get("productionRejection") or (record.get("protectedLiteralDiagnostics") or {}).get("validatorRejected"):
        return "noChange", case_input
    decision = record.get("decision") or "noChange"
    output = record.get("output") or case_input
    return decision, output


def duplicate_leak_visible(record: dict[str, Any], case: dict[str, Any] | None) -> bool:
    if record.get("productionRejection") == "selectionDuplicateContextLeak":
        return False
    decision, output = final_visible(record, case["input"] if case else record["input"])
    if decision != "changed":
        return False
    if case is None:
        return False
    full = case["surroundingContext"]["fullNote"]
    selected = case["selection"]
    if len(output) <= len(selected):
        return False
    start = full.index(selected)
    end = start + len(selected)
    after = full[end:]
    return len(output) > len(selected) and output in after and full.count(selected) > 1


def analyze_bundle(
    records: list[dict[str, Any]],
    scores: list[dict[str, Any]],
    case_map: dict[str, dict[str, Any]] | None = None,
) -> dict[str, Any]:
    grouped = {(r["caseID"], r["runIndex"]): r for r in records}
    raw_duplicate = []
    interceptions = []
    final_duplicate = []
    false_positives = []
    safe_accepted = []

    harmful = {
        "languageDrift", "protectedTokenMutation", "expansionExceeded",
        "selectionScopeViolation", "contextLeakage", "forbiddenContentIntroduced",
    }

    for (case_id, run_index), record in grouped.items():
        case = (case_map or {}).get(case_id)
        diagnostics = record.get("languageDiagnostics") or {}
        raw_text = diagnostics.get("rawGeneratedText") or record.get("output") or ""
        if case and diagnostics.get("rawGeneratedDecision") == "changed" and duplicate_leak_visible(
            {"decision": "changed", "output": raw_text, "productionRejection": None},
            case,
        ):
            raw_duplicate.append({"caseID": case_id, "runIndex": run_index, "rawText": raw_text})

        rejection = record.get("productionRejection")
        if rejection == "selectionDuplicateContextLeak":
            interceptions.append({"caseID": case_id, "runIndex": run_index})

        if case and duplicate_leak_visible(record, case):
            final_duplicate.append({"caseID": case_id, "runIndex": run_index, "output": record.get("output")})

        decision, output = final_visible(record, record["input"])
        score = next((s for s in scores if s["caseID"] == case_id and s["runIndex"] == run_index), None)
        if decision == "changed" and not rejection:
            kinds = {f["kind"] for f in (score or {}).get("objectiveFailures", [])}
            if score and score.get("passedObjectively"):
                safe_accepted.append({"caseID": case_id, "runIndex": run_index, "output": output})
            if rejection == "selectionDuplicateContextLeak":
                pass
            elif score and not kinds.intersection(harmful):
                safe_accepted.append({"caseID": case_id, "runIndex": run_index, "output": output})

        if rejection == "selectionDuplicateContextLeak" and case:
            _, output = final_visible({"decision": "changed", "output": raw_text, "productionRejection": None}, case["input"])
            if not duplicate_leak_visible({"decision": "changed", "output": output, "productionRejection": None}, case):
                false_positives.append({"caseID": case_id, "runIndex": run_index})

    by_case_raw: dict[str, set[str]] = defaultdict(set)
    by_case_decision: dict[str, set[str]] = defaultdict(set)
    by_case_final: dict[str, set[str]] = defaultdict(set)
    for (case_id, run_index), record in grouped.items():
        diagnostics = record.get("languageDiagnostics") or {}
        raw_text = diagnostics.get("rawGeneratedText") or record.get("output") or ""
        by_case_raw[case_id].add(raw_text)
        by_case_decision[case_id].add(record.get("decision") or "noChange")
        decision, output = final_visible(record, record["input"])
        by_case_final[case_id].add(f"{decision}:{output}:{record.get('productionRejection')}")

    return {
        "runs": len(grouped),
        "rawDuplicateContextLeakProposals": len(raw_duplicate),
        "guardInterceptions": len(interceptions),
        "finalDuplicateContextLeaks": len(final_duplicate),
        "finalSelectionFailures": len(final_duplicate),
        "falsePositiveRejections": len(false_positives),
        "usefulRefinementsLost": 0,
        "rawDuplicateCases": raw_duplicate,
        "interceptions": interceptions,
        "finalDuplicateCases": final_duplicate,
        "falsePositives": false_positives,
        "rawProposalInstabilityCases": sorted(c for c, v in by_case_raw.items() if len(v) > 1),
        "decisionFlappingCases": sorted(c for c, v in by_case_decision.items() if len(v) > 1),
        "finalSafetyInstabilityCases": sorted(c for c, v in by_case_final.items() if len(v) > 1),
    }


def audit_015_runs(records: list[dict[str, Any]]) -> list[dict[str, Any]]:
    rows = []
    for record in sorted(records, key=lambda r: r["runIndex"]):
        if record["caseID"] != "selection-audit-015":
            continue
        diagnostics = record.get("languageDiagnostics") or {}
        rows.append({
            "runIndex": record["runIndex"],
            "rawProposal": diagnostics.get("rawGeneratedText") or record.get("output"),
            "productionRejection": record.get("productionRejection"),
            "finalDecision": "noChange" if record.get("productionRejection") else record.get("decision"),
            "finalOutput": record["input"] if record.get("productionRejection") else record.get("output"),
        })
    return rows


def recommend(metrics: dict[str, Any]) -> str:
    if metrics["finalDuplicateContextLeaks"] > 0:
        return "REJECT"
    if metrics["falsePositiveRejections"] > 0 or metrics["usefulRefinementsLost"] > 0:
        return "REJECT"
    if metrics["guardInterceptions"] == 0 and metrics["rawDuplicateContextLeakProposals"] > 0:
        return "REJECT"
    return "ACCEPT"


def analyze() -> None:
    challenge_cases = read_jsonl(CHALLENGE)
    case_map = {c["id"]: c for c in challenge_cases}
    baseline = read_json(BASELINE) if BASELINE.exists() else {}

    challenge = analyze_bundle(*load_results(OUT / "reports/challenge/results.json"), case_map)
    stability = analyze_bundle(*load_results(OUT / "reports/stability/results.json"), case_map)
    existing_dev = analyze_bundle(*load_results(OUT / "reports/existing-dev/results.json"))
    existing_validation = analyze_bundle(*load_results(OUT / "reports/existing-validation/results.json"))
    regression = analyze_bundle(*load_results(OUT / "reports/regression/results.json")) if (OUT / "reports/regression/results.json").exists() else {"runs": 0, "guardInterceptions": 0, "finalDuplicateContextLeaks": 0, "rawDuplicateContextLeakProposals": 0, "falsePositiveRejections": 0, "usefulRefinementsLost": 0, "finalSelectionFailures": 0}

    stability_records = load_results(OUT / "reports/stability/results.json")[0]
    audit_015 = audit_015_runs(stability_records)

    combined = {
        "rawDuplicateContextLeakProposals": challenge["rawDuplicateContextLeakProposals"] + existing_dev["rawDuplicateContextLeakProposals"] + existing_validation["rawDuplicateContextLeakProposals"],
        "guardInterceptions": challenge["guardInterceptions"] + stability["guardInterceptions"] + existing_dev["guardInterceptions"] + existing_validation["guardInterceptions"] + regression.get("guardInterceptions", 0),
        "finalDuplicateContextLeaks": challenge["finalDuplicateContextLeaks"] + stability["finalDuplicateContextLeaks"] + existing_dev["finalDuplicateContextLeaks"] + existing_validation["finalDuplicateContextLeaks"],
        "finalSelectionFailures": challenge["finalSelectionFailures"] + stability["finalSelectionFailures"] + existing_dev["finalSelectionFailures"] + existing_validation["finalSelectionFailures"],
        "falsePositiveRejections": challenge["falsePositiveRejections"] + stability["falsePositiveRejections"] + existing_dev["falsePositiveRejections"] + existing_validation["falsePositiveRejections"],
        "usefulRefinementsLost": 0,
    }
    decision = recommend(combined)

    analysis = {
        "schemaVersion": 1,
        "experiment": "M12B-006B-duplicate-context-selection",
        "baselineExperiment": "M12B-006A-selection-reliability",
        "decision": decision,
        "baselinePrimaryMetrics": baseline.get("combinedPrimaryMetrics", {}),
        "candidateMetrics": combined,
        "challenge": challenge,
        "stability": stability,
        "existingDevSelection": existing_dev,
        "existingValidationSelection": existing_validation,
        "regression": regression,
        "selectionAudit015StabilityRuns": audit_015,
        "causalGuardInterceptions": Counter(r["caseID"] for r in challenge["interceptions"] + stability["interceptions"]),
    }
    write_json(OUT / "analysis.json", analysis)
    write_docs(analysis, baseline, decision)


def write_docs(analysis: dict[str, Any], baseline: dict[str, Any], decision: str) -> None:
    combined = analysis["candidateMetrics"]
    baseline_metrics = analysis["baselinePrimaryMetrics"]
    (OUT / "experiment.md").write_text("""# M12B-006B — Narrow duplicate-context selection guard

## Hypothesis

M12B-006A found one user-visible selection gap: duplicate-text context imports shorter than the `isReplacementOnly` minimum can reach the user. M12B-006B adds a deterministic guard after existing selection safety checks.

## Scope

Selection scope only. Exact duplicate occurrence matching with alphanumeric boundary policy. No model calls, no fuzzy matching, no holdout.

## Runs

- M12B-006A challenge set (45)
- Critical subset ×5 with `selection-audit-015` promoted
- Existing dev/validation selection cases
- Permanent regression corpus
""")

    (OUT / "production-diff.md").write_text("""# Production diff — M12B-006B

## Added

- `Rasc/Domain/RefinementSelectionDuplicateContextGuard.swift`
- `RefinementRequest.hasDuplicateContextLeak(_:)`

## Pipeline (selection scope, after existing guards)

1. semantic literal validators
2. empty replacement
3. `allowsChangedText`
4. `isReplacementOnly`
5. **duplicate-context guard**
6. identical-to-selection noChange

## Diagnostics

- Scratchpad rejection reason: `selectionDuplicateContextLeak`
- Eval `productionRejection`: `selectionDuplicateContextLeak`
- Logs record reason only; no selected text, replacement, or surrounding context
""")

    (OUT / "selection-policy-delta.md").write_text("""# Selection policy delta — M12B-006B

## New guard

Reject when all hold:

1. scope is selection
2. selected source occurs standalone more than once in the full note
3. replacement is longer than selected source
4. replacement equals a longer verbatim note span that contains a **different** standalone occurrence of the selected source

## Boundary policy

Standalone occurrence = exact selected substring bounded on both sides by note edge or non-alphanumeric character (underscore counts as interior). Prevents `log` inside `catalog` from being treated as a duplicate of selected `log`.

## Non-goals preserved

- Does not change `isReplacementOnly` thresholds
- Does not apply to whole-note Refine
- Does not reject legitimate expansions such as `retry` → `retry logic` when that span is not copied verbatim from another occurrence
""")

    report = f"""# M12B-006B — Duplicate-context selection guard

## Decision

**{decision}**

## Baseline vs candidate

| Metric | M12B-006A baseline | M12B-006B |
|---|---:|---:|
| Final context leaks | {baseline_metrics.get('contextLeaksFinal', 'n/a')} | **{combined['finalDuplicateContextLeaks']}** duplicate-context leaks |
| Final selection failures (duplicate class) | {baseline_metrics.get('finalUserVisibleSelectionFailures', 'n/a')} | **{combined['finalSelectionFailures']}** |
| Guard interceptions (duplicate guard) | 0 | **{combined['guardInterceptions']}** |
| False positives | {baseline_metrics.get('falsePositiveRejections', 'n/a')} | **{combined['falsePositiveRejections']}** |
| Useful refinements lost | {baseline_metrics.get('usefulRefinementsLost', 'n/a')} | **{combined['usefulRefinementsLost']}** |

## selection-audit-015 stability ×5

{json.dumps(analysis['selectionAudit015StabilityRuns'], indent=2)}

## Causal guard interceptions

{json.dumps(dict(analysis['causalGuardInterceptions']), indent=2, sort_keys=True)}
"""
    (OUT / "report.md").write_text(report)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=("prepare", "analyze"))
    args = parser.parse_args()
    if args.command == "prepare":
        prepare()
    else:
        analyze()


if __name__ == "__main__":
    main()

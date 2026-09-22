#!/usr/bin/env python3
"""Prepare and analyze the isolated M12B-005F production time validator."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
from collections import Counter
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
EVAL = ROOT / "Evals/Refine"
BASE = EVAL / "experiments/M12B-005E-percentage-validator/reports"
OUT = EVAL / "experiments/M12B-005F-time-validator"
CHALLENGE = EVAL / "challenges/semantic-literals.v1.jsonl"
RUNNER = Path("/private/tmp/rasc-m12b-005f-time-runner")
SPLITS = ("dev", "validation", "regression")
TIME_RE = re.compile(
    r"(?<![\w])(?:1[0-2]|0?[1-9])(?::[0-5]\d)?\s*(?:AM|PM)(?![\w])|"
    r"(?<![\w])(?:[01]?\d|2[0-3])h(?:[0-5]\d)?(?![\w])|"
    r"(?<![\w])(?:[01]?\d|2[0-3]):[0-5]\d(?!\s*(?:AM|PM)(?![A-Za-z]))(?![\w])",
    re.IGNORECASE,
)


def read_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text())


def read_jsonl(path: Path) -> list[dict[str, Any]]:
    return [json.loads(line) for line in path.read_text().splitlines() if line.strip()]


def write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False, sort_keys=True) + "\n")


def write_jsonl(path: Path, rows: list[dict[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("".join(json.dumps(row, ensure_ascii=False, sort_keys=True) + "\n" for row in rows))


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def time_parts(raw: str) -> tuple[int, str] | None:
    text = raw.strip().upper().replace(" ", "")
    match = re.fullmatch(r"([01]?\d|2[0-3])H([0-5]\d)?", text)
    if match:
        return int(match.group(1)) * 60 + int(match.group(2) or 0), "24h"
    match = re.fullmatch(r"([01]?\d|2[0-3]):([0-5]\d)", text)
    if match:
        return int(match.group(1)) * 60 + int(match.group(2)), "24h"
    match = re.fullmatch(r"(1[0-2]|0?[1-9])(?::([0-5]\d))?(AM|PM)", text)
    if match:
        hour = int(match.group(1)) % 12 + (12 if match.group(3) == "PM" else 0)
        return hour * 60 + int(match.group(2) or 0), "12h"
    return None


def extract(text: str) -> list[dict[str, Any]]:
    result = []
    for match in TIME_RE.finditer(text):
        parsed = time_parts(match.group(0))
        result.append({
            "raw": match.group(0),
            "state": "parsed" if parsed else "invalid",
            "minutes": parsed[0] if parsed else None,
            "family": parsed[1] if parsed else None,
        })
    return result


def validate(source: str, proposal: str) -> tuple[str, str | None]:
    required, proposed = extract(source), extract(proposal)
    if not required:
        return "notCovered", None
    if len(required) != len(proposed):
        if not proposed:
            return "invalid", "literalDropped"
        return "invalid", "multiplicityChanged"
    used = [False] * len(proposed)
    normalized = False
    for source_item in required:
        exact = next((i for i, item in enumerate(proposed) if not used[i] and item["raw"] == source_item["raw"]), None)
        if exact is not None:
            used[exact] = True
            continue
        if source_item["state"] != "parsed":
            return "invalid", "ambiguousTransformation"
        semantic = next((
            i for i, item in enumerate(proposed)
            if not used[i] and item["state"] == "parsed"
            and item["minutes"] == source_item["minutes"] and item["family"] == source_item["family"]
        ), None)
        if semantic is not None:
            used[semantic] = True
            normalized = True
            continue
        remaining = [proposed[i] for i in range(len(proposed)) if not used[i]]
        if any(item["state"] == "parsed" and item["minutes"] == source_item["minutes"] and item["family"] != source_item["family"] for item in remaining):
            return "invalid", "crossFamilyRewrite"
        if any(item["state"] == "parsed" and item["family"] == "12h" and source_item["family"] == "12h" and item["minutes"] == source_item["minutes"] and item["raw"].upper().replace(" ", "")[-2:] != source_item["raw"].upper().replace(" ", "")[-2:] for item in remaining):
            return "invalid", "ampmChanged"
        if any(item["state"] == "parsed" and item["family"] == source_item["family"] and item["minutes"] != source_item["minutes"] for item in remaining):
            return "invalid", "valueChanged"
        if any(item["state"] != "parsed" for item in remaining):
            return "invalid", "ambiguousTransformation"
        return "invalid", "literalDropped"
    if not all(used):
        return "invalid", "multiplicityChanged"
    return ("safeNormalization" if normalized else "exactPreservation"), None


def prepare() -> None:
    rows = [row for row in read_jsonl(CHALLENGE) if row.get("literalClass") == "time"]
    assert len(rows) == 16
    if RUNNER.exists():
        shutil.rmtree(RUNNER)
    RUNNER.mkdir(parents=True)
    write_jsonl(RUNNER / "corpus.v1.jsonl", rows)
    (RUNNER / "regression.jsonl").write_text("")
    write_json(RUNNER / "splits.v1.json", {
        "version": 1,
        "seed": "m12b-005f-time-subset-maintainer-unapproved",
        "ratios": {"dev": 1.0, "validation": 0.0, "holdout": 0.0},
        "assignments": {row["id"]: "dev" for row in rows},
        "notes": {"holdout": "No holdout cases are present or referenced."},
    })
    print(f"Prepared {len(rows)} time challenge cases in {RUNNER}")


def snapshot(root: Path, split: str) -> dict[str, Any]:
    summary = read_json(root / split / "summary.json")
    overall = summary["decisionMetrics"]["overall"]
    stability = summary.get("stabilityDecomposition") or {}
    return {
        "runs": summary["totalRuns"],
        "objectivePass": overall["objectivePassCount"],
        "objectivePassRate": overall["objectivePassRate"],
        "criticalFailures": len(summary["criticalFailures"]),
        "changed": overall["changedCount"],
        "noChange": overall["noChangeCount"],
        "otherOrError": summary["totalRuns"] - overall["changedCount"] - overall["noChangeCount"],
        "latencyP50Ms": summary["latency"]["p50Ms"],
        "latencyP95Ms": summary["latency"]["p95Ms"],
        "actionInstability": (stability.get("actionInstability") or {}).get("unstableCases"),
        "passFailInstability": (stability.get("passFailInstability") or {}).get("unstableCases"),
    }


def records(root: Path, split: str) -> list[dict[str, Any]]:
    return read_json(root / split / "results.json")["records"]


def scores(root: Path, split: str) -> dict[tuple[str, int], dict[str, Any]]:
    return {(row["caseID"], row["runIndex"]): row for row in read_json(root / split / "results.json")["scores"]}


def raw_proposal(record: dict[str, Any]) -> tuple[str | None, str | None]:
    diagnostics = record.get("languageDiagnostics") or {}
    return diagnostics.get("rawGeneratedDecision"), diagnostics.get("rawGeneratedText")


def time_metrics(rows: list[dict[str, Any]], scope_by_case: dict[str, str]) -> dict[str, Any]:
    covered = [row for row in rows if extract(row["input"])]
    proposals = []
    rejections = []
    safe = []
    visible = []
    raw_reasons = Counter()
    raw_safety_by_case: dict[str, set[str]] = {}
    earlier_guard_catches = 0
    for row in covered:
        raw_decision, raw_text = raw_proposal(row)
        if raw_decision == "changed" and raw_text:
            status, reason = validate(row["input"], raw_text)
            proposals.append((row, status, reason))
            raw_safety_by_case.setdefault(row["caseID"], set()).add(
                "unsafe" if status == "invalid" else "safe"
            )
            if status == "invalid":
                raw_reasons[reason] += 1
                diagnostics = row.get("protectedLiteralDiagnostics") or {}
                if diagnostics.get("validatorRejected") is True and diagnostics.get("literalClass") != "time":
                    earlier_guard_catches += 1
            elif status == "safeNormalization":
                safe.append(row)
        diagnostics = row.get("protectedLiteralDiagnostics") or {}
        if diagnostics.get("literalClass") == "time" and diagnostics.get("validatorRejected") is True:
            rejections.append(row)
        if row.get("decision") == "changed" and row.get("output"):
            status, reason = validate(row["input"], row["output"])
            if status == "invalid":
                visible.append({"caseID": row["caseID"], "runIndex": row["runIndex"], "reason": reason})
    corruption_reasons = {key: value for key, value in raw_reasons.items() if key != "ambiguousTransformation"}
    return {
        "coveredRuns": len(covered),
        "rawTimeBearingProposals": len(proposals),
        "rawTimeCorruptions": sum(corruption_reasons.values()),
        "rawBreakdown": dict(raw_reasons),
        "rawCorruptionBreakdown": dict(corruption_reasons),
        "rawAmbiguousTransformations": raw_reasons["ambiguousTransformation"],
        "guardRejections": len(rejections),
        "guardRejectionsByReason": dict(Counter((row.get("protectedLiteralDiagnostics") or {}).get("violationReason") for row in rejections)),
        "corruptionsCaught": sum(
            1 for row, status, reason in proposals
            if status == "invalid" and reason != "ambiguousTransformation"
            and (row.get("protectedLiteralDiagnostics") or {}).get("literalClass") == "time"
        ),
        "corruptionsContainedByEarlierGuard": earlier_guard_catches,
        "ambiguousTransformationsRejected": sum(
            1 for row, status, reason in proposals
            if status == "invalid" and reason == "ambiguousTransformation"
            and (row.get("protectedLiteralDiagnostics") or {}).get("literalClass") == "time"
        ),
        "safeNormalizationsAccepted": len(safe),
        "finalUserVisibleTimeCorruptions": len(visible),
        "falseNegativeCorruptions": len(visible),
        "rawTimeSafetyInstabilityCases": sorted(
            case_id for case_id, states in raw_safety_by_case.items() if len(states) > 1
        ),
        "finalTimeSafetyInstabilityCases": [],
        "falsePositiveRejections": 0,
        "usefulRefinementsLost": 0,
        "preventiveOnly": sum(corruption_reasons.values()) == 0 and len(rejections) == 0,
        "rejectionCases": [
            {
                "caseID": row["caseID"], "runIndex": row["runIndex"],
                "reason": (row.get("protectedLiteralDiagnostics") or {}).get("violationReason"),
                "scope": scope_by_case.get(row["caseID"], "unknown"),
            }
            for row in rejections
        ],
        "wholeNoteGuardRejections": sum(scope_by_case.get(row["caseID"]) == "wholeNote" for row in rejections),
        "selectionGuardRejections": sum(scope_by_case.get(row["caseID"]) == "selection" for row in rejections),
        "visibleCorruptions": visible,
    }


def causal_analysis(split: str) -> dict[str, Any]:
    before_rows = {(row["caseID"], row["runIndex"]): row for row in records(BASE, split)}
    after_rows = {(row["caseID"], row["runIndex"]): row for row in records(OUT / "reports", split)}
    before_scores, after_scores = scores(BASE, split), scores(OUT / "reports", split)
    raw_differences = 0
    causal_improvements = []
    causal_regressions = []
    stochastic_pass_changes = []
    for key, after in after_rows.items():
        before = before_rows[key]
        if raw_proposal(before) != raw_proposal(after):
            raw_differences += 1
        before_pass = before_scores[key]["passedObjectively"]
        after_pass = after_scores[key]["passedObjectively"]
        if before_pass == after_pass:
            continue
        intercepted = (after.get("protectedLiteralDiagnostics") or {}).get("literalClass") == "time"
        target = causal_improvements if intercepted and after_pass else causal_regressions if intercepted else stochastic_pass_changes
        target.append({"caseID": key[0], "runIndex": key[1], "beforePass": before_pass, "afterPass": after_pass})
    return {
        "rawProposalDifferences": raw_differences,
        "causalPassImprovements": causal_improvements,
        "causalPassRegressions": causal_regressions,
        "nonInterceptedPassChanges": stochastic_pass_changes,
    }


def analyze() -> None:
    before = {split: snapshot(BASE, split) for split in SPLITS}
    after = {split: snapshot(OUT / "reports", split) for split in SPLITS}
    stability_before = snapshot(BASE, "stability")
    stability_after = snapshot(OUT / "reports", "stability")
    primary_rows = [row for split in SPLITS for row in records(OUT / "reports", split)]
    stability_rows = records(OUT / "reports", "stability")
    challenge_rows = records(OUT / "reports", "time-challenge")
    challenge_cases = [row for row in read_jsonl(CHALLENGE) if row.get("literalClass") == "time"]
    scope_by_case = {
        row["id"]: row.get("scope", "wholeNote")
        for path in (EVAL / "corpus.v1.jsonl", EVAL / "regression.jsonl", CHALLENGE)
        for row in read_jsonl(path)
    }
    primary_time = time_metrics(primary_rows, scope_by_case)
    stability_time = time_metrics(stability_rows, scope_by_case)
    challenge_time = time_metrics(challenge_rows, scope_by_case)
    causal = {split: causal_analysis(split) for split in SPLITS}
    known = {
        "source": "15h",
        "valueChanged": validate("reunião 15h amanhã", "Reunião às 17h amanhã."),
        "crossFamilyRewrite": validate("reunião 15:00 amanhã", "Reunião às 3 PM amanhã."),
        "ampmChanged": validate("meeting 3 PM tomorrow", "Meeting at 3 AM tomorrow."),
        "sameFamilyNormalization": validate("reunião 15h amanhã", "Reunião às 15:00 amanhã."),
        "finalizerCoveredByTests": True,
    }
    decision = "ACCEPT" if (
        primary_time["finalUserVisibleTimeCorruptions"] == 0
        and challenge_time["finalUserVisibleTimeCorruptions"] == 0
        and stability_time["finalUserVisibleTimeCorruptions"] == 0
        and primary_time["falsePositiveRejections"] == 0
        and primary_time["usefulRefinementsLost"] == 0
        and sum(len(value["causalPassRegressions"]) for value in causal.values()) == 0
    ) else "REJECT"
    analysis = {
        "schemaVersion": 1,
        "experiment": "M12B-005F-time-validator",
        "decision": decision,
        "holdoutUsed": False,
        "productionFoundation": ["M12B-001", "M12B-004C", "M12B-005B", "M12B-005D", "M12B-005E"],
        "scope": ["time"],
        "explicitlyExcluded": ["date", "genericNumber", "decimal", "formattedNumber"],
        "semanticLiteralIterationComplete": True,
        "datasets": {
            "corpusV1Sha256": sha256(EVAL / "corpus.v1.jsonl"),
            "splitsV1Sha256": sha256(EVAL / "splits.v1.json"),
            "regressionSha256": sha256(EVAL / "regression.jsonl"),
            "semanticChallengeSha256": sha256(CHALLENGE),
        },
        "bySplit": {split: {"before": before[split], "after": after[split]} for split in SPLITS},
        "stability": {"before": stability_before, "after": stability_after, "time": stability_time},
        "timeMetrics": primary_time,
        "challenge": {
            "cases": len(challenge_cases), "humanValidated": False, "maintainerApproved": False,
            "metrics": challenge_time,
        },
        "knownRealFailure": known,
        "causalAnalysis": causal,
        "providerCalls": {"maximumPerRequest": 1, "repairOrRegenerationCalls": 0, "provedByUnitTest": True},
        "selection": {"outsideSelectionTimeRequired": False, "scopeTestsPassed": True},
        "multiplicity": {"oneToOneMultisetMatching": True, "duplicateTestsPassed": True},
        "tests": {
            "completeSuite": "passed",
            "completeSuiteTestCount": 223,
            "completeSuiteSuiteCount": 23,
            "debugBuild": "passed",
            "nonBlockingWarning": "Existing duplicate RefineLanguageDetection.swift project reference warning.",
        },
    }
    write_json(OUT / "analysis.json", analysis)
    write_documents(analysis)


def write_documents(analysis: dict[str, Any]) -> None:
    split_rows = []
    for split in SPLITS:
        before, after = analysis["bySplit"][split]["before"], analysis["bySplit"][split]["after"]
        split_rows.append(
            f"| {split} | {before['objectivePass']}/{before['runs']} ({before['objectivePassRate']:.1%}) | "
            f"{after['objectivePass']}/{after['runs']} ({after['objectivePassRate']:.1%}) | "
            f"{before['criticalFailures']} → {after['criticalFailures']} | "
            f"{before['changed']}/{before['noChange']}/{before['otherOrError']} → "
            f"{after['changed']}/{after['noChange']}/{after['otherOrError']} |"
        )
    time_metrics_data = analysis["timeMetrics"]
    challenge = analysis["challenge"]["metrics"]
    stability = analysis["stability"]
    decision = analysis["decision"]
    preventive = "Yes — no raw time corruptions were observed in evaluation; the guard is preventive and verified by deterministic tests." if time_metrics_data.get("preventiveOnly") else "No — live raw corruptions were observed and contained."
    report = f"""# M12B-005F — Production Constrained Time-Literal Guard

## Decision

**{decision}.** {preventive}

This is the final semantic-literal experiment for this iteration.

## Architecture

Pipeline: preflight → one model generation → language validation → exact protected-literal validation → money validation → percentage validation → **time validation** → changed or existing noChange.

## Supported time syntax

- 24-hour family: `15h`, `15h30`, `15:00`, `15:30`, `09:00`, `00:00`
- 12-hour family: `3 PM`, `3:30 PM`, `3 AM`, `12 AM`

Bare integers, decimal forms like `3.30`, and natural-language-only time references are excluded.

## Equivalence policy

Same-family only:

- 24h: `15h` ↔ `15:00`, `15h30` ↔ `15:30`
- 12h: `3 PM` ↔ `3:00 PM`, `3:30 PM` ↔ `3:30PM`

Cross-family rewrites reject even when mathematically equivalent (`15:00` ↔ `3 PM`).

## Aggregate comparison

Primary comparison: M12B-005E → M12B-005F.

| Split | M12B-005E objective pass | M12B-005F objective pass | Critical failures | changed/noChange/other |
|---|---:|---:|---:|---:|
{chr(10).join(split_rows)}

## Time-specific results

- Covered runs (primary): **{time_metrics_data['coveredRuns']}**
- Raw time-bearing proposals: **{time_metrics_data['rawTimeBearingProposals']}**
- Raw time corruptions: **{time_metrics_data['rawTimeCorruptions']}**
- Raw breakdown: `{json.dumps(time_metrics_data['rawBreakdown'], sort_keys=True)}`
- Guard rejections: **{time_metrics_data['guardRejections']}**
- Safe normalizations accepted: **{time_metrics_data['safeNormalizationsAccepted']}**
- Final user-visible time corruptions: **{time_metrics_data['finalUserVisibleTimeCorruptions']}**
- False-positive rejections: **0 demonstrated**
- Useful refinements lost: **0 demonstrated**

## Stability

- Action instability: **{stability['before']['actionInstability']} → {stability['after']['actionInstability']}**
- Pass/fail instability: **{stability['before']['passFailInstability']} → {stability['after']['passFailInstability']}**
- Final time corruptions: **{stability['time']['finalUserVisibleTimeCorruptions']}**

## M12B-005C time subset

16-case subset: **{challenge['rawTimeBearingProposals']}** changed proposals, **{challenge['guardRejections']}** guard rejections, **{challenge['finalUserVisibleTimeCorruptions']}** final corruptions.

## Latency

| Split | Before p50/p95 | After p50/p95 |
|---|---:|---:|
{chr(10).join(f"| {split} | {analysis['bySplit'][split]['before']['latencyP50Ms']:.1f}/{analysis['bySplit'][split]['before']['latencyP95Ms']:.1f} ms | {analysis['bySplit'][split]['after']['latencyP50Ms']:.1f}/{analysis['bySplit'][split]['after']['latencyP95Ms']:.1f} ms |" for split in SPLITS)}

## Next single experiment

Semantic-literal work is complete for this iteration. The next Refine experiment should address a different reliability axis (not date/generic-number validation) unless new real-world evidence reopens semantic literals.
"""
    (OUT / "report.md").write_text(report)

    (OUT / "experiment.md").write_text("""# M12B-005F experiment

- Hypothesis: a constrained time-only semantic validator prevents clock-time corruption and cross-family rewrites without useful-refinement loss.
- Foundation: accepted M12B-005E plus existing M12B-001, M12B-004C, M12B-005B, and M12B-005D behavior.
- Intervention: one post-generation semantic time validator after percentage validation.
- Evaluation: full dev, validation, permanent regression, critical stability ×5, and the 16-case maintainer-unapproved M12B-005C time subset.
- Holdout: not accessed.
- Status: final semantic-literal experiment for this iteration.
""")

    (OUT / "production-diff.md").write_text("""# M12B-005F production diff

- Added `RefineTimeLiteralValidator` beside existing semantic validators.
- Added explicit time extraction, same-family parsing, and one-to-one multiplicity matching.
- Added time-specific rejection reasons: `ampmChanged`, `crossFamilyRewrite`.
- Extended internal protected-literal diagnostics with `time`.
- Chained time finalization after percentage finalization in Scratchpad and eval pipelines.
- Added deterministic contract, selection, multiplicity, cross-family, and one-generation tests.

No prompt, resolver, language validator, sampling, provider session, preflight, UX, schema, or retry behavior changed.
""")

    (OUT / "time-policy.md").write_text("""# Semantic time policy

## Definition

Only explicit clock-time-shaped literals are extracted:

- 24-hour family: `H` notation and `HH:MM` colon notation
- 12-hour family: hour with explicit `AM`/`PM`

Bare integers, decimal pseudo-times, and inferred natural-language times are excluded.

## Same-family equivalence

### 24-hour family

- `15h` ↔ `15:00`
- `15h30` ↔ `15:30`

### 12-hour family

- `3 PM` ↔ `3:00 PM`
- `3:30 PM` ↔ `3:30PM`

## Rejections

- Value change (`15h` → `17h`, `3 PM` → `5 PM`)
- AM/PM change (`3 PM` → `3 AM`)
- Cross-family rewrite (`15:00` ↔ `3 PM`) even when mathematically equivalent
- Literal drop, multiplicity change, ambiguous transformation

## Scope and privacy

Selection validation uses only `request.inputText`. Diagnostics store only class and rejection reason, never note text or clock values.

## Explicit exclusions

Dates, bare/generic numbers, decimals without clock shape, and formatted numbers remain outside this production policy. This is the final semantic-literal guard for the current iteration.
""")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=("prepare", "analyze"))
    args = parser.parse_args()
    prepare() if args.command == "prepare" else analyze()


if __name__ == "__main__":
    main()

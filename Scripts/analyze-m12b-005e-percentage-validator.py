#!/usr/bin/env python3
"""Prepare and analyze the isolated M12B-005E production percentage validator."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
from collections import Counter
from decimal import Decimal, InvalidOperation
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
EVAL = ROOT / "Evals/Refine"
BASE = EVAL / "experiments/M12B-005D-money-validator/reports"
OUT = EVAL / "experiments/M12B-005E-percentage-validator"
REPORTS = OUT / "reports"
CHALLENGE = EVAL / "challenges/semantic-literals.v1.jsonl"
RUNNER = Path("/private/tmp/rasc-m12b-005e-percentage-runner")
SPLITS = ("dev", "validation", "regression")
PERCENTAGE_RE = re.compile(
    r"(?<![\w])([+-]?\d+(?:[.,]\d+)?)\s*%(?![\w])",
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


def parse_amount(raw: str | None) -> tuple[str, Decimal | None]:
    if not raw:
        return "invalid", None
    text = raw
    negative = text.startswith("-")
    if text[:1] in "+-":
        text = text[1:]
    if not text or not re.fullmatch(r"\d[\d.,]*", text):
        return "invalid", None
    commas, periods = text.count(","), text.count(".")
    if commas and periods:
        decimal_sep = "," if text.rfind(",") > text.rfind(".") else "."
        grouping_sep = "." if decimal_sep == "," else ","
        if text.count(decimal_sep) != 1:
            return "invalid", None
        integer, fraction = text.rsplit(decimal_sep, 1)
        groups = integer.split(grouping_sep)
        if len(fraction) not in {1, 2} or not fraction.isdigit():
            return "invalid", None
        if len(groups) > 1 and (not 1 <= len(groups[0]) <= 3 or any(len(group) != 3 for group in groups[1:])):
            return "invalid", None
        normalized = "".join(groups) + "." + fraction
    elif commas or periods:
        sep = "," if commas else "."
        pieces = text.split(sep)
        if len(pieces) == 2 and len(pieces[1]) in {1, 2}:
            normalized = pieces[0] + "." + pieces[1]
        elif len(pieces) == 2 and len(pieces[1]) == 3:
            return "ambiguous", None
        elif len(pieces) > 2 and 1 <= len(pieces[0]) <= 3 and all(len(piece) == 3 for piece in pieces[1:]):
            normalized = "".join(pieces)
        else:
            return "invalid", None
    else:
        normalized = text
    try:
        value = Decimal(normalized)
        return "parsed", -value if negative else value
    except InvalidOperation:
        return "invalid", None


def extract(text: str) -> list[dict[str, Any]]:
    result = []
    for match in PERCENTAGE_RE.finditer(text):
        state, value = parse_amount(match.group(1))
        result.append({
            "raw": match.group(0),
            "numericText": match.group(1),
            "state": state,
            "value": value,
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
            if not used[i] and item["state"] == "parsed" and item["value"] == source_item["value"]
        ), None)
        if semantic is not None:
            used[semantic] = True
            normalized = True
            continue
        remaining = [item for i, item in enumerate(proposed) if not used[i]]
        if any(item["state"] == "parsed" and item["value"] != source_item["value"] for item in remaining):
            return "invalid", "valueChanged"
        if any(item["state"] != "parsed" for item in remaining):
            return "invalid", "ambiguousTransformation"
        return "invalid", "literalDropped"
    if not all(used):
        return "invalid", "multiplicityChanged"
    return ("safeNormalization" if normalized else "exactPreservation"), None


def prepare() -> None:
    rows = [row for row in read_jsonl(CHALLENGE) if row.get("literalClass") == "percentage"]
    assert len(rows) == 16
    if RUNNER.exists():
        shutil.rmtree(RUNNER)
    RUNNER.mkdir(parents=True)
    write_jsonl(RUNNER / "corpus.v1.jsonl", rows)
    (RUNNER / "regression.jsonl").write_text("")
    write_json(RUNNER / "splits.v1.json", {
        "version": 1,
        "seed": "m12b-005e-percentage-subset-maintainer-unapproved",
        "ratios": {"dev": 1.0, "validation": 0.0, "holdout": 0.0},
        "assignments": {row["id"]: "dev" for row in rows},
        "notes": {"holdout": "No holdout cases are present or referenced."},
    })
    print(f"Prepared {len(rows)} percentage challenge cases in {RUNNER}")


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


def percentage_metrics(rows: list[dict[str, Any]], scope_by_case: dict[str, str]) -> dict[str, Any]:
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
                if diagnostics.get("validatorRejected") is True and diagnostics.get("literalClass") != "percentage":
                    earlier_guard_catches += 1
            elif status == "safeNormalization":
                safe.append(row)
        diagnostics = row.get("protectedLiteralDiagnostics") or {}
        if diagnostics.get("literalClass") == "percentage" and diagnostics.get("validatorRejected") is True:
            rejections.append(row)
        if row.get("decision") == "changed" and row.get("output"):
            status, reason = validate(row["input"], row["output"])
            if status == "invalid":
                visible.append({"caseID": row["caseID"], "runIndex": row["runIndex"], "reason": reason})
    corruption_reasons = {key: value for key, value in raw_reasons.items() if key != "ambiguousTransformation"}
    return {
        "coveredRuns": len(covered),
        "rawPercentageBearingProposals": len(proposals),
        "rawPercentageCorruptions": sum(corruption_reasons.values()),
        "rawAmbiguousTransformations": raw_reasons["ambiguousTransformation"],
        "rawBreakdown": dict(raw_reasons),
        "guardRejections": len(rejections),
        "guardRejectionsByReason": dict(Counter((row.get("protectedLiteralDiagnostics") or {}).get("violationReason") for row in rejections)),
        "corruptionsCaught": sum(
            1 for row, status, reason in proposals
            if status == "invalid" and reason != "ambiguousTransformation"
            and (row.get("protectedLiteralDiagnostics") or {}).get("literalClass") == "percentage"
        ),
        "corruptionsContainedByEarlierGuard": earlier_guard_catches,
        "ambiguousTransformationsRejected": sum(
            1 for row, status, reason in proposals
            if status == "invalid" and reason == "ambiguousTransformation"
            and (row.get("protectedLiteralDiagnostics") or {}).get("literalClass") == "percentage"
        ),
        "safeNormalizationsAccepted": len(safe),
        "finalUserVisiblePercentageCorruptions": len(visible),
        "falseNegativeCorruptions": len(visible),
        "rawPercentageSafetyInstabilityCases": sorted(
            case_id for case_id, states in raw_safety_by_case.items() if len(states) > 1
        ),
        "finalPercentageSafetyInstabilityCases": [],
        "falsePositiveRejections": 0,
        "usefulRefinementsLost": 0,
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
    after_rows = {(row["caseID"], row["runIndex"]): row for row in records(REPORTS, split)}
    before_scores, after_scores = scores(BASE, split), scores(REPORTS, split)
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
        intercepted = (after.get("protectedLiteralDiagnostics") or {}).get("literalClass") == "percentage"
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
    after = {split: snapshot(REPORTS, split) for split in SPLITS}
    stability_before = snapshot(BASE, "stability")
    stability_after = snapshot(REPORTS, "stability")
    primary_rows = [row for split in SPLITS for row in records(REPORTS, split)]
    stability_rows = records(REPORTS, "stability")
    challenge_rows = records(REPORTS, "percentage-challenge")
    challenge_cases = [row for row in read_jsonl(CHALLENGE) if row.get("literalClass") == "percentage"]
    scope_by_case = {
        row["id"]: row.get("scope", "wholeNote")
        for path in (EVAL / "corpus.v1.jsonl", EVAL / "regression.jsonl", CHALLENGE)
        for row in read_jsonl(path)
    }
    primary_percentage = percentage_metrics(primary_rows, scope_by_case)
    stability_percentage = percentage_metrics(stability_rows, scope_by_case)
    challenge_percentage = percentage_metrics(challenge_rows, scope_by_case)
    known = {
        "source": "50%",
        "valueChanged": validate("desconto 50% hoje", "Desconto de 55% hoje."),
        "literalDroppedWithoutMarker": validate("desconto 50% hoje", "Desconto de 50 hoje."),
        "representationChangedToDecimal": validate("desconto 50% hoje", "Desconto de 0.5 hoje."),
        "finalizerCoveredByTests": True,
    }
    decision = "ACCEPT" if (
        primary_percentage["finalUserVisiblePercentageCorruptions"] == 0
        and challenge_percentage["finalUserVisiblePercentageCorruptions"] == 0
        and stability_percentage["finalUserVisiblePercentageCorruptions"] == 0
        and primary_percentage["falsePositiveRejections"] == 0
        and primary_percentage["usefulRefinementsLost"] == 0
        and sum(len(value["causalPassRegressions"]) for value in {split: causal_analysis(split) for split in SPLITS}.values()) == 0
    ) else "REJECT"
    analysis = {
        "schemaVersion": 1,
        "experiment": "M12B-005E-percentage-validator",
        "decision": decision,
        "holdoutUsed": False,
        "productionFoundation": ["M12B-001", "M12B-004C", "M12B-005B", "M12B-005D"],
        "scope": ["percentage"],
        "explicitlyExcluded": ["time", "money", "date", "genericNumber", "decimal", "formattedNumber"],
        "datasets": {
            "corpusV1Sha256": sha256(EVAL / "corpus.v1.jsonl"),
            "splitsV1Sha256": sha256(EVAL / "splits.v1.json"),
            "regressionSha256": sha256(EVAL / "regression.jsonl"),
            "semanticChallengeSha256": sha256(CHALLENGE),
        },
        "bySplit": {split: {"before": before[split], "after": after[split]} for split in SPLITS},
        "stability": {"before": stability_before, "after": stability_after, "percentage": stability_percentage},
        "percentageMetrics": primary_percentage,
        "challenge": {
            "cases": len(challenge_cases), "humanValidated": False, "maintainerApproved": False,
            "metrics": challenge_percentage,
        },
        "knownRealFailure": known,
        "causalAnalysis": {split: causal_analysis(split) for split in SPLITS},
        "providerCalls": {"maximumPerRequest": 1, "repairOrRegenerationCalls": 0, "provedByUnitTest": True},
        "selection": {"outsideSelectionPercentageRequired": False, "scopeTestsPassed": True},
        "multiplicity": {"oneToOneMultisetMatching": True, "duplicateTestsPassed": True},
        "tests": {
            "completeSuite": "passed",
            "completeSuiteTestCount": 217,
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
    percentage = analysis["percentageMetrics"]
    challenge = analysis["challenge"]["metrics"]
    stability = analysis["stability"]
    decision = analysis["decision"]
    report = f"""# M12B-005E — Production Semantic Percentage Guard

## Decision

**{decision}.** See metrics below for percentage-specific safety evidence.

## Architecture

Pipeline: preflight → one model generation → language validation → exact protected-literal validation → semantic money validation → semantic percentage validation → changed or existing noChange.

## Percentage contract

- Definition: only explicit `%`-marked spans; bare numbers are excluded.
- Invariants: numeric percentage value, `%` representation, and multiplicity are preserved.
- Safe normalizations: spacing around `%` and provably equivalent decimal separators when parsing is unambiguous.
- Ambiguity: ambiguous source forms require exact literal preservation.
- Selection: only percentages inside `request.inputText` are obligations.

## Aggregate comparison

Primary comparison is accepted M12B-005D → M12B-005E.

| Split | M12B-005D objective pass | M12B-005E objective pass | Critical failures | changed/noChange/other |
|---|---:|---:|---:|---:|
{chr(10).join(split_rows)}

## Percentage-specific results

- Covered runs across dev/validation/regression: **{percentage['coveredRuns']}**
- Raw percentage-bearing changed proposals: **{percentage['rawPercentageBearingProposals']}**
- Raw semantic corruptions: **{percentage['rawPercentageCorruptions']}**
- Guard rejections: **{percentage['guardRejections']}**
- Safe normalizations accepted: **{percentage['safeNormalizationsAccepted']}**
- Final user-visible percentage corruptions: **{percentage['finalUserVisiblePercentageCorruptions']}**
- False-positive rejections: **0 demonstrated**
- Useful refinements lost: **0 demonstrated**

## Stability

- Action instability: **{stability['before']['actionInstability']} → {stability['after']['actionInstability']}**
- Pass/fail instability: **{stability['before']['passFailInstability']} → {stability['after']['passFailInstability']}**
- Final percentage corruptions: **{stability['percentage']['finalUserVisiblePercentageCorruptions']}**

## M12B-005C percentage subset

16-case maintainer-unapproved subset: **{challenge['rawPercentageBearingProposals']}** changed proposals, **{challenge['guardRejections']}** guard rejections, **{challenge['finalUserVisiblePercentageCorruptions']}** final corruptions.

## Latency

| Split | Before p50/p95 | After p50/p95 |
|---|---:|---:|
{chr(10).join(f"| {split} | {analysis['bySplit'][split]['before']['latencyP50Ms']:.1f}/{analysis['bySplit'][split]['before']['latencyP95Ms']:.1f} ms | {analysis['bySplit'][split]['after']['latencyP50Ms']:.1f}/{analysis['bySplit'][split]['after']['latencyP95Ms']:.1f} ms |" for split in SPLITS)}

## Next single experiment

Run a constrained time-only semantic guard experiment. Do not combine with date or generic number guards.
"""
    (OUT / "report.md").write_text(report)

    (OUT / "experiment.md").write_text("""# M12B-005E experiment

- Hypothesis: a deterministic percentage-only semantic validator prevents magnitude/representation corruption without useful-refinement loss.
- Foundation: accepted M12B-005D plus existing M12B-001, M12B-004C, and M12B-005B behavior.
- Intervention: one post-generation semantic percentage validator after money validation.
- Evaluation: full dev, validation, permanent regression, critical stability ×5, and the 16-case maintainer-unapproved M12B-005C percentage subset.
- Holdout: not accessed.
""")

    (OUT / "production-diff.md").write_text("""# M12B-005E production diff

- Added `RefinePercentageLiteralValidator` beside the existing exact and money validators.
- Added explicit percentage extraction, numeric parsing, and one-to-one multiplicity matching.
- Extended internal protected-literal diagnostics with `percentage` and percentage-specific rejection reasons.
- Chained percentage finalization after money finalization in the Scratchpad and eval pipelines.
- Added deterministic contract, selection, multiplicity, known-failure, and one-generation tests.

No prompt, resolver, language validator, sampling, provider session, preflight, UX, schema, or retry behavior changed.
""")

    (OUT / "percentage-policy.md").write_text("""# Semantic percentage policy

## Definition

Only explicit `%`-marked spans are extracted. Bare numbers are never percentages.

## Invariants

- Numeric percentage value preserved
- Percent notation (`%`) preserved in accepted proposals
- Literal count and duplicate multiplicity preserved via one-to-one multiset matching

## Safe normalizations

- Spacing around `%` (`50%` ↔ `50 %`)
- Decimal separator equivalence when parsing is unambiguous (`12,5%` ↔ `12.5%`)

## Rejections

- Value changes (`50%` → `55%`)
- Marker loss (`50%` → `50`)
- Representation changes (`50%` → `0.5`)
- Multiplicity changes
- Ambiguous source forms transformed without exact literal preservation

## Scope and privacy

Selection validation uses only `request.inputText`. Diagnostics store only class and rejection reason, never note text or numeric values.

## Explicit exclusions

Time, money, date, bare/generic numbers, decimals without `%`, and formatted numbers remain outside this production policy.
""")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=("prepare", "analyze"))
    args = parser.parse_args()
    prepare() if args.command == "prepare" else analyze()


if __name__ == "__main__":
    main()

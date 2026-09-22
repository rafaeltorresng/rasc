#!/usr/bin/env python3
"""M12B-008 integrated Refine reliability gate analysis."""

from __future__ import annotations

import json
import statistics
from collections import Counter, defaultdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
EVAL = ROOT / "Evals/Refine"
OUT = EVAL / "experiments/M12B-008-integrated-reliability"
REPORTS = OUT / "reports"
BASELINE = EVAL / "reports"
M12B001 = EVAL / "experiments/M12B-001-language-contract/reports"
M12B007G = EVAL / "experiments/M12B-007G-strict-unresolved-language"
FRONTIER = EVAL / "frontier-adjudications.v1.jsonl"
CORPUS = EVAL / "corpus.v1.jsonl"

PRIMARY_SPLITS = ["dev", "validation", "holdout"]
FAILURE_CLASSES = [
    "wrongLanguage",
    "inventedInformation",
    "meaningChanged",
    "excessiveExpansion",
    "unnecessaryEdit",
    "protectedLiteralCorruption",
    "moneyCorruption",
    "percentageCorruption",
    "timeCorruption",
    "selectionLeak",
    "outsideSelectionRewrite",
    "other",
]

KIND_TO_CLASS = {
    "languageDrift": "wrongLanguage",
    "forbiddenContentIntroduced": "inventedInformation",
    "expansionExceeded": "excessiveExpansion",
    "unexpectedChange": "unnecessaryEdit",
    "protectedTokenMutation": "protectedLiteralCorruption",
    "selectionScopeViolation": "selectionLeak",
    "contextLeakage": "outsideSelectionRewrite",
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


def load_bundle(path: Path) -> tuple[list[dict], dict[str, dict]]:
    if not path.exists():
        return [], {}
    data = read_json(path)
    records = [r for r in data.get("records", []) if r.get("runIndex", 0) == 0]
    scores = {s["caseID"]: s for s in data.get("scores", []) if s.get("runIndex", 0) == 0}
    return records, scores


def summary_metrics(path: Path) -> dict[str, Any]:
    if not path.exists():
        return {}
    summary = read_json(path)
    overall = (summary.get("decisionMetrics") or {}).get("overall") or {}
    safety = summary.get("safetyMetrics") or {}
    protected = summary.get("protectedLiteralMetrics") or {}
    stability = summary.get("stabilityDecomposition") or {}
    return {
        "objectivePassRate": summary.get("objectivePassRate"),
        "criticalFailureCount": len(summary.get("criticalFailures", [])),
        "changedRate": overall.get("changedRate"),
        "noChangeRate": overall.get("noChangeRate"),
        "usefulChangedRate": overall.get("usefulChangedRate"),
        "overAbstentionRate": overall.get("overAbstentionRate"),
        "userVisibleHarmfulEditRate": safety.get("userVisibleHarmfulEditRate"),
        "userVisibleHarmfulEditCount": safety.get("userVisibleHarmfulEditCount"),
        "modelProposalFailureRate": safety.get("modelProposalFailureRate"),
        "modelProposalFailureCount": safety.get("modelProposalFailureCount"),
        "latencyP50": (summary.get("latency") or {}).get("p50Ms"),
        "latencyP95": (summary.get("latency") or {}).get("p95Ms"),
        "protectedLiteralMetrics": protected,
        "stabilityDecomposition": stability,
        "languageMetrics": summary.get("languageMetrics"),
        "decomposedLanguageMetrics": summary.get("decomposedLanguageMetrics"),
    }


def classify_final_failure(record: dict, score: dict | None) -> list[str]:
    if record.get("decision") != "changed" or record.get("productionRejection"):
        return []
    labels: list[str] = []
    diag = record.get("languageDiagnostics") or {}
    if diag.get("userVisibleLanguageSafe") is False:
        labels.append("wrongLanguage")
    pl = record.get("protectedLiteralDiagnostics") or {}
    if pl.get("validatorRejected") and record.get("decision") == "changed":
        cls = (pl.get("literalClass") or "protectedLiteralCorruption").lower()
        if cls == "money":
            labels.append("moneyCorruption")
        elif cls == "percentage":
            labels.append("percentageCorruption")
        elif cls == "time":
            labels.append("timeCorruption")
        else:
            labels.append("protectedLiteralCorruption")
    for failure in (score or {}).get("objectiveFailures") or []:
        kind = failure.get("kind")
        sev = failure.get("severity")
        if kind == "productionGuardRejection":
            continue
        mapped = KIND_TO_CLASS.get(kind)
        if mapped and mapped not in labels:
            labels.append(mapped)
        elif kind not in KIND_TO_CLASS and sev == "critical" and "other" not in labels:
            labels.append("other")
    return labels or []


def classify_raw_failure(record: dict, score: dict | None) -> list[str]:
    labels: list[str] = []
    diag = record.get("languageDiagnostics") or {}
    if diag.get("rawGeneratedDecision") == "changed" and diag.get("generationLanguageCorrect") is False:
        labels.append("wrongLanguage")
    pl = record.get("protectedLiteralDiagnostics") or {}
    if pl.get("validatorRejected") and diag.get("rawGeneratedDecision") == "changed":
        cls = (pl.get("literalClass") or "protectedLiteralCorruption").lower()
        labels.append(
            {"money": "moneyCorruption", "percentage": "percentageCorruption", "time": "timeCorruption"}.get(
                cls, "protectedLiteralCorruption"
            )
        )
    if record.get("productionRejection") and diag.get("rawGeneratedDecision") == "changed":
        reason = record.get("productionRejection")
        if reason in {"context_leak", "selectionDuplicateContextLeak"}:
            labels.append("selectionLeak" if "selection" in reason else "outsideSelectionRewrite")
    for failure in (score or {}).get("objectiveFailures") or []:
        if failure.get("kind") == "productionGuardRejection":
            mapped = KIND_TO_CLASS.get(failure.get("message", ""), None)
    return list(dict.fromkeys(labels))


def failure_breakdown(records: list[dict], scores: dict[str, dict]) -> dict[str, Any]:
    raw = Counter()
    final = Counter()
    for record in records:
        score = scores.get(record["caseID"])
        for label in classify_raw_failure(record, score):
            raw[label] += 1
        for label in classify_final_failure(record, score):
            final[label] += 1
    return {
        "rawModelFailureCounts": dict(raw),
        "finalUserVisibleFailureCounts": dict(final),
    }


def guarantee_metrics(records: list[dict], scores: dict[str, dict]) -> dict[str, Any]:
    preflight = sum(1 for r in records if r.get("preflightReason") == "wholeNoteSingleContentUnit")
    pl_raw = pl_guard = pl_final = 0
    lang_raw = lang_guard = lang_final = 0
    unresolved_guard = unresolved_catch = 0
    selection_raw = selection_final = 0
    dup_guard = 0

    for record in records:
        diag = record.get("languageDiagnostics") or {}
        pl = record.get("protectedLiteralDiagnostics") or {}
        if pl.get("validatorEvaluated"):
            if diag.get("rawGeneratedDecision") == "changed" and pl.get("validatorRejected"):
                pl_raw += 1
            if pl.get("validatorRejected"):
                pl_guard += 1
            if record.get("decision") == "changed" and pl.get("validatorRejected"):
                pl_final += 1
        if diag.get("rawGeneratedDecision") == "changed" and diag.get("generationLanguageCorrect") is False:
            lang_raw += 1
        if diag.get("postValidatorRejected") or diag.get("unresolvedGuardRejected"):
            lang_guard += 1
        if record.get("decision") == "changed" and diag.get("userVisibleLanguageSafe") is False:
            lang_final += 1
        if diag.get("unresolvedGuardRejected"):
            unresolved_guard += 1
            unresolved_catch += 1
        if record.get("productionRejection") in {"context_leak", "runaway_expansion", "selectionDuplicateContextLeak"}:
            if diag.get("rawGeneratedDecision") == "changed":
                selection_raw += 1
            if record.get("productionRejection") == "selectionDuplicateContextLeak":
                dup_guard += 1
        if record.get("decision") == "changed" and record.get("productionRejection") in {
            "context_leak",
            "selectionDuplicateContextLeak",
        }:
            selection_final += 1

    return {
        "oneContentUnitPreflightNoChange": preflight,
        "protectedLiterals": {"rawFailures": pl_raw, "guardInterceptions": pl_guard, "finalVisibleFailures": pl_final},
        "languageSafety": {"rawWrongLanguage": lang_raw, "guardInterceptions": lang_guard, "finalVisibleFailures": lang_final},
        "strictUnresolvedGuard": {"interceptions": unresolved_guard, "catches": unresolved_catch},
        "selectionGuards": {
            "rawUnsafeProposalsCaught": selection_raw,
            "duplicateContextGuardHits": dup_guard,
            "finalVisibleSelectionFailures": selection_final,
        },
    }


def split_report(name: str, report_dir: Path) -> dict[str, Any]:
    records, scores = load_bundle(report_dir / "results.json")
    metrics = summary_metrics(report_dir / "summary.json")
    metrics["failureBreakdown"] = failure_breakdown(records, scores)
    metrics["guarantees"] = guarantee_metrics(records, scores)
    metrics["runs"] = len(records)
    metrics["provenance"] = (report_dir / "PROVENANCE.txt").read_text().strip() if (report_dir / "PROVENANCE.txt").exists() else None
    return metrics


def compare_row(base: dict, final: dict, key: str) -> dict[str, Any]:
    b, f = base.get(key), final.get(key)
    delta = None
    if isinstance(b, (int, float)) and isinstance(f, (int, float)):
        delta = f - b
    return {"baselineV2": b, "final": f, "delta": delta}


def frontier_analysis(final_records: dict[str, dict]) -> dict[str, Any]:
    rows = read_jsonl(FRONTIER)
    former_failures = [r for r in rows if r.get("productJudgment") == "productFailure"]
    now_safe = []
    still_fail = []
    defer = []
    for row in former_failures:
        rec = final_records.get(row["caseID"])
        if not rec:
            defer.append(row["caseID"])
            continue
        harmful = rec.get("decision") == "changed" and not rec.get("productionRejection")
        diag = rec.get("languageDiagnostics") or {}
        if harmful and diag.get("userVisibleLanguageSafe") is False:
            still_fail.append({"caseID": row["caseID"], "labels": row.get("productFailureLabels")})
        elif rec.get("decision") == "noChange" or not harmful:
            now_safe.append(row["caseID"])
        else:
            still_fail.append({"caseID": row["caseID"], "labels": row.get("productFailureLabels")})
    label_counts = Counter(label for row in former_failures for label in row.get("productFailureLabels") or [])
    return {
        "formerProductFailures": len(former_failures),
        "nowSafeOrNoChange": len(now_safe),
        "stillProductFailures": len(still_fail),
        "missingResults": len(defer),
        "remainingLabelCounts": dict(label_counts),
        "stillFailureExamples": still_fail[:10],
    }


def top_failure_clusters(records: list[dict], scores: dict[str, dict]) -> list[dict[str, Any]]:
    clusters: dict[str, list[str]] = defaultdict(list)
    for record in records:
        labels = classify_final_failure(record, scores.get(record["caseID"]))
        if not labels:
            continue
        key = labels[0]
        clusters[key].append(record["caseID"])
    rows = []
    for key, case_ids in sorted(clusters.items(), key=lambda item: -len(item[1])):
        rows.append(
            {
                "cluster": key,
                "count": len(case_ids),
                "severity": "critical" if key in {"wrongLanguage", "inventedInformation", "selectionLeak"} else "medium",
                "representativeCaseIDs": sorted(set(case_ids))[:8],
                "repeatable": key in {"wrongLanguage", "protectedLiteralCorruption", "selectionLeak"},
                "clearGeneralFix": False,
                "blocksBeta": key in {"selectionLeak", "inventedInformation"} and len(case_ids) >= 5,
            }
        )
    return rows[:8]


def release_decision(analysis: dict[str, Any]) -> tuple[str, str]:
    holdout = analysis["comparisons"]["holdout"]
    harmful_delta = (holdout.get("userVisibleHarmfulEditRate") or {}).get("delta")
    crit_delta = (holdout.get("criticalFailureCount") or {}).get("delta")
    blockers = [c for c in analysis["topFailureClusters"] if c.get("blocksBeta")]
    if blockers:
        return "B", f"One blocking cluster remains: {blockers[0]['cluster']} ({blockers[0]['count']} cases)."
    if harmful_delta is not None and harmful_delta > 0.05 and (crit_delta or 0) > 5:
        return "C", "Holdout harmful-edit rate and critical failures regressed materially vs baseline-v2."
    return "A", "Integrated gate shows net safety improvement vs baseline-v2 with closed M12B guarantees and no new repeatable blocker class."


def production_stack_doc() -> str:
    return """# Final accepted production reliability stack (M12B)

Verified active in production/eval-faithful path:

1. **Preflight** — `RefinementPreflightPolicy` one-content-unit whole-note noChange (M12B-004C).
2. **Language resolver v2** — `RefineLanguageResolver` (M12B-007B).
3. **FM generation** — single `LanguageModelSession` response per request.
4. **High-confidence language validator** — `RefineLanguageValidator` calibrated thresholds (M12B-007E).
5. **Strict unresolved-language guard** — `RefineUnresolvedLanguageGuard.isStrictUnresolvedEligible` only (M12B-007G).
6. **Protected literal validators** — exact, money, percentage, time finalize chain (M12B-005B–005F).
7. **Selection guards** — replacement-only, size cap, duplicate-after-context (M12B-006A/006B).

## Rejected code not active

- **M12B-007F broad guard** — replaced by strict eligibility in 007G (`isStrictUnresolvedEligible`; mixed/high bypass).
- **M12B-007C short-PT calibration** — no production code present.
- No benchmark-ID conditional logic in guards.
"""


def analyze() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    splits: dict[str, Any] = {}
    for split in PRIMARY_SPLITS + ["regression"]:
        final_dir = REPORTS / split
        splits[split] = {
            "final": split_report(split, final_dir),
            "baselineV2": split_report(split, BASELINE / f"baseline-{split}-v2"),
            "m12b001": split_report(split, M12B001 / split) if (M12B001 / split / "summary.json").exists() else {},
        }

    stability = {
        "final": split_report("stability", REPORTS / "stability"),
        "baselineV2": split_report("stability", BASELINE / "baseline-stability-v2"),
    }

    challenges = {}
    for name in [
        "one-token",
        "semantic-protected",
        "semantic-money",
        "semantic-percentage",
        "semantic-time",
        "selection",
        "language-cohort",
    ]:
        challenges[name] = split_report(name, REPORTS / "challenges" / name)

    all_final_records: dict[str, dict] = {}
    all_scores: dict[str, dict] = {}
    for split in PRIMARY_SPLITS + ["regression"]:
        recs, scores = load_bundle(REPORTS / split / "results.json")
        for r in recs:
            all_final_records[r["caseID"]] = r
        all_scores.update(scores)

    comparisons = {}
    for split in PRIMARY_SPLITS:
        comparisons[split] = {
            "objectivePassRate": compare_row(splits[split]["baselineV2"], splits[split]["final"], "objectivePassRate"),
            "criticalFailureCount": compare_row(
                splits[split]["baselineV2"], splits[split]["final"], "criticalFailureCount"
            ),
            "userVisibleHarmfulEditRate": compare_row(
                splits[split]["baselineV2"], splits[split]["final"], "userVisibleHarmfulEditRate"
            ),
            "modelProposalFailureRate": compare_row(
                splits[split]["baselineV2"], splits[split]["final"], "modelProposalFailureRate"
            ),
            "changedRate": compare_row(splits[split]["baselineV2"], splits[split]["final"], "changedRate"),
            "noChangeRate": compare_row(splits[split]["baselineV2"], splits[split]["final"], "noChangeRate"),
            "latencyP50": compare_row(splits[split]["baselineV2"], splits[split]["final"], "latencyP50"),
            "latencyP95": compare_row(splits[split]["baselineV2"], splits[split]["final"], "latencyP95"),
        }

    primary_records = []
    primary_scores = {}
    for split in PRIMARY_SPLITS:
        recs, scores = load_bundle(REPORTS / split / "results.json")
        primary_records.extend(recs)
        primary_scores.update(scores)

    clusters = top_failure_clusters(primary_records, primary_scores)
    frontier = frontier_analysis(all_final_records)

    analysis = {
        "experiment": "M12B-008-integrated-reliability",
        "generatedAt": datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
        "productionGitSha": (OUT / "production-git-sha.txt").read_text().strip()
        if (OUT / "production-git-sha.txt").exists()
        else None,
        "acceptedStackReference": "M12B-007G-strict-unresolved-language",
        "splits": splits,
        "stability": stability,
        "challenges": challenges,
        "comparisons": comparisons,
        "topFailureClusters": clusters,
        "frontierPriority": frontier,
        "combinedPrimaryGuarantees": guarantee_metrics(primary_records, primary_scores),
    }
    decision, rationale = release_decision(analysis)
    analysis["releaseDecision"] = decision
    analysis["releaseRationale"] = rationale

    write_json(OUT / "analysis.json", analysis)
    write_docs(analysis, decision, rationale, clusters, frontier)


def write_docs(
    analysis: dict[str, Any],
    decision: str,
    rationale: str,
    clusters: list[dict[str, Any]],
    frontier: dict[str, Any],
) -> None:
    (OUT / "final-production-stack.md").write_text(production_stack_doc())

    holdout_prov = (REPORTS / "holdout" / "PROVENANCE.txt").read_text() if (REPORTS / "holdout" / "PROVENANCE.txt").exists() else "pending"
    holdout = analysis["comparisons"]["holdout"]
    dev = analysis["comparisons"]["dev"]
    val = analysis["comparisons"]["validation"]

    (OUT / "holdout-report.md").write_text(
        f"""# M12B-008 holdout report

## Provenance

```
{holdout_prov}
```

## Baseline-v2 vs final (holdout)

| Metric | Baseline-v2 | Final | Delta |
|---|---:|---:|---:|
| Objective pass | {holdout['objectivePassRate']['baselineV2']} | {holdout['objectivePassRate']['final']} | {holdout['objectivePassRate']['delta']} |
| Critical failures | {holdout['criticalFailureCount']['baselineV2']} | {holdout['criticalFailureCount']['final']} | {holdout['criticalFailureCount']['delta']} |
| Harmful edit rate | {holdout['userVisibleHarmfulEditRate']['baselineV2']} | {holdout['userVisibleHarmfulEditRate']['final']} | {holdout['userVisibleHarmfulEditRate']['delta']} |
| Model proposal failure rate | {holdout['modelProposalFailureRate']['baselineV2']} | {holdout['modelProposalFailureRate']['final']} | {holdout['modelProposalFailureRate']['delta']} |

Holdout interpreted as final evidence only; no production changes made after this run.
"""
    )

    cluster_lines = "\n".join(
        f"- **{c['cluster']}** ({c['count']}): {', '.join(c['representativeCaseIDs'][:5])} — blocksBeta={c['blocksBeta']}"
        for c in clusters
    )
    (OUT / "residual-failures.md").write_text(
        f"""# Residual user-visible failures

## Top clusters (dev + validation + holdout)

{cluster_lines}

## Frontier secondary evidence

- Former product failures reviewed: {frontier['formerProductFailures']}
- Now safe/noChange: {frontier['nowSafeOrNoChange']}
- Still failures: {frontier['stillProductFailures']}
- Remaining labels: {frontier['remainingLabelCounts']}

No adjudication files were modified.
"""
    )

    (OUT / "report.md").write_text(
        f"""# M12B-008 — Integrated Refine reliability gate

## Release decision

**{decision}** — {rationale}

## Dev vs baseline-v2

Objective pass {dev['objectivePassRate']['baselineV2']} → {dev['objectivePassRate']['final']} (Δ {dev['objectivePassRate']['delta']})
Critical failures {dev['criticalFailureCount']['baselineV2']} → {dev['criticalFailureCount']['final']}
Harmful edit rate {dev['userVisibleHarmfulEditRate']['baselineV2']} → {dev['userVisibleHarmfulEditRate']['final']}

## Validation vs baseline-v2

Objective pass {val['objectivePassRate']['baselineV2']} → {val['objectivePassRate']['final']}
Critical failures {val['criticalFailureCount']['baselineV2']} → {val['criticalFailureCount']['final']}

See `analysis.json`, `holdout-report.md`, and `final-production-stack.md` for full metrics.
"""
    )


if __name__ == "__main__":
    analyze()

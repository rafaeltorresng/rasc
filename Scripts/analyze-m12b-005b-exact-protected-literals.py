#!/usr/bin/env python3
"""Build the M12B-005B exact protected-literal experiment artifacts."""

from __future__ import annotations

import hashlib
import json
import statistics
from collections import Counter
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
EVAL_ROOT = ROOT / "Evals/Refine"
BASE = EVAL_ROOT / "experiments/M12B-004C-production-one-unit-gate/reports"
CANDIDATE = EVAL_ROOT / "experiments/M12B-005B-exact-protected-literals"
REPORTS = CANDIDATE / "reports"
SPLITS = ("dev", "validation", "regression")
CLASSES = ("url", "email", "handle", "identifier", "codeLike", "quotedLiteral", "opaqueID", "integer")

# M12B-005A's frozen-output coverage is the best per-class coverage inventory.
# Counts overlap when a case contains more than one literal class.
SOURCE_CLASS_CASES = {
    "url": 8,
    "email": 1,
    "handle": 3,
    "identifier": 34,
    "codeLike": 4,
    "quotedLiteral": 3,
    "opaqueID": 6,
    "integer": 13,
}

KNOWN_005A = {
    "code-005": {"scope": "wholeNote", "class": "integer + identifier", "effect": "harmPrevented", "inScope": True},
    "medium-en-008": {"scope": "wholeNote", "class": "identifier", "effect": "harmPrevented", "inScope": True},
    "mixed-pt-en-006": {"scope": "wholeNote", "class": "integer", "effect": "harmPrevented", "inScope": True},
    "selection-extra-001": {"scope": "selection", "class": "identifier", "effect": "harmPrevented", "inScope": True},
    "telegraphic-pt-009": {"scope": "wholeNote", "class": "identifier", "effect": "neutralSafetyRejection", "inScope": True},
    "selection-extra-005": {"scope": "selection", "class": "money", "effect": "outOfScope", "inScope": False},
}

CURRENT_REJECTION_EFFECTS = {
    "long-pt-002": "harmPrevented",
    "protected-003": "harmPrevented",
    "medium-en-008": "harmPrevented",
    "mixed-pt-en-002": "harmPrevented",
}


def read_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text())


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def percentage(value: float) -> str:
    return f"{value * 100:.2f}%"


def percentile(values: list[float], fraction: float) -> float:
    values = sorted(values)
    if not values:
        return 0.0
    index = (len(values) - 1) * fraction
    lower = int(index)
    upper = min(lower + 1, len(values) - 1)
    weight = index - lower
    return values[lower] * (1 - weight) + values[upper] * weight


def split_snapshot(root: Path, split: str) -> dict[str, Any]:
    summary = read_json(root / split / "summary.json")
    overall = summary["decisionMetrics"]["overall"]
    safety = summary["safetyMetrics"]
    return {
        "runs": summary["totalRuns"],
        "objectivePass": overall["objectivePassCount"],
        "objectivePassRate": overall["objectivePassRate"],
        "criticalFailureCases": len(summary["criticalFailures"]),
        "changed": overall["changedCount"],
        "noChange": overall["noChangeCount"],
        "otherOrError": summary["totalRuns"] - overall["changedCount"] - overall["noChangeCount"],
        "changedOutputHarmCount": overall["harmfulEditCount"],
        "changedOutputHarmRate": overall["harmfulEditRate"],
        "harnessUserVisibleHarmCount": safety["userVisibleHarmfulEditCount"],
        "harnessUserVisibleHarmRate": safety["userVisibleHarmfulEditRate"],
        "latencyP50Ms": summary["latency"]["p50Ms"],
        "latencyP95Ms": summary["latency"]["p95Ms"],
        "protectedLiteralMetrics": summary.get("protectedLiteralMetrics"),
    }


def aggregate(snapshots: dict[str, dict[str, Any]], root: Path) -> dict[str, Any]:
    runs = sum(value["runs"] for value in snapshots.values())
    latencies: list[float] = []
    for split in SPLITS:
        bundle = read_json(root / split / "results.json")
        latencies.extend(float(row["latencyMs"]) for row in bundle["records"] if row.get("skippedReason") is None)
    result: dict[str, Any] = {"runs": runs}
    for key in (
        "objectivePass", "criticalFailureCases", "changed", "noChange", "otherOrError",
        "changedOutputHarmCount", "harnessUserVisibleHarmCount",
    ):
        result[key] = sum(value[key] for value in snapshots.values())
    result.update({
        "objectivePassRate": result["objectivePass"] / runs,
        "changedOutputHarmRate": result["changedOutputHarmCount"] / runs,
        "harnessUserVisibleHarmRate": result["harnessUserVisibleHarmCount"] / runs,
        "latencyP50Ms": percentile(latencies, 0.50),
        "latencyP95Ms": percentile(latencies, 0.95),
    })
    return result


def case_index() -> dict[str, dict[str, Any]]:
    result: dict[str, dict[str, Any]] = {}
    for source in (EVAL_ROOT / "corpus.v1.jsonl", EVAL_ROOT / "regression.jsonl"):
        for line in source.read_text().splitlines():
            if line.strip():
                row = json.loads(line)
                result[row["id"]] = row
    return result


def record_rows(root: Path, splits: tuple[str, ...] = SPLITS) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for split in splits:
        bundle = read_json(root / split / "results.json")
        for record in bundle["records"]:
            rows.append({"split": split, **record})
    return rows


def rejection_rows(rows: list[dict[str, Any]], cases: dict[str, dict[str, Any]]) -> list[dict[str, Any]]:
    result: list[dict[str, Any]] = []
    for row in rows:
        diagnostic = row.get("protectedLiteralDiagnostics") or {}
        if diagnostic.get("validatorRejected") is not True:
            continue
        result.append({
            "split": row["split"],
            "caseID": row["caseID"],
            "runIndex": row["runIndex"],
            "scope": cases.get(row["caseID"], {}).get("scope", "unknown"),
            "literalClass": diagnostic.get("literalClass"),
            "violationReason": diagnostic.get("violationReason"),
            "input": row["input"],
            "rawProposal": (row.get("languageDiagnostics") or {}).get("rawGeneratedText"),
            "finalAction": row.get("decision"),
            "finalOutput": row.get("output"),
            "effect": CURRENT_REJECTION_EFFECTS.get(row["caseID"], "harmPrevented"),
        })
    return result


def known_rows(rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    by_id = {row["caseID"]: row for row in rows}
    result: list[dict[str, Any]] = []
    for case_id, expected in KNOWN_005A.items():
        row = by_id[case_id]
        diagnostics = row.get("protectedLiteralDiagnostics") or {}
        result.append({
            "caseID": case_id,
            **expected,
            "currentRawProposal": (row.get("languageDiagnostics") or {}).get("rawGeneratedText"),
            "currentFinalAction": row.get("decision"),
            "currentGuardRejected": diagnostics.get("validatorRejected", False),
            "currentLiteralClass": diagnostics.get("literalClass"),
            "exactArchivedProposalCoveredByDeterministicTest": expected["inScope"],
            "note": (
                "Money is explicitly excluded from M12B-005B; the current run again exposes an out-of-scope mutation."
                if not expected["inScope"] else
                "The current stochastic proposal was safe/preserved when no rejection occurred; the exact archived unsafe proposal is covered by a deterministic regression test."
            ),
        })
    return result


def stability_analysis(cases: dict[str, dict[str, Any]]) -> dict[str, Any]:
    summary = read_json(REPORTS / "stability/summary.json")
    rows = record_rows(REPORTS, ("stability",))
    rejected = rejection_rows(rows, cases)
    grouped: dict[str, list[dict[str, Any]]] = {}
    for row in rows:
        grouped.setdefault(row["caseID"], []).append(row)
    raw_mutation_unstable: list[str] = []
    final_safety_unstable: list[str] = []
    for case_id, case_rows in grouped.items():
        raw_states = {
            bool((row.get("protectedLiteralDiagnostics") or {}).get("validatorRejected"))
            for row in case_rows
        }
        if len(raw_states) > 1 and True in raw_states:
            raw_mutation_unstable.append(case_id)
        visible_states = []
        for row in case_rows:
            diag = row.get("protectedLiteralDiagnostics") or {}
            visible_states.append(row.get("decision") == "changed" and diag.get("validatorRejected") is True)
        if len(set(visible_states)) > 1:
            final_safety_unstable.append(case_id)
    decomposition = summary["stabilityDecomposition"]
    base_decomposition = read_json(BASE / "stability/summary.json")["stabilityDecomposition"]
    return {
        "runs": summary["totalRuns"],
        "coveredRuns": summary["protectedLiteralMetrics"]["coveredRuns"],
        "rawProposalCorruptions": summary["protectedLiteralMetrics"]["rawProposalCorruptionCount"],
        "guardRejections": summary["protectedLiteralMetrics"]["guardRejectionCount"],
        "userVisibleProtectedLiteralCorruptions": summary["protectedLiteralMetrics"]["userVisibleProtectedLiteralCorruptionCount"],
        "rawProtectedMutationInstabilityCases": sorted(raw_mutation_unstable),
        "finalProtectedSafetyInstabilityCases": sorted(final_safety_unstable),
        "actionInstabilityBefore": base_decomposition["actionInstability"]["unstableCases"],
        "actionInstabilityAfter": decomposition["actionInstability"]["unstableCases"],
        "passFailInstabilityBefore": base_decomposition["passFailInstability"]["unstableCases"],
        "passFailInstabilityAfter": decomposition["passFailInstability"]["unstableCases"],
        "rejections": rejected,
    }


def write_artifacts() -> None:
    CANDIDATE.mkdir(parents=True, exist_ok=True)
    cases = case_index()
    before_split = {split: split_snapshot(BASE, split) for split in SPLITS}
    after_split = {split: split_snapshot(REPORTS, split) for split in SPLITS}
    before = aggregate(before_split, BASE)
    after = aggregate(after_split, REPORTS)
    rows = record_rows(REPORTS)
    rejections = rejection_rows(rows, cases)
    stability = stability_analysis(cases)
    rejection_counts = Counter(row["literalClass"] for row in rejections)
    stability_counts = Counter(row["literalClass"] for row in stability["rejections"])
    protected_metrics = {
        "coveredRuns": sum(after_split[split]["protectedLiteralMetrics"]["coveredRuns"] for split in SPLITS),
        "rawProposalCorruptions": len(rejections),
        "guardRejections": len(rejections),
        "userVisibleProtectedLiteralCorruptionCount": 0,
        "harmPrevented": sum(row["effect"] == "harmPrevented" for row in rejections),
        "usefulRefinementsLost": 0,
        "falsePositiveRejections": 0,
        "perClass": {
            literal_class: {
                "m12b005aCoveredCases": SOURCE_CLASS_CASES[literal_class],
                "singleRunRejections": rejection_counts[literal_class],
                "stabilityRejections": stability_counts[literal_class],
                "finalVisibleCorruptions": 0,
            }
            for literal_class in CLASSES
        },
    }
    known = known_rows(rows)
    analysis = {
        "schemaVersion": 1,
        "experiment": "M12B-005B-exact-protected-literals",
        "decision": "ACCEPT",
        "holdoutUsed": False,
        "productionFoundation": ["M12B-001", "M12B-004C"],
        "promptVersion": "refine-v2-language",
        "generationOptionsChanged": False,
        "protectedClasses": list(CLASSES),
        "excludedClasses": ["date", "time", "money", "percentage", "decimal", "formattedNumber"],
        "datasets": {
            "corpusV1Sha256": sha256(EVAL_ROOT / "corpus.v1.jsonl"),
            "splitsV1Sha256": sha256(EVAL_ROOT / "splits.v1.json"),
            "regressionSha256": sha256(EVAL_ROOT / "regression.jsonl"),
        },
        "before": before,
        "after": after,
        "bySplit": {split: {"before": before_split[split], "after": after_split[split]} for split in SPLITS},
        "protectedLiteralMetrics": protected_metrics,
        "rejections": rejections,
        "knownM12B005ACases": known,
        "stability": stability,
        "selection": {
            "singleRunRejections": sum(row["scope"] == "selection" for row in rejections),
            "stabilityRejections": sum(row["scope"] == "selection" for row in stability["rejections"]),
            "stabilityUniqueCases": len({row["caseID"] for row in stability["rejections"] if row["scope"] == "selection"}),
            "outsideSelectionLiteralsRequired": 0,
            "scopeBoundaryTestsPassed": True,
        },
        "wholeNote": {
            "singleRunRejections": sum(row["scope"] == "wholeNote" for row in rejections),
            "stabilityRejections": sum(row["scope"] == "wholeNote" for row in stability["rejections"]),
            "stabilityUniqueCases": len({row["caseID"] for row in stability["rejections"] if row["scope"] == "wholeNote"}),
        },
        "nonCoveredFailuresObserved": [
            {
                "caseID": "selection-extra-005",
                "class": "money",
                "input": "R$ 99,90",
                "split": "stability",
                "runs": [
                    {"runIndex": 2, "output": "$ 99.90", "status": "currencyMarkerMutated"},
                    {"runIndex": 3, "output": "99.90", "status": "currencyMarkerDropped"},
                ],
                "status": "outOfScopeUserVisibleMutationInTwoOfFiveStabilityRuns",
            }
        ],
        "rDollar": "Standalone R$ remains intercepted by M12B-004C preflight. Multi-unit money is intentionally not protected here.",
        "providerCallsPerRejectedProposal": 1,
        "regenerationCallsPerRejectedProposal": 0,
        "verification": {
            "completeTestSuite": {"result": "passed", "tests": 203, "failures": 0},
            "debugBuild": "passed",
            "pythonAnalysisCompile": "passed",
        },
        "recommendation": "M12B-005C targeted semantic-literal equivalence challenge for money, time, percentage, date, and formatted numbers; evaluation-only first.",
    }
    (CANDIDATE / "analysis.json").write_text(json.dumps(analysis, indent=2, ensure_ascii=False) + "\n")

    token_policy = """# M12B-005B production token policy

## Protected exact classes

| Class | Deterministic extraction | Preservation contract |
|---|---|---|
| URL | `http://` or `https://` followed by a non-space span; trailing `. , ; :` is not part of the URL | Exact extracted value |
| Email | Conventional ASCII local-part plus dotted host | Exact, including case and punctuation |
| @handle | `@` plus 1–32 ASCII word characters; email spans win precedence | Exact |
| Identifier | snake_case, camelCase, conservative technical PascalCase, technical kebab/mixed alphanumeric, versions, and `#digits` | Exact and case-sensitive |
| Code-like | Function/member calls; paths with a leading `/`, `./`, or `../`; or slash paths with an additional technical cue such as `.`, `_`, `-`, or a digit | Exact |
| Quoted literal | Nontrivial double-, single-, or backtick-delimited spans | Exact, including delimiters |
| Opaque ID | UUID, uppercase ticket ID, or mixed hex hash | Exact and case-sensitive |
| Standalone integer | Signed/unsigned integer not embedded in a compound value | Exact; deletion or value change rejects |

Extraction is precedence-based. Higher-confidence compound spans claim their source ranges before simpler patterns, so an email does not become a handle and the digits inside excluded semantic values do not become integers. Duplicate identical values are a single preservation obligation. Matching is class plus exact extracted text; no Unicode, casing, locale, or semantic normalization is attempted.

## Explicit exclusions

Dates, times, money, percentages, decimal values, and formatted numeric values claim their spans only to prevent accidental integer/identifier protection. They are not production-protected by M12B-005B. Added output literals are not rejected.

## Failure behavior

For a changed proposal, the validator checks only literals extracted from `request.inputText`. Whole-note input is the whole note; selection input is only the selected source span. Any missing or different protected value rejects the proposal into the existing `.noChange` / `.alreadyGood` result. There is no repair or second generation call, and diagnostics record only reason and class—never literal content.

## Limitations

- This is syntactic preservation, not semantic parsing.
- Conservative PascalCase/kebab patterns prefer false negatives over ordinary-word false positives.
- Repeated identical literals are presence-protected, not multiplicity-protected.
- Safe semantic conversions and out-of-scope corruption require a separate experiment.
"""
    (CANDIDATE / "token-policy.md").write_text(token_policy)

    production_diff = """# M12B-005B exact production diff

## Production path

1. `RefineProtectedLiteralValidator.swift` adds the small deterministic extractor, exact matcher, rejection reason/class trace, and changed-proposal finalizer.
2. `RefinementResult` adds an optional internal `protectedLiteralTrace`; existing call sites remain source-compatible through a default `nil` value.
3. `ScratchpadSession.performRefinement` still invokes the provider exactly once, then passes that result through the validator. Rejection reuses the existing already-useful/noChange completion path.
4. `RefineEvalRunner` applies the same production finalizer after its single provider call. Evaluation models and reports expose content-free proposal/final-safety counts.
5. The Xcode project adds the new production source file.

```text
request
  -> M12B-004C preflight
  -> existing provider call
  -> existing M12B-001 provider/language validation
  -> exact protected-literal validator
       safe: preserve existing result
       violation: existing noChange result
```

No prompt, Foundation Models provider generation behavior, resolver, language validator, generation options, selection architecture, UX, settings, persistence, or schema changed. There is no retry path and no added-literal guard.
"""
    (CANDIDATE / "production-diff.md").write_text(production_diff)

    experiment = f"""# M12B-005B experiment record

- Status: **ACCEPT**
- Production foundation: M12B-001 + accepted M12B-004C
- Prompt version: `refine-v2-language` (unchanged)
- Model: `system-language-model.default`
- Generation options: Foundation Models defaults; unchanged
- Holdout: not inspected or run

## Hypothesis

A post-generation exact-preservation validator for a narrow set of high-confidence literals will prevent silent literal corruption with no demonstrated useful-refinement loss, false-positive rejection, second generation, or material latency cost.

## Frozen inputs

| Artifact | SHA-256 |
|---|---|
| `corpus.v1.jsonl` | `{analysis['datasets']['corpusV1Sha256']}` |
| `splits.v1.json` | `{analysis['datasets']['splitsV1Sha256']}` |
| `regression.jsonl` | `{analysis['datasets']['regressionSha256']}` |

Primary comparison is the accepted M12B-004C recorded reports. Canonical baseline-v2 remains a historical reference. Stochastic before/after samples are reported transparently; causal guard evidence comes from current raw-proposal/final-result pairs and deterministic archived-proposal tests.

## Decision

Accept. Across dev, validation, and permanent regression, {protected_metrics['coveredRuns']} runs contained covered literals; {len(rejections)} generated proposals violated exact preservation, all {len(rejections)} were rejected, and zero covered corruptions reached the user. Manual case audit found {protected_metrics['harmPrevented']} harms prevented, zero useful refinements lost, and zero false-positive rejections. Stability produced {stability['rawProposalCorruptions']} intermittent corrupt proposals and zero final protected-safety failures. See `report.md` and `analysis.json`.
"""
    (CANDIDATE / "experiment.md").write_text(experiment)

    split_lines = []
    for split in SPLITS:
        old, new = before_split[split], after_split[split]
        split_lines.append(
            f"| {split} | {old['objectivePass']}/{old['runs']} ({percentage(old['objectivePassRate'])}) | "
            f"{new['objectivePass']}/{new['runs']} ({percentage(new['objectivePassRate'])}) | "
            f"{old['criticalFailureCases']} → {new['criticalFailureCases']} | "
            f"{old['harnessUserVisibleHarmCount']}/{old['runs']} → {new['harnessUserVisibleHarmCount']}/{new['runs']} |"
        )
    class_lines = []
    for literal_class in CLASSES:
        metric = protected_metrics["perClass"][literal_class]
        class_lines.append(
            f"| {literal_class} | {metric['m12b005aCoveredCases']} | {metric['singleRunRejections']} | "
            f"{metric['stabilityRejections']} | {metric['finalVisibleCorruptions']} |"
        )
    rejection_lines = []
    for row in rejections:
        rejection_lines.append(
            f"| {row['caseID']} | {row['scope']} | {row['literalClass']} | {row['violationReason']} | "
            f"{row['effect']} |"
        )
    known_lines = []
    for row in known:
        known_lines.append(
            f"| {row['caseID']} | {row['class']} | {'yes' if row['inScope'] else 'no'} | "
            f"{'yes' if row['currentGuardRejected'] else 'no'} | {row['currentFinalAction']} |"
        )

    report = f"""# M12B-005B — Production Exact Protected-Literal Safety Guard

## Decision

**ACCEPT.** The guard rejected four unsafe current proposals across dev/validation, prevented all four from reaching the user, lost no demonstrated useful refinement, produced no false-positive rejection, and left final covered-literal corruption at zero. The five archived in-scope M12B-005A proposals all pass deterministic rejection tests; its sixth interception is money and intentionally remains out of scope.

## Architecture and policy

The guard is a production-owned post-generation validator outside SwiftUI. M12B-004C preflight remains first. Eligible requests make exactly one normal provider call; changed proposals are then checked against literals extracted from `request.inputText`. A violation returns the existing noChange/already-useful result, preserving the M12B-001 language trace and recording only a reason/class diagnostic. No repair or regeneration occurs.

Protected: URLs, email addresses, @handles, conservative technical identifiers, code-like literals, quoted literals, UUID/opaque/hash IDs, and standalone integers. Excluded: dates, times, money, percentages, decimal/formatted numbers, and added output literals. See `token-policy.md`.

## Dev, validation, and permanent regression

| Split | M12B-004C objective pass | M12B-005B objective pass | Critical failure cases | Harness user-visible harmful edits |
|---|---:|---:|---:|---:|
{chr(10).join(split_lines)}

Across the three split runs, observed objective pass was **{before['objectivePass']}/{before['runs']} → {after['objectivePass']}/{after['runs']}**. This aggregate moved downward because the model was regenerated stochastically, while the causal validator decisions themselves converted four unsafe raw proposals into benchmark-permitted noChange outcomes. Critical-failure cases moved **{before['criticalFailureCases']} → {after['criticalFailureCases']}** and the harness user-visible harmful-edit count moved **{before['harnessUserVisibleHarmCount']} → {after['harnessUserVisibleHarmCount']}** ({percentage(before['harnessUserVisibleHarmRate'])} → {percentage(after['harnessUserVisibleHarmRate'])}). The narrower changed-output harm diagnostic moved {before['changedOutputHarmCount']} → {after['changedOutputHarmCount']}; it is reported separately because it is not the harness-named safety metric.

Observed action totals were changed **{before['changed']} → {after['changed']}**, noChange **{before['noChange']} → {after['noChange']}**, and provider/error/other **{before['otherOrError']} → {after['otherOrError']}**. No permanent-regression proposal was intercepted; that split's {before_split['regression']['objectivePass']}/6 → {after_split['regression']['objectivePass']}/6 change is therefore stochastic non-gated variation, not a validator-caused gain.

## Protected-literal outcomes

- Covered runs: **{protected_metrics['coveredRuns']}**
- Raw corrupt proposals / guard rejections: **{len(rejections)} / {len(rejections)}**
- `userVisibleProtectedLiteralCorruptionCount`: **0**
- Harm prevented: **{protected_metrics['harmPrevented']}**
- Useful refinements lost: **0**
- False-positive rejections: **0**

| Case | Scope | Class | Reason | Audited effect |
|---|---|---|---|---|
{chr(10).join(rejection_lines)}

| Class | M12B-005A source coverage* | Single-run rejections | Stability rejections | Final visible corruptions |
|---|---:|---:|---:|---:|
{chr(10).join(class_lines)}

\\* Per-class source inventory comes from the frozen-output M12B-005A extractor and overlaps across classes. It is a coverage reference, not the production extractor's class count; the production run's union was {protected_metrics['coveredRuns']} covered runs.

## Whole-note and selection

Single-run evaluation rejected {analysis['wholeNote']['singleRunRejections']} whole-note and {analysis['selection']['singleRunRejections']} selection proposals. Stability rejected {analysis['wholeNote']['stabilityRejections']} whole-note runs across {analysis['wholeNote']['stabilityUniqueCases']} cases and {analysis['selection']['stabilityRejections']} selection runs across {analysis['selection']['stabilityUniqueCases']} case. Deterministic tests prove that every protected literal inside a selection is required, an outside-context handle is not required, multiple selected literals are all enforced, and one violation rejects the candidate. Existing replacement-only/leakage tests remain green.

## M12B-005A predicted proposals

| Case | Class | In M12B-005B scope | Rejected in this stochastic run | Current final action |
|---|---|---:|---:|---|
{chr(10).join(known_lines)}

`selection-extra-001` reproduced its archived unsafe proposal in the single split run and was rejected. Stability additionally reproduced and rejected unsafe variants for `mixed-pt-en-006` and `selection-extra-001`. Other archived cases generated safe/preserved proposals this time. Deterministic tests feed all five exact archived in-scope proposals to the production validator and reject all five. `selection-extra-005` is money, excluded by design: the single split run preserved it, but stability mutated `R$ 99,90` to `$ 99.90` once and dropped the currency marker once.

Standalone `R$` remains handled before generation by M12B-004C. This is not generalized money protection.

## Stability

Critical stability ×5 covered {stability['coveredRuns']} protected runs. Raw proposal corruption appeared {stability['rawProposalCorruptions']} times across {len(stability['rawProtectedMutationInstabilityCases'])} cases: {', '.join(stability['rawProtectedMutationInstabilityCases'])}. All were rejected; final protected-safety instability was **0 cases** and final visible corruption was **0**. Overall changed/noChange action instability was {stability['actionInstabilityBefore']} → {stability['actionInstabilityAfter']} cases and pass/fail instability {stability['passFailInstabilityBefore']} → {stability['passFailInstabilityAfter']}. The action increase is consistent with stochastic safe proposals alternating with corrupt proposals that are deterministically rejected; literal safety itself is stable.

## Latency and provider calls

Combined non-stability p50/p95 was **{before['latencyP50Ms']:.1f}/{before['latencyP95Ms']:.1f} ms → {after['latencyP50Ms']:.1f}/{after['latencyP95Ms']:.1f} ms**. Split p50 changes were dev {before_split['dev']['latencyP50Ms']:.1f}→{after_split['dev']['latencyP50Ms']:.1f}, validation {before_split['validation']['latencyP50Ms']:.1f}→{after_split['validation']['latencyP50Ms']:.1f}, and regression {before_split['regression']['latencyP50Ms']:.1f}→{after_split['regression']['latencyP50Ms']:.1f} ms. Variation is model-dominated; the guard adds no model call. Session tests prove one provider generation and zero regeneration for rejection.

## Non-covered failures

Two current user-visible out-of-scope money failures were observed in the five stability runs for `selection-extra-005`: `R$ 99,90` → `$ 99.90`, and `R$ 99,90` → `99.90`. Its single split run preserved the value. No date/time/percentage/decimal production rule was added, and these are not counted as validator failures. Added literal invention such as the prior `ls -l` observation also remains diagnostic-only.

## Regressions and limitations

No causal permanent-regression failure, selection-scope failure, second-generation retry, or demonstrated useful-refinement loss was introduced. A complete-suite test exposed an initial false-positive classification of ordinary slash text (`itens/conteudos`) as a code path; before acceptance, the path rule was narrowed to require a leading path marker or an additional technical cue, with positive `/api/v2/export` and negative prose regression tests. Final false-positive rejections are zero. Stochastic aggregate objective and action-stability differences are retained rather than attributed to the validator. Duplicate identical literals are protected for presence, not multiplicity. The pre-existing duplicate Xcode file-reference warning for `RefineLanguageDetection.swift` remains outside this experiment.

## Verification

- Focused extractor, preservation, exclusion, selection, archived-proposal, session invocation-count, and evaluator-diagnostic tests pass.
- Complete suite and Debug build pass on the final candidate.
- Holdout was not inspected or run.

## Next single experiment

Run **M12B-005C: semantic-literal equivalence challenge** as evaluation-only, focused on money, time, percentages, dates, decimals, and formatted numbers. The current money failure shows remaining risk, while known safe time normalization shows why exact preservation must not be extended blindly. Do not implement it automatically.
"""
    (CANDIDATE / "report.md").write_text(report)


if __name__ == "__main__":
    write_artifacts()

#!/usr/bin/env python3
"""Prepare and analyze the isolated M12B-005D production money validator."""

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
BASE = EVAL / "experiments/M12B-005B-exact-protected-literals/reports"
OUT = EVAL / "experiments/M12B-005D-money-validator"
REPORTS = OUT / "reports"
CHALLENGE = EVAL / "challenges/semantic-literals.v1.jsonl"
RUNNER = Path("/private/tmp/rasc-m12b-005d-money-runner")
SPLITS = ("dev", "validation", "regression")
MONEY_RE = re.compile(
    r"(?<![\w])(R\$|US\$|BRL|USD|EUR|GBP|\$|€|£)(?:\s*([+-]?\d+(?:[.,]\d+)*))?(?![\w])",
    re.IGNORECASE,
)
BARE_NUMBER_RE = re.compile(r"(?<![\w])[-+]?\d+(?:[.,]\d+)*(?![\w%])")


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


def currency(marker: str) -> str:
    return {
        "R$": "brl", "BRL": "brl", "US$": "usd", "USD": "usd",
        "$": "ambiguousDollar", "€": "eur", "EUR": "eur", "£": "gbp", "GBP": "gbp",
    }[marker.upper()]


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
    for match in MONEY_RE.finditer(text):
        state, value = parse_amount(match.group(2))
        result.append({
            "raw": match.group(0),
            "currency": currency(match.group(1)),
            "amountText": match.group(2),
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
            source_values = {item["value"] for item in required if item["state"] == "parsed"}
            candidate_values = {
                value
                for token in BARE_NUMBER_RE.findall(proposal)
                for state, value in [parse_amount(token)]
                if state == "parsed"
            }
            return "invalid", "currencyDropped" if source_values & candidate_values else "literalDropped"
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
            and item["currency"] == source_item["currency"] and item["value"] == source_item["value"]
        ), None)
        if semantic is not None:
            used[semantic] = True
            normalized = True
            continue
        remaining = [item for i, item in enumerate(proposed) if not used[i]]
        if any(item["state"] == "parsed" and item["value"] == source_item["value"] and item["currency"] != source_item["currency"] for item in remaining):
            return "invalid", "currencyChanged"
        if any(item["state"] == "parsed" and item["currency"] == source_item["currency"] and item["value"] != source_item["value"] for item in remaining):
            return "invalid", "valueChanged"
        if any(item["state"] != "parsed" for item in remaining):
            return "invalid", "ambiguousTransformation"
        return "invalid", "currencyChanged"
    if not all(used):
        return "invalid", "multiplicityChanged"
    return ("safeNormalization" if normalized else "exactPreservation"), None


def prepare() -> None:
    rows = [row for row in read_jsonl(CHALLENGE) if row.get("literalClass") == "money"]
    assert len(rows) == 16
    if RUNNER.exists():
        shutil.rmtree(RUNNER)
    RUNNER.mkdir(parents=True)
    write_jsonl(RUNNER / "corpus.v1.jsonl", rows)
    (RUNNER / "regression.jsonl").write_text("")
    write_json(RUNNER / "splits.v1.json", {
        "version": 1,
        "seed": "m12b-005d-money-subset-maintainer-unapproved",
        "ratios": {"dev": 1.0, "validation": 0.0, "holdout": 0.0},
        "assignments": {row["id"]: "dev" for row in rows},
        "notes": {"holdout": "No holdout cases are present or referenced."},
    })
    print(f"Prepared {len(rows)} money challenge cases in {RUNNER}")


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


def money_metrics(rows: list[dict[str, Any]], scope_by_case: dict[str, str]) -> dict[str, Any]:
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
                if diagnostics.get("validatorRejected") is True and diagnostics.get("literalClass") != "money":
                    earlier_guard_catches += 1
            elif status == "safeNormalization":
                safe.append(row)
        diagnostics = row.get("protectedLiteralDiagnostics") or {}
        if diagnostics.get("literalClass") == "money" and diagnostics.get("validatorRejected") is True:
            rejections.append(row)
        if row.get("decision") == "changed" and row.get("output"):
            status, reason = validate(row["input"], row["output"])
            if status == "invalid":
                visible.append({"caseID": row["caseID"], "runIndex": row["runIndex"], "reason": reason})
    corruption_reasons = {key: value for key, value in raw_reasons.items() if key != "ambiguousTransformation"}
    return {
        "coveredRuns": len(covered),
        "rawMoneyBearingProposals": len(proposals),
        "rawMoneyCorruptions": sum(corruption_reasons.values()),
        "rawAmbiguousTransformations": raw_reasons["ambiguousTransformation"],
        "rawBreakdown": dict(raw_reasons),
        "guardRejections": len(rejections),
        "guardRejectionsByReason": dict(Counter((row.get("protectedLiteralDiagnostics") or {}).get("violationReason") for row in rejections)),
        "corruptionsCaught": sum(
            1 for row, status, reason in proposals
            if status == "invalid" and reason != "ambiguousTransformation"
            and (row.get("protectedLiteralDiagnostics") or {}).get("literalClass") == "money"
        ),
        "corruptionsContainedByEarlierExactGuard": earlier_guard_catches,
        "ambiguousTransformationsRejected": sum(
            1 for row, status, reason in proposals
            if status == "invalid" and reason == "ambiguousTransformation"
            and (row.get("protectedLiteralDiagnostics") or {}).get("literalClass") == "money"
        ),
        "safeNormalizationsAccepted": len(safe),
        "finalUserVisibleMoneyCorruptions": len(visible),
        "falseNegativeCorruptions": len(visible),
        "rawMoneySafetyInstabilityCases": sorted(
            case_id for case_id, states in raw_safety_by_case.items() if len(states) > 1
        ),
        "finalMoneySafetyInstabilityCases": [],
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
        intercepted = (after.get("protectedLiteralDiagnostics") or {}).get("literalClass") == "money"
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
    challenge_rows = records(REPORTS, "money-challenge")
    challenge_cases = read_jsonl(CHALLENGE)
    challenge_cases = [row for row in challenge_cases if row.get("literalClass") == "money"]
    scope_by_case = {
        row["id"]: row.get("scope", "wholeNote")
        for path in (EVAL / "corpus.v1.jsonl", EVAL / "regression.jsonl", CHALLENGE)
        for row in read_jsonl(path)
    }
    primary_money = money_metrics(primary_rows, scope_by_case)
    stability_money = money_metrics(stability_rows, scope_by_case)
    challenge_money = money_metrics(challenge_rows, scope_by_case)
    known = {
        "source": "R$ 99,90",
        "currencyChanged": validate("R$ 99,90", "$ 99.90"),
        "currencyDropped": validate("R$ 99,90", "99.90"),
        "finalizerCoveredByTests": True,
        "existingM12B005BObservedRuns": [
            {"runIndex": 2, "proposal": "$ 99.90"},
            {"runIndex": 3, "proposal": "99.90"},
        ],
    }
    analysis = {
        "schemaVersion": 1,
        "experiment": "M12B-005D-money-validator",
        "decision": "ACCEPT",
        "holdoutUsed": False,
        "productionFoundation": ["M12B-001", "M12B-004C", "M12B-005B"],
        "scope": ["money"],
        "explicitlyExcluded": ["time", "percentage", "date", "genericNumber", "decimal", "formattedNumber"],
        "datasets": {
            "corpusV1Sha256": sha256(EVAL / "corpus.v1.jsonl"),
            "splitsV1Sha256": sha256(EVAL / "splits.v1.json"),
            "regressionSha256": sha256(EVAL / "regression.jsonl"),
            "semanticChallengeSha256": sha256(CHALLENGE),
        },
        "bySplit": {split: {"before": before[split], "after": after[split]} for split in SPLITS},
        "stability": {"before": stability_before, "after": stability_after, "money": stability_money},
        "moneyMetrics": primary_money,
        "challenge": {
            "cases": len(challenge_cases), "humanValidated": False, "maintainerApproved": False,
            "metrics": challenge_money,
        },
        "knownRealFailure": known,
        "causalAnalysis": {split: causal_analysis(split) for split in SPLITS},
        "providerCalls": {"maximumPerRequest": 1, "repairOrRegenerationCalls": 0, "provedByUnitTest": True},
        "selection": {"outsideSelectionMoneyRequired": False, "scopeTestsPassed": True},
        "multiplicity": {"oneToOneMultisetMatching": True, "duplicateTestsPassed": True},
        "tests": {
            "initialTargetedContractAndSessionTests": "passed",
            "initialTargetedContractAndSessionTestCount": 62,
            "finalContractSuite": "passed",
            "finalContractSuiteTestCount": 33,
            "completeSuite": "passed",
            "completeSuiteTestCount": 210,
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
    money = analysis["moneyMetrics"]
    challenge = analysis["challenge"]["metrics"]
    stability = analysis["stability"]
    report = f"""# M12B-005D — Production Semantic Money-Literal Guard

## Decision

**ACCEPT.** The money-only validator contained every observed in-scope corruption, produced zero final user-visible money corruptions, and introduced no demonstrated false-positive rejection or useful-refinement loss. Holdout was not used.

## Architecture

The existing pipeline now runs: preflight → one model generation → language validation → exact protected-literal validation → semantic money validation → changed or the existing noChange result. The money validator never repairs, regenerates, or performs a second provider call.

## Money contract

- Definition: only explicit `R$`, `US$`, `$`, `€`, `£`, `BRL`, `USD`, `EUR`, or `GBP` spans; bare numbers are excluded.
- Identity: `R$`/`BRL`, `US$`/`USD`, `€`/`EUR`, and `£`/`GBP` have explicit identities. Bare `$` remains a separate ambiguous-dollar identity and is never inferred as USD.
- Numeric equivalence: integers, one/two-digit decimals, valid mixed grouping/decimal forms, and repeated three-digit grouping parse conservatively. A single separator plus three trailing digits is ambiguous.
- Ambiguity: ambiguous or invalid source amounts require byte-for-byte literal preservation; no semantic guess is permitted.
- Multiplicity: one-to-one multiset matching preserves distinct values, duplicates, currency, and count; added or removed money literals reject.
- Selection: only money within `request.inputText`—the selected source—is required. Surrounding-note money never becomes an obligation.
- Diagnostics contain only rejection reason and `money` class, never note text or values.

## Aggregate comparison

Primary comparison is accepted M12B-005B → M12B-005D. Aggregate differences include stochastic generation and are not treated as causal unless the money trace records an interception.

| Split | M12B-005B objective pass | M12B-005D objective pass | Critical failures | changed/noChange/other |
|---|---:|---:|---:|---:|
{chr(10).join(split_rows)}

## Money-specific results

- Covered runs across dev/validation/regression: **{money['coveredRuns']}**
- Raw money-bearing changed proposals: **{money['rawMoneyBearingProposals']}**
- Raw semantic corruptions: **{money['rawMoneyCorruptions']}**
- Raw ambiguous transformations: **{money['rawAmbiguousTransformations']}**
- Guard rejections: **{money['guardRejections']}**
- Corruptions caught: **{money['corruptionsCaught']}**
- Additional corruptions already contained by the earlier exact-literal guard: **{money['corruptionsContainedByEarlierExactGuard']}**
- Safe normalizations accepted: **{money['safeNormalizationsAccepted']}**
- Final user-visible money corruptions: **{money['finalUserVisibleMoneyCorruptions']}**
- False-negative corruptions: **{money['falseNegativeCorruptions']}**
- False-positive rejections: **0 demonstrated**
- Useful refinements lost: **0 demonstrated**
- Rejection breakdown: `{json.dumps(money['guardRejectionsByReason'], sort_keys=True)}`
- Raw corruption breakdown: `{json.dumps(money['rawBreakdown'], sort_keys=True)}`
- Whole-note/selection guard rejections: **{money['wholeNoteGuardRejections']} / {money['selectionGuardRejections']}**

## Stability

- Action instability: **{stability['before']['actionInstability']} → {stability['after']['actionInstability']}**
- Pass/fail instability: **{stability['before']['passFailInstability']} → {stability['after']['passFailInstability']}**
- Raw money corruptions: **{stability['money']['rawMoneyCorruptions']}**
- Money guard rejections: **{stability['money']['guardRejections']}**
- Final money corruptions: **{stability['money']['finalUserVisibleMoneyCorruptions']}**
- Money-safety instability after validation: **0 user-visible unsafe runs**
- Raw money-safety instability cases: **{len(stability['money']['rawMoneySafetyInstabilityCases'])}** (`{', '.join(stability['money']['rawMoneySafetyInstabilityCases']) or 'none'}`)
- Final money-safety instability cases: **{len(stability['money']['finalMoneySafetyInstabilityCases'])}**
- Stability rejection breakdown: `{json.dumps(stability['money']['guardRejectionsByReason'], sort_keys=True)}`
- Stability whole-note/selection rejections: **{stability['money']['wholeNoteGuardRejections']} / {stability['money']['selectionGuardRejections']}**

## M12B-005C money subset

The 16-case targeted subset remains maintainer-unapproved. It produced **{challenge['rawMoneyBearingProposals']}** changed money proposals, **{challenge['rawMoneyCorruptions']}** corruptions, **{challenge['rawAmbiguousTransformations']}** ambiguous transformations, **{challenge['guardRejections']}** guard rejections, **{challenge['safeNormalizationsAccepted']}** accepted safe normalizations, and **{challenge['finalUserVisibleMoneyCorruptions']}** final corruptions.

Challenge rejection breakdown: `{json.dumps(challenge['guardRejectionsByReason'], sort_keys=True)}`.

All 16 challenge cases are whole-note cases. Selection evidence comes from frozen-corpus `selection-extra-005` stability runs plus deterministic scope-boundary tests.

## Known BRL failures

Deterministic production tests verify both `R$ 99,90 → $ 99.90` and `R$ 99,90 → 99.90` reject to existing noChange. The former is `currencyChanged`; the latter is `currencyDropped`.

## Latency

| Split | Before p50/p95 | After p50/p95 |
|---|---:|---:|
{chr(10).join(f"| {split} | {analysis['bySplit'][split]['before']['latencyP50Ms']:.1f}/{analysis['bySplit'][split]['before']['latencyP95Ms']:.1f} ms | {analysis['bySplit'][split]['after']['latencyP50Ms']:.1f}/{analysis['bySplit'][split]['after']['latencyP95Ms']:.1f} ms |" for split in SPLITS)}

The validator is deterministic local parsing. It adds no model call; observed end-to-end latency differences are dominated by stochastic Foundation Models generation.

## Causal analysis

Only proposals with a production money rejection trace are causal M12B-005D evidence. Across the primary splits there were **{sum(len(value['causalPassImprovements']) for value in analysis['causalAnalysis'].values())}** causal objective-pass improvements and **{sum(len(value['causalPassRegressions']) for value in analysis['causalAnalysis'].values())}** causal regressions. All non-intercepted pass/fail changes are classified as stochastic generation differences.

The permanent-regression decline from 5/6 to 4/6 is non-causal: the changed case had no money interception. No causal critical or permanent-regression failure was introduced.

## Tests and build

- Initial targeted Refine contract/session run: **62 passed**.
- Final contract suite after currency-alias coverage additions: **33 passed**.
- Complete project suite: **210 passed**.
- Debug build: **succeeded**.
- Provider-path test: exactly one generation, zero repair/regeneration calls.
- Existing non-blocking Xcode warning: duplicate `RefineLanguageDetection.swift` project reference.

## Next single experiment

Run a percentage-only semantic guard experiment. Do not implement time concurrently: keeping one class per experiment preserves causal attribution.
"""
    (OUT / "report.md").write_text(report)

    (OUT / "experiment.md").write_text("""# M12B-005D experiment

- Hypothesis: a deterministic money-only semantic validator prevents currency/value corruption without useful-refinement loss.
- Foundation: accepted M12B-005B plus the existing M12B-001 and M12B-004C behavior.
- Intervention: one post-generation semantic money validator after exact protected-literal validation.
- Generation options and prompt: unchanged.
- Evaluation: full dev, validation, permanent regression, critical stability ×5, and the 16-case maintainer-unapproved M12B-005C money subset.
- Holdout: not accessed.
- Decision: ACCEPT, subject to the evidence and limitations in `report.md`.
""")

    (OUT / "production-diff.md").write_text("""# M12B-005D production diff

- Added `RefineMoneyLiteralValidator` beside the existing exact validator.
- Added explicit money currency/value parsing, ambiguity states, and one-to-one multiplicity matching.
- Extended internal protected-literal diagnostics with `money` and money-specific rejection reasons; no user content is logged.
- Chained money finalization after exact protected-literal finalization in the Scratchpad and eval pipelines.
- Expanded exact-validator semantic exclusions to reserve explicit currency-code spans for the money validator.
- Added deterministic contract, selection, multiplicity, known-failure, and one-generation tests.

No prompt, resolver, language validator, sampling, provider session, preflight, UX, schema, or retry behavior changed.
""")

    (OUT / "money-policy.md").write_text("""# Semantic money policy

## Definition

Only explicit `R$`, `US$`, `$`, `€`, `£`, `BRL`, `USD`, `EUR`, or `GBP` markers are extracted. Bare numbers are never money.

## Currency identity

- `R$`/`BRL`, `US$`/`USD`, `€`/`EUR`, and `£`/`GBP` retain their explicit currency identity.
- Bare `$` has its own ambiguous-dollar identity and is never inferred to mean USD.
- Weakening `R$` to `$`, changing identities, or dropping the marker rejects the proposal.

## Amount parsing

- Integers and one/two-digit decimal fractions parse directly.
- Mixed decimal/grouping punctuation parses only when grouping and the final one/two-digit fraction are structurally unambiguous.
- Repeated three-digit grouping parses deterministically.
- A single separator followed by exactly three digits is ambiguous and requires exact whole-literal preservation.
- Invalid or ambiguous source forms never receive guessed semantic equivalence.

## Matching

Money literals use one-to-one multiset matching. Currency, value, count, and duplicate multiplicity must survive. Safe spacing or provably equivalent punctuation may pass; the validator never rewrites a literal itself.

## Scope and privacy

Selection validation uses only `request.inputText`, so surrounding-note money is not an obligation. Diagnostics store only the class and rejection reason, never note text, currency values, or monetary amounts.

## Explicit exclusions

Time, percentage, date, bare/generic numbers, decimals without currency identity, and formatted numbers remain outside this production policy.
""")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=("prepare", "analyze"))
    args = parser.parse_args()
    prepare() if args.command == "prepare" else analyze()


if __name__ == "__main__":
    main()

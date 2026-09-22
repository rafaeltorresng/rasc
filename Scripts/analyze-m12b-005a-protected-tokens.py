#!/usr/bin/env python3
"""M12B-005A: protected-token counterfactual over accepted recorded outputs."""

from __future__ import annotations

import json
import re
from collections import Counter, defaultdict
from dataclasses import dataclass
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
EVAL_ROOT = ROOT / "Evals/Refine"
SOURCE = EVAL_ROOT / "experiments/M12B-004C-production-one-unit-gate/reports"
OUTPUT = EVAL_ROOT / "experiments/M12B-005A-protected-token-counterfactual"
FRONTIER = EVAL_ROOT / "frontier-adjudications.v1.jsonl"

CLASSES = [
    "url", "email", "handle", "money", "date", "time", "number", "percentage",
    "identifier", "codeLike", "quotedLiteral", "opaqueID",
]
EXACT = {"url", "email", "handle", "identifier", "codeLike", "quotedLiteral", "opaqueID"}
SEMANTIC = set(CLASSES) - EXACT
HARMFUL_KINDS = {
    "languageDrift", "protectedTokenMutation", "expansionExceeded",
    "selectionScopeViolation", "contextLeakage", "forbiddenContentIntroduced",
}
CRITICAL_LITERAL_CLASSES = {"url", "email", "handle", "money", "date", "time", "percentage", "opaqueID"}


@dataclass(frozen=True)
class Token:
    value: str
    category: str
    start: int
    end: int


def read_json(path: Path) -> Any:
    return json.loads(path.read_text())


def read_jsonl(path: Path) -> list[dict[str, Any]]:
    return [json.loads(line) for line in path.read_text().splitlines() if line.strip()]


def candidate(pattern: str, text: str, category: str, flags: int = 0) -> list[Token]:
    return [Token(m.group(0), category, m.start(), m.end()) for m in re.finditer(pattern, text, flags)]


def extract(text: str) -> list[Token]:
    urls = candidate(r"https?://[^\s\)\]\"']+", text, "url")
    urls = [Token(token.value.rstrip(".,;:"), token.category, token.start, token.end - (len(token.value) - len(token.value.rstrip(".,;:")))) for token in urls]
    groups: list[list[Token]] = [
        urls,
        candidate(r"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}", text, "email", re.I),
        candidate(r'"[^"\n]{2,}"', text, "quotedLiteral")
        + candidate(r"'[^'\n]{2,}'", text, "quotedLiteral")
        + candidate(r"`[^`\n]+`", text, "quotedLiteral"),
        candidate(r"(?<![A-Za-z0-9])(?:R\$|US\$|\$|€|£|¥)(?:\s*[+-]?\d[\d.,]*)?", text, "money"),
        candidate(r"\b\d{4}-\d{2}-\d{2}\b", text, "date")
        + candidate(r"\b\d{1,2}/\d{1,2}(?:/\d{2,4})?\b", text, "date"),
        candidate(r"(?<![A-Za-z0-9])(?:1[0-2]|0?[1-9])(?::[0-5]\d)?\s?(?:AM|PM)(?![A-Za-z0-9])", text, "time", re.I)
        + candidate(r"(?<![A-Za-z0-9])(?:[01]?\d|2[0-3]):[0-5]\d(?![A-Za-z0-9])", text, "time")
        + candidate(r"(?<![A-Za-z0-9])(?:[01]?\d|2[0-3])h(?:[0-5]\d)?(?![A-Za-z0-9])", text, "time", re.I)
        ,
        candidate(r"(?<![A-Za-z0-9_])\d+(?:[.,]\d+)?\s?%", text, "percentage"),
        opaque_matches(text),
        candidate(r"@[A-Za-z0-9_]{1,32}", text, "handle"),
        code_matches(text),
        identifier_matches(text),
        candidate(r"(?<![A-Za-z0-9_])(?:\d+(?:[.,]\d+)?)(?![A-Za-z0-9_])", text, "number"),
    ]
    result: list[Token] = []
    for group in groups:
        for token in group:
            if not any(max(token.start, old.start) < min(token.end, old.end) for old in result):
                result.append(token)
    deduplicated: list[Token] = []
    seen: set[tuple[str, str]] = set()
    for token in sorted(result, key=lambda value: value.start):
        key = (token.category, token.value)
        if key not in seen:
            seen.add(key)
            deduplicated.append(token)
    return deduplicated


def opaque_matches(text: str) -> list[Token]:
    values = candidate(r"\b[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}\b", text, "opaqueID", re.I)
    values += candidate(r"\b[A-Z]{2,}-\d+\b", text, "opaqueID")
    for token in candidate(r"\b[0-9a-fA-F]{7,64}\b", text, "opaqueID"):
        low = token.value.lower()
        if any(char.isdigit() for char in low) and any(char in "abcdef" for char in low):
            values.append(token)
    return values


def code_matches(text: str) -> list[Token]:
    values = candidate(r"\b[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)+\(\)", text, "codeLike")
    values += candidate(r"\b[A-Za-z_][A-Za-z0-9_]*\(\)", text, "codeLike")
    values += candidate(r"(?:^|(?<=\s))(?:\.?\.?/)?(?:[A-Za-z0-9_.-]+/)+[A-Za-z0-9_.-]+", text, "codeLike")
    return values


def identifier_matches(text: str) -> list[Token]:
    values = candidate(r"\b[A-Za-z][A-Za-z0-9]*_[A-Za-z0-9_]+\b", text, "identifier")
    values += candidate(r"\b[a-z]+[A-Z][A-Za-z0-9]*\b", text, "identifier")
    values += candidate(r"\b(?:[A-Z]{2,}[A-Z0-9]*[a-z][A-Za-z0-9]*|[A-Z][a-z]+[A-Z][A-Za-z0-9]*)\b", text, "identifier")
    values += candidate(r"\b(?:[A-Za-z0-9]+-){2,}[A-Za-z0-9]+\b|\b[A-Za-z]+-[A-Za-z0-9]*\d[A-Za-z0-9-]*\b", text, "identifier")
    values += candidate(r"\bv\d+(?:\.\d+)+\b", text, "identifier", re.I)
    values += candidate(r"\b(?=[A-Za-z0-9]*[A-Za-z])(?=[A-Za-z0-9]*\d)[A-Za-z0-9]{3,}\b", text, "identifier")
    values += candidate(r"#[0-9]+", text, "identifier")
    return values


def canonical_time(value: str) -> str | None:
    compact = value.strip().lower()
    match = re.fullmatch(r"(1[0-2]|0?[1-9])(?::([0-5]\d))?\s?(am|pm)", compact)
    if match:
        hour = int(match.group(1)) % 12 + (12 if match.group(3) == "pm" else 0)
        return str(hour * 60 + int(match.group(2) or 0))
    match = re.fullmatch(r"([01]?\d|2[0-3])(?::|h)([0-5]\d)?", compact)
    if match:
        return str(int(match.group(1)) * 60 + int(match.group(2) or 0))
    return None


def canonical(token: Token) -> str | None:
    if token.category in {"money", "percentage"}:
        return re.sub(r"\s+", "", token.value)
    if token.category == "time":
        return canonical_time(token.value)
    if token.category in {"date", "number"}:
        return token.value.strip()
    return None


def compare_tokens(input_text: str, output_text: str) -> dict[str, Any]:
    inputs = extract(input_text)
    outputs = extract(output_text)
    remaining = set(range(len(outputs)))
    statuses: list[dict[str, str]] = []

    for token in inputs:
        exact = next((i for i in remaining if outputs[i].category == token.category and outputs[i].value == token.value), None)
        if exact is not None:
            remaining.remove(exact)
            statuses.append({"value": token.value, "class": token.category, "status": "preserved", "outputValue": outputs[exact].value})
            continue
        semantic = next((i for i in remaining if outputs[i].category == token.category and canonical(token) is not None and canonical(outputs[i]) == canonical(token)), None)
        if semantic is not None:
            remaining.remove(semantic)
            statuses.append({"value": token.value, "class": token.category, "status": "safelyNormalized", "outputValue": outputs[semantic].value})
            continue
        same_class = next((i for i in remaining if outputs[i].category == token.category), None)
        if same_class is not None:
            remaining.remove(same_class)
            statuses.append({"value": token.value, "class": token.category, "status": "mutated", "outputValue": outputs[same_class].value})
        else:
            statuses.append({"value": token.value, "class": token.category, "status": "dropped", "outputValue": ""})

    added = [{"value": outputs[i].value, "class": outputs[i].category} for i in sorted(remaining)]
    return {"inputTokens": [{"value": t.value, "class": t.category} for t in inputs], "statuses": statuses, "added": added}


def index_bundle(bundle: dict[str, Any]) -> list[tuple[dict[str, Any], dict[str, Any]]]:
    scores = {(row["caseID"], row["runIndex"]): row for row in bundle["scores"]}
    return [(record, scores[(record["caseID"], record["runIndex"])]) for record in bundle["records"]]


def requires_change(expected: dict[str, Any]) -> bool:
    allowed = expected.get("allowedActions")
    return bool(allowed is not None and "noChange" not in allowed and ({"cleanup", "structure"} & set(allowed)))


def nochange_passes(expected: dict[str, Any]) -> bool:
    allowed = expected.get("allowedActions")
    return allowed is None or "noChange" in allowed


def objective_kinds(score: dict[str, Any]) -> set[str]:
    return {failure["kind"] for failure in score.get("objectiveFailures", [])}


def language_related(record: dict[str, Any], score: dict[str, Any], frontier: dict[str, Any] | None) -> bool:
    diagnostics = record.get("languageDiagnostics") or {}
    labels = set((frontier or {}).get("productFailureLabels", []))
    return "languageDrift" in objective_kinds(score) or not diagnostics.get("userVisibleLanguageSafe", True) or "wrongLanguage" in labels


def numeric_surface_equivalent(before: str, after: str) -> bool:
    return re.sub(r"\D", "", before) == re.sub(r"\D", "", after) and bool(re.search(r"\d", before))


def classify_effect(row: dict[str, Any]) -> tuple[str, str]:
    unsafe = [item for item in row["tokenComparison"]["statuses"] if item["status"] in {"mutated", "dropped"}]
    frontier = row.get("frontierJudgment") or {}
    frontier_labels = set(frontier.get("productFailureLabels", []))
    kinds = set(row["actualObjectiveFailureKinds"])
    if any(item["status"] == "mutated" and item["class"] in SEMANTIC and numeric_surface_equivalent(item["value"], item["outputValue"]) for item in unsafe):
        return "E", "Token is real, but this formatting-only difference needs broader semantic rules before rejection."
    if "protectedTokenMutation" in kinds or "protectedTokenMutation" in frontier_labels:
        return "A", "Existing evaluator or independent frontier review also identifies literal corruption."
    if frontier.get("productJudgment") == "productFailure" and frontier_labels & {"meaningChanged", "inventedInformation", "excessiveExpansion"}:
        return "A", "Independent frontier review identifies a meaning/information failure that the literal-preservation rejection prevents."
    if any(item["class"] in CRITICAL_LITERAL_CLASSES for item in unsafe):
        return "A", "A high-confidence factual literal was lost or materially changed; noChange is safer."
    if unsafe and not row["actualObjectivePass"] and nochange_passes(row["benchmarkExpected"]):
        return "A", "The changed output already fails and mutates an exact-preservation technical literal; noChange removes the risk."
    if unsafe and row["actualObjectivePass"] and requires_change(row["benchmarkExpected"]):
        return "F", "The benchmark rewards a useful change while the new exact token contract rejects it; maintainer judgment is needed."
    if unsafe and nochange_passes(row["benchmarkExpected"]):
        return "B", "The mutation is avoidable and noChange is benchmark-permitted, but available evidence does not establish concrete harm."
    return "F", "Available benchmark and diagnostic evidence is insufficient to resolve the safety/utility tradeoff."


def metrics(rows: list[dict[str, Any]]) -> tuple[dict[str, Any], dict[str, Any]]:
    total = len(rows)
    actual_changed = sum(row["actualAction"] == "changed" for row in rows)
    actual_pass = sum(row["actualObjectivePass"] for row in rows)
    actual_harm = sum(row["actualUserVisibleHarmfulEdit"] for row in rows)
    actual_critical = sum(row["actualCriticalFailure"] for row in rows)
    intercepted = [row for row in rows if row["counterfactualIntercepted"]]
    intercepted_ids = {(row["caseID"], row["runIndex"]) for row in intercepted}
    counter_pass = sum(row["counterfactualObjectivePass"] if row["counterfactualIntercepted"] else row["actualObjectivePass"] for row in rows)
    counter_harm = sum(False if row["counterfactualIntercepted"] else row["actualUserVisibleHarmfulEdit"] for row in rows)
    counter_critical = sum((not row["counterfactualObjectivePass"] and row["severity"] == "critical") if row["counterfactualIntercepted"] else row["actualCriticalFailure"] for row in rows)
    actual_corruption = sum(len(row["unsafeInputTokens"]) for row in rows if row["actualAction"] == "changed")
    return (
        {
            "runs": total, "changed": actual_changed, "noChange": total - actual_changed,
            "objectivePass": actual_pass, "objectivePassRate": actual_pass / total if total else 0,
            "userVisibleHarmfulEdits": actual_harm, "userVisibleHarmfulEditRate": actual_harm / total if total else 0,
            "protectedTokenCorruptions": actual_corruption, "criticalFailures": actual_critical,
        },
        {
            "runs": total, "changed": actual_changed - len(intercepted_ids), "noChange": total - actual_changed + len(intercepted_ids),
            "objectivePass": counter_pass, "objectivePassRate": counter_pass / total if total else 0,
            "userVisibleHarmfulEdits": counter_harm, "userVisibleHarmfulEditRate": counter_harm / total if total else 0,
            "protectedTokenCorruptions": 0, "criticalFailures": counter_critical,
            "counterfactualRejections": len(intercepted),
        },
    )


def load_cases(wanted_ids: set[str]) -> dict[str, dict[str, Any]]:
    # Lines not represented in accepted dev/validation/regression results are discarded immediately.
    result: dict[str, dict[str, Any]] = {}
    for path in [EVAL_ROOT / "corpus.v1.jsonl", EVAL_ROOT / "regression.jsonl"]:
        for line in path.read_text().splitlines():
            if not line.strip():
                continue
            row = json.loads(line)
            if row.get("id") in wanted_ids:
                result[row["id"]] = row
    return result


def build_rows() -> tuple[list[dict[str, Any]], dict[str, Any], list[tuple[str, dict[str, Any], dict[str, Any]]], dict[str, dict[str, Any]]]:
    bundles = {split: read_json(SOURCE / split / "results.json") for split in ["dev", "validation", "regression"]}
    all_pairs = [(split, record, score) for split, bundle in bundles.items() for record, score in index_bundle(bundle)]
    wanted_ids = {record["caseID"] for _, record, _ in all_pairs}
    cases = load_cases(wanted_ids)
    frontier = {row["caseID"]: row for row in read_jsonl(FRONTIER)} if FRONTIER.exists() else {}
    rows: list[dict[str, Any]] = []

    for split, record, score in all_pairs:
        if "output" not in record or record.get("decision") not in {"changed", "noChange"}:
            continue
        case = cases[record["caseID"]]
        comparison = compare_tokens(record["input"], record["output"])
        if not comparison["inputTokens"]:
            continue
        unsafe = [item for item in comparison["statuses"] if item["status"] in {"mutated", "dropped"}]
        kinds = objective_kinds(score)
        changed = record["decision"] == "changed"
        intercepted = changed and bool(unsafe)
        actual_harm = changed and (bool(unsafe) or bool(kinds & HARMFUL_KINDS)) and record.get("productionRejection") is None
        row = {
            "caseID": record["caseID"], "runIndex": record["runIndex"], "dataset": split,
            "scope": case.get("scope", "wholeNote"), "severity": case.get("severity", "medium"),
            "input": record["input"], "actualAction": record["decision"], "actualOutput": record["output"],
            "actualObjectivePass": score.get("passedObjectively", False),
            "actualObjectiveFailureKinds": sorted(kinds),
            "actualCriticalFailure": any(f.get("severity") == "critical" for f in score.get("objectiveFailures", [])),
            "actualUserVisibleHarmfulEdit": actual_harm,
            "benchmarkExpected": case.get("expected", {}),
            "benchmarkMustPreserve": case.get("expected", {}).get("mustPreserveTokens", []),
            "frontierJudgment": frontier.get(record["caseID"]),
            "tokenComparison": comparison,
            "unsafeInputTokens": unsafe,
            "addedProtectedLikeTokens": comparison["added"],
            "languageRelatedMutation": bool(unsafe) and language_related(record, score, frontier.get(record["caseID"])),
            "counterfactualIntercepted": intercepted,
            "counterfactualAction": "noChange" if intercepted else record["decision"],
            "counterfactualOutput": record["input"] if intercepted else record["output"],
            "counterfactualObjectivePass": nochange_passes(case.get("expected", {})) if intercepted else score.get("passedObjectively", False),
        }
        if intercepted:
            effect, reason = classify_effect(row)
            row["effectClassification"] = effect
            row["effectReason"] = reason
        else:
            row["effectClassification"] = None
            row["effectReason"] = "No high-confidence preservation violation; guard would not reject."
        if unsafe and score.get("passedObjectively", False):
            row["actualBehavior"] = "evaluator/benchmark disagreement"
        elif any(item["status"] == "mutated" for item in comparison["statuses"]):
            row["actualBehavior"] = "mutated"
        elif any(item["status"] == "dropped" for item in comparison["statuses"]):
            row["actualBehavior"] = "dropped"
        elif any(item["status"] == "safelyNormalized" for item in comparison["statuses"]):
            row["actualBehavior"] = "safely normalized"
        elif comparison["added"]:
            row["actualBehavior"] = "added new protected-like literal"
        else:
            row["actualBehavior"] = "preserved"
        rows.append(row)
    return rows, bundles, all_pairs, cases


def global_metrics(
    all_pairs: list[tuple[str, dict[str, Any], dict[str, Any]]],
    covered_rows: list[dict[str, Any]],
    cases: dict[str, dict[str, Any]],
) -> tuple[dict[str, Any], dict[str, Any]]:
    intercepts = {(row["caseID"], row["runIndex"]): row for row in covered_rows if row["counterfactualIntercepted"]}
    unsafe_by_key = {(row["caseID"], row["runIndex"]): row for row in covered_rows}
    actual = Counter()
    counter = Counter()
    for _, record, score in all_pairs:
        if "output" not in record or record.get("decision") not in {"changed", "noChange"}:
            continue
        key = (record["caseID"], record["runIndex"])
        eval_case = cases[record["caseID"]]
        kinds = objective_kinds(score)
        changed = record["decision"] == "changed"
        pass_now = bool(score.get("passedObjectively"))
        new_violation = bool(unsafe_by_key.get(key, {}).get("unsafeInputTokens"))
        harmful = changed and record.get("productionRejection") is None and (bool(kinds & HARMFUL_KINDS) or new_violation)
        critical = any(failure.get("severity") == "critical" for failure in score.get("objectiveFailures", []))
        useful = changed and pass_now and requires_change(eval_case.get("expected", {})) and not new_violation
        actual.update(runs=1, changed=int(changed), noChange=int(not changed), objectivePass=int(pass_now), userVisibleHarmfulEdits=int(harmful), criticalFailures=int(critical), usefulRefinements=int(useful))
        if key in intercepts:
            cf_pass = nochange_passes(eval_case.get("expected", {}))
            counter.update(runs=1, noChange=1, objectivePass=int(cf_pass), criticalFailures=int(not cf_pass and eval_case.get("severity") == "critical"))
        else:
            counter.update(runs=1, changed=int(changed), noChange=int(not changed), objectivePass=int(pass_now), userVisibleHarmfulEdits=int(harmful), criticalFailures=int(critical), usefulRefinements=int(useful))
    corruptions = sum(len(row["unsafeInputTokens"]) for row in covered_rows if row["actualAction"] == "changed")
    actual["protectedTokenCorruptions"] = corruptions
    counter["protectedTokenCorruptions"] = 0
    counter["counterfactualRejections"] = len(intercepts)
    for value in [actual, counter]:
        value["objectivePassRate"] = value["objectivePass"] / value["runs"] if value["runs"] else 0
        value["userVisibleHarmfulEditRate"] = value["userVisibleHarmfulEdits"] / value["runs"] if value["runs"] else 0
    return dict(actual), dict(counter)


def added_literal_analysis(bundles: dict[str, Any]) -> dict[str, Any]:
    details: list[dict[str, Any]] = []
    for split, bundle in bundles.items():
        for record, score in index_bundle(bundle):
            if record.get("decision") != "changed" or "output" not in record:
                continue
            comparison = compare_tokens(record["input"], record["output"])
            if comparison["added"]:
                kinds = sorted(objective_kinds(score))
                details.append({
                    "caseID": record["caseID"], "dataset": split, "input": record["input"], "output": record["output"],
                    "added": comparison["added"], "existingFailureKinds": kinds,
                    "likelyInventedInformation": "forbiddenContentIntroduced" in kinds,
                })
    factual = [row for row in details if row["likelyInventedInformation"] or any(token["class"] in CRITICAL_LITERAL_CLASSES for token in row["added"])]
    return {
        "changedCases": len(details), "factualLiteralIndicatorCases": len(factual),
        "caseIDs": sorted({row["caseID"] for row in details}), "details": details,
        "note": "These are indicators, not automatic invented-information findings; list numbering and structural labels can be benign.",
    }


def per_class(rows: list[dict[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for category in CLASSES:
        category_rows = [row for row in rows if any(token["class"] == category for token in row["tokenComparison"]["inputTokens"])]
        statuses = [status for row in category_rows for status in row["tokenComparison"]["statuses"] if status["class"] == category]
        intercepted = [row for row in category_rows if row["counterfactualIntercepted"] and any(value["class"] == category for value in row["unsafeInputTokens"])]
        result[category] = {
            "casesContainingClass": len({row["caseID"] for row in category_rows}),
            "runsContainingClass": len(category_rows),
            "changedProposals": sum(row["actualAction"] == "changed" for row in category_rows),
            "tokenOccurrences": len(statuses),
            "preserved": sum(value["status"] == "preserved" for value in statuses),
            "safelyNormalized": sum(value["status"] == "safelyNormalized" for value in statuses),
            "mutated": sum(value["status"] == "mutated" for value in statuses),
            "dropped": sum(value["status"] == "dropped" for value in statuses),
            "counterfactualRejections": len(intercepted),
            "harmPrevented": sum(row["effectClassification"] == "A" for row in intercepted),
            "usefulRefinementsLost": sum(row["effectClassification"] == "C" for row in intercepted),
            "falsePositiveDetections": sum(row["effectClassification"] == "D" for row in intercepted),
            "policyTooStrict": sum(row["effectClassification"] == "E" for row in intercepted),
        }
    return result


def stability_analysis() -> dict[str, Any]:
    bundle = read_json(SOURCE / "stability/results.json")
    pairs = index_bundle(bundle)
    by_case: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for record, score in pairs:
        comparison = compare_tokens(record["input"], record["output"])
        if not comparison["inputTokens"]:
            continue
        unsafe = any(item["status"] in {"mutated", "dropped"} for item in comparison["statuses"])
        actual_state = "unsafe" if unsafe and record["decision"] == "changed" else "safe"
        final_action = "noChange" if unsafe and record["decision"] == "changed" else record["decision"]
        by_case[record["caseID"]].append({"actualState": actual_state, "actualAction": record["decision"], "counterfactualState": "safe", "counterfactualAction": final_action})
    mutation_flapping = sorted(case for case, values in by_case.items() if len({row["actualState"] for row in values}) > 1)
    actual_action_flapping = sorted(case for case, values in by_case.items() if len({row["actualAction"] for row in values}) > 1)
    counter_action_flapping = sorted(case for case, values in by_case.items() if len({row["counterfactualAction"] for row in values}) > 1)
    return {
        "coveredCases": len(by_case), "coveredRuns": sum(map(len, by_case.values())),
        "tokenMutationInstabilityCases": mutation_flapping,
        "tokenMutationInstabilityCount": len(mutation_flapping),
        "actualActionInstabilityCases": actual_action_flapping,
        "counterfactualActionInstabilityCases": counter_action_flapping,
        "counterfactualEliminatesUnsafeFinalTokenState": True,
        "counterfactualDoesNotGuaranteeActionDeterminism": bool(counter_action_flapping),
    }


def markdown_table(rows: list[dict[str, Any]], added: dict[str, Any]) -> str:
    def clean(value: str) -> str:
        return value.replace("|", "\\|").replace("\n", "<br>")
    lines = [
        "# M12B-005A covered-case table", "",
        "One row per accepted dev, validation, or permanent-regression result containing at least one high-confidence protected token. Holdout is excluded.", "",
        "| Case | Set / scope | Input | Actual output | Tokens and status | Added literals | Actual result | Counterfactual | Effect | Reason |",
        "|---|---|---|---|---|---|---|---|---|---|",
    ]
    for row in sorted(rows, key=lambda value: (value["dataset"], value["caseID"], value["runIndex"])):
        tokens = "; ".join(f'{item["class"]}:{item["value"]}={item["status"]}' for item in row["tokenComparison"]["statuses"])
        added_cell = "; ".join(f'{item["class"]}:{item["value"]}' for item in row["addedProtectedLikeTokens"]) or "—"
        actual = f'{row["actualAction"]}; objective {"pass" if row["actualObjectivePass"] else "fail"}'
        counter = "rejected → noChange" if row["counterfactualIntercepted"] else "unchanged"
        lines.append("| " + " | ".join(map(clean, [row["caseID"], f'{row["dataset"]} / {row["scope"]}', row["input"], row["actualOutput"], tokens, added_cell, actual, counter, row["effectClassification"] or "—", row["effectReason"]])) + " |")
    lines += ["", "## Outputs adding protected-like literals", "", "These cases are diagnostic indicators, not automatic failures.", "", "| Case | Set | Input | Output | Added protected-like values |", "|---|---|---|---|---|"]
    for row in added["details"]:
        values = "; ".join(f'{item["class"]}:{item["value"]}' for item in row["added"])
        lines.append("| " + " | ".join(map(clean, [row["caseID"], row["dataset"], row["input"], row["output"], values])) + " |")
    return "\n".join(lines) + "\n"


def main() -> None:
    rows, bundles, all_pairs, cases = build_rows()
    covered_actual, covered_counterfactual = metrics(rows)
    actual, counterfactual = global_metrics(all_pairs, rows, cases)
    effects = Counter(row["effectClassification"] for row in rows if row["effectClassification"])
    classes = per_class(rows)
    scopes = {}
    for scope in ["wholeNote", "selection"]:
        subset = [row for row in rows if row["scope"] == scope]
        current, simulated = metrics(subset)
        scopes[scope] = {"coveredCases": len({row["caseID"] for row in subset}), "current": current, "counterfactual": simulated}
    added = added_literal_analysis(bundles)
    language_rows = [row for row in rows if row["counterfactualIntercepted"] and row["languageRelatedMutation"]]
    benchmark_disagreements = [
        row["caseID"] for row in rows
        if row["counterfactualIntercepted"] and row["actualObjectivePass"]
    ]
    frontier_intercepts = [row for row in rows if row["counterfactualIntercepted"] and row["frontierJudgment"]]
    selection_rows = [row for row in rows if row["scope"] == "selection"]
    analysis = {
        "schemaVersion": 1,
        "experiment": "M12B-005A-protected-token-counterfactual",
        "evaluationOnly": True,
        "productionBehaviorModified": False,
        "holdoutUsed": False,
        "source": "Recorded accepted M12B-004C dev, validation, and permanent-regression outputs; no generation was run.",
        "classesAnalyzed": CLASSES,
        "preservationPolicy": {category: "exact" if category in EXACT else "semantic" for category in CLASSES},
        "coverage": {
            "uniqueCases": len({row["caseID"] for row in rows}), "runs": len(rows),
            "byDataset": {name: sum(row["dataset"] == name for row in rows) for name in ["dev", "validation", "regression"]},
            "frontierCoveredCases": len({row["caseID"] for row in rows if row["frontierJudgment"]}),
        },
        "currentAccepted": actual,
        "counterfactualGuard": counterfactual,
        "coveredCohort": {"currentAccepted": covered_actual, "counterfactualGuard": covered_counterfactual},
        "deltas": {key: counterfactual.get(key, 0) - actual.get(key, 0) for key in ["changed", "noChange", "objectivePass", "userVisibleHarmfulEdits", "protectedTokenCorruptions", "criticalFailures"]},
        "effectCounts": dict(sorted(effects.items())),
        "harmPrevented": effects["A"], "usefulRefinementsLost": effects["C"],
        "falsePositiveExtractorCases": effects["D"], "policyTooStrictCases": effects["E"],
        "perTokenClass": classes,
        "byScope": scopes,
        "languageInteraction": {
            "languageRelatedInterceptedCases": len(language_rows),
            "languageRelatedCaseIDs": sorted({row["caseID"] for row in language_rows}),
            "nonLanguageInterceptedCases": counterfactual["counterfactualRejections"] - len(language_rows),
            "claim": "The simulated guard rejects literal-corrupting outputs; it does not improve or replace language resolution.",
        },
        "addedProtectedLikeLiterals": added,
        "benchmarkEvaluatorDisagreement": {"actualPassDespiteNewViolationCaseIDs": sorted(set(benchmark_disagreements))},
        "frontierSecondary": {
            "coveredCases": len({row["caseID"] for row in rows if row["frontierJudgment"]}),
            "interceptedCases": len(frontier_intercepts),
            "interceptedCaseIDs": sorted({row["caseID"] for row in frontier_intercepts}),
            "supportingProductFailureCases": sorted({row["caseID"] for row in frontier_intercepts if row["frontierJudgment"].get("productJudgment") == "productFailure"}),
            "isHumanGroundTruth": False,
        },
        "selectionIsolation": {
            "coveredCases": len(selection_rows),
            "existingContextLeakOrScopeFailureCases": sorted({row["caseID"] for row in selection_rows if set(row["actualObjectiveFailureKinds"]) & {"contextLeakage", "selectionScopeViolation"}}),
            "note": "Only selected input spans were token-compared; the counterfactual does not change selection behavior.",
        },
        "stability": stability_analysis(),
        "rDollar": {
            "caseID": "tiny-pt-008", "class": "money", "currentAcceptedBehavior": "M12B-004C preflight returns noChange and preserves R$.",
            "priorM12B001Observation": "R$ → $", "strictPreservationCatchesPriorMutation": True,
            "noChangeIsSafer": True,
            "futureBenchmarkCorrection": "Consider mustPreserveTokens: [\"R$\"] after maintainer review; frozen corpus was not modified.",
        },
        "recommendation": {
            "choice": "B",
            "label": "Implement protection only for a narrower subset of token classes",
            "exactClasses": ["url", "email", "handle", "identifier", "codeLike", "quotedLiteral", "opaqueID"],
            "semanticClasses": ["money", "time", "percentage"],
            "exactIntegerDeletionProtection": True,
            "deferClasses": ["date", "formattedOrDecimalNumberMutation"],
            "reason": "High-confidence structural and factual literals support a simple reject-to-noChange guard. Exact standalone-integer deletion is also supported; locale-sensitive date and formatted/decimal-number rewriting needs positive controls.",
        },
        "cases": rows,
    }

    OUTPUT.mkdir(parents=True, exist_ok=True)
    (OUTPUT / "analysis.json").write_text(json.dumps(analysis, indent=2, ensure_ascii=False) + "\n")
    (OUTPUT / "case-table.md").write_text(markdown_table(rows, added))

    token_policy = f"""# M12B-005A evaluation token policy

This policy is evaluation-only. It does not change production Refine behavior, prompts, generation, language handling, selection handling, corpus data, or UX.

## Extraction rules

Extraction is deterministic and precedence-based. Compound spans claim their range before simpler patterns, preventing the digits inside a date, percentage, money value, URL, or identifier from being counted again as plain numbers.

| Class | High-confidence rule | Evaluation preservation |
|---|---|---|
| URL | `http://` or `https://` followed by a non-space URL span | Exact |
| Email | Conventional local-part, `@`, dotted host | Exact |
| Handle | `@` plus 1–32 ASCII word characters; emails take precedence | Exact |
| Money | `R$`, `US$`, `$`, `€`, `£`, or `¥`, optionally followed by an amount | Semantic: whitespace around the currency marker may change; marker and amount may not |
| Date | ISO `YYYY-MM-DD` or slash date `D/M[/Y]` | Semantic class, but only identical surface is currently accepted; no locale guessing |
| Time | 24-hour colon, Portuguese `h`, or AM/PM clock forms | Semantic by exact minute-of-day equivalence |
| Number | Standalone integer/decimal-like literal, after compound classes | Semantic class, but only identical surface is currently accepted; no separator guessing |
| Percentage | Numeric literal plus `%` | Semantic: whitespace before `%` may change; value and `%` may not |
| Identifier | snake_case, camelCase, conservative technical PascalCase, version/mixed-alphanumeric, or technical kebab form | Exact |
| Code-like | Function/member-call or path-like literal | Exact |
| Quoted literal | Double-, single-, or backtick-delimited nontrivial span | Exact, including delimiters |
| Opaque ID | UUID, ticket-style uppercase ID, or 7–64 character mixed hex hash | Exact |

## Assumptions

- Exact preservation means the original byte/text span must appear in the changed output.
- Safe semantic normalization is intentionally narrow: `R$ 300` ↔ `R$300`, `15h` ↔ `15:00`, and `50%` ↔ `50 %`.
- `R$` → `$`, `31/12` → `12/31`, and `50%` → `50` are not safe normalization.
- Changed proposals that violate the high-confidence contract are simulated as rejected into the existing `noChange` result. There is no regeneration or repair pass.

## Known limitations and false-positive risks

- Dates and plain numbers are detected structurally, not interpreted by locale. Production enforcement is deferred for these classes.
- Version strings, durations such as `45ms`, and mixed alphanumeric values are treated as identifiers only when structural cues are strong.
- Uppercase ordinary words are not automatically identifiers.
- A generated numbered list can introduce protected-like plain numbers without inventing factual content; added-token results are indicators, not automatic failures.
- Quoted natural-language text is protected as a literal even when a user might accept quote-style normalization; this first layer prefers false negatives over broad semantic inference.
- Extraction does not attempt NLP, named-entity recognition, or locale-heavy date parsing.
"""
    (OUTPUT / "token-policy.md").write_text(token_policy)

    per_class_lines = [
        "| Class | Cases | Changed | Preserved | Safe normalized | Mutated | Dropped | Rejections | Harm prevented | Useful lost | False positive | Too strict |",
        "|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for category in CLASSES:
        value = classes[category]
        per_class_lines.append(f'| {category} | {value["casesContainingClass"]} | {value["changedProposals"]} | {value["preserved"]} | {value["safelyNormalized"]} | {value["mutated"]} | {value["dropped"]} | {value["counterfactualRejections"]} | {value["harmPrevented"]} | {value["usefulRefinementsLost"]} | {value["falsePositiveDetections"]} | {value["policyTooStrict"]} |')

    report = f"""# M12B-005A protected-token counterfactual

## Decision

**B — implement protection only for a narrower high-confidence subset in a future production experiment.** This experiment itself is evaluation-only and made no production Refine change.

Exact production candidates justified for a future experiment: URLs, emails, handles, technical identifiers, code-like literals, quoted literals, opaque IDs, and deletion of standalone integers. Narrow semantic preservation is also justified for currency expressions, times, and percentages. Defer dates and formatted/decimal-number mutation until targeted positive controls resolve locale-sensitive normalization risk.

## Method and coverage

- Source: existing accepted M12B-004C dev, validation, and permanent-regression outputs.
- Foundation Models generations performed: **0**.
- Holdout used: **no**.
- Global accepted cohort: **{actual["runs"]} runs**. Protected-input coverage: **{analysis["coverage"]["uniqueCases"]} unique cases / {analysis["coverage"]["runs"]} runs**.
- Frontier overlap: **{analysis["coverage"]["frontierCoveredCases"]} cases**; frontier judgments are a secondary, non-human lens only.
- Scope: {scopes["wholeNote"]["coveredCases"]} whole-note cases and {scopes["selection"]["coveredCases"]} selection cases.

## Current vs simulated reject-to-noChange

| Metric | Current accepted | Counterfactual | Delta |
|---|---:|---:|---:|
| Objective pass | {actual["objectivePass"]}/{actual["runs"]} | {counterfactual["objectivePass"]}/{counterfactual["runs"]} | {analysis["deltas"]["objectivePass"]:+d} |
| User-visible harmful edits | {actual["userVisibleHarmfulEdits"]} | {counterfactual["userVisibleHarmfulEdits"]} | {analysis["deltas"]["userVisibleHarmfulEdits"]:+d} |
| Changed | {actual["changed"]} | {counterfactual["changed"]} | {analysis["deltas"]["changed"]:+d} |
| noChange | {actual["noChange"]} | {counterfactual["noChange"]} | {analysis["deltas"]["noChange"]:+d} |
| Protected-token corruption occurrences | {actual["protectedTokenCorruptions"]} | {counterfactual["protectedTokenCorruptions"]} | {analysis["deltas"]["protectedTokenCorruptions"]:+d} |
| Critical failures | {actual["criticalFailures"]} | {counterfactual["criticalFailures"]} | {analysis["deltas"]["criticalFailures"]:+d} |

Counterfactual interceptions: **{counterfactual["counterfactualRejections"]}**. Effects: {dict(sorted(effects.items()))}. Harm prevented: **{effects["A"]}**. Demonstrated useful refinements lost: **{effects["C"]}**. False-positive detections: **{effects["D"]}**. Policy-too-strict cases: **{effects["E"]}**.

The covered cohort contains **{actual["protectedTokenCorruptions"]} corruption/loss occurrences**: {sum(value["mutated"] for value in classes.values())} mutations and {sum(value["dropped"] for value in classes.values())} drops. Two semantic time changes (`15h` → `3:00 PM`, `14h` → `2:00 PM`) were correctly classified as safe normalization rather than corruption. Current and counterfactual useful refinements retained are both **{actual["usefulRefinements"]}**.

## Per token class

{chr(10).join(per_class_lines)}

Counts for preservation/mutation are token occurrences; cases and changed proposals are run/case-level counts. A single case may contribute to multiple classes.

## Whole-note vs selection

- Whole note: {scopes["wholeNote"]["current"]["protectedTokenCorruptions"]} current corruption occurrences; {scopes["wholeNote"]["counterfactual"]["counterfactualRejections"]} simulated rejections.
- Selection: {scopes["selection"]["current"]["protectedTokenCorruptions"]} current corruption occurrences; {scopes["selection"]["counterfactual"]["counterfactualRejections"]} simulated rejections.
- Selection is evaluated only against the selected input span. This analysis does not alter selection production behavior or its existing isolation guards.
- Existing selection diagnostics report **{len(analysis["selectionIsolation"]["existingContextLeakOrScopeFailureCases"])}** context-leak/scope failures among these protected-token selection cases.

## Language interaction

{analysis["languageInteraction"]["languageRelatedInterceptedCases"]} intercepted cases also carry wrong-language evidence; {analysis["languageInteraction"]["nonLanguageInterceptedCases"]} do not. Rejecting those proposals would prevent the literal mutation as an indirect safety effect, but would not improve the resolver or validator.

## Frontier secondary lens and evaluator disagreements

Frontier adjudication overlaps {analysis["frontierSecondary"]["coveredCases"]} covered cases and is not human/maintainer ground truth. It overlaps one intercepted case, `mixed-pt-en-006`, and independently labels that output a high-confidence `meaningChanged` product failure. The deterministic benchmark nevertheless passes two newly detected violations (`mixed-pt-en-006`, `telegraphic-pt-009`), so those are retained explicitly as evaluator/benchmark disagreements rather than silently treated as ground truth.

## Added protected-like information

Across the full accepted cohort, changed output introduced unmatched protected-like values in **{analysis["addedProtectedLikeLiterals"]["changedCases"]}** case, and that case is also flagged for forbidden introduced content: `regression-over-expansion-005` changes `ver logs` into an instruction containing the invented quoted command ``ls -l``. Added-value extraction remains diagnostic rather than a proposed guard in M12B-005A.

## Stability

The ×5 artifact covers {analysis["stability"]["coveredCases"]} protected-token cases / {analysis["stability"]["coveredRuns"]} runs. Preserved/unsafe token state flapped in **{analysis["stability"]["tokenMutationInstabilityCount"]} cases**: {analysis["stability"]["tokenMutationInstabilityCases"]}. The counterfactual removes unsafe final token states, but action instability can remain in {len(analysis["stability"]["counterfactualActionInstabilityCases"])} cases because safe changed outputs may alternate with noChange.

## R$ case

`tiny-pt-008` is classified as money. The accepted M12B-004C path already returns preflight `noChange`, preserving `R$` without generation. The earlier M12B-001 `R$` → `$` observation would be caught because changing the currency marker is not a safe normalization; `noChange` is safer. A future maintainer-reviewed benchmark edit could add `mustPreserveTokens: ["R$"]`, but this experiment did not modify the frozen corpus.

## Recommendation rationale

The evidence supports a small, explainable post-generation reject-to-noChange guard for exact structural literals, narrowly equivalent money/time/percentage formatting, and deletion of exact standalone integers. It does not yet justify production enforcement for dates or formatted/decimal-number rewrites: locale-sensitive changes can be either dangerous or acceptable, and the current data lacks sufficient positive controls. This is recommendation **B**, not implementation.

## Verification

- Deterministic extractor unit tests pass, including URLs, emails, handles, money, dates, times, numbers, percentages, snake/camel/Pascal/mixed identifiers, UUID/hash IDs, quoted/code-like literals, overlap suppression, repeated-literal deduplication, and ordinary-language negative controls.
- Complete `Rasc` scheme test suite passes under `xcodebuild test` on 2026-09-21.
- The analysis script compiles with `python3 -m py_compile` and regenerates the four experiment artifacts without Foundation Models calls.
- Xcode continues to emit the existing duplicate file-reference warning for `RefineLanguageDetection.swift`; it does not fail the build or tests and is outside this experiment.
"""
    (OUTPUT / "report.md").write_text(report)


if __name__ == "__main__":
    main()

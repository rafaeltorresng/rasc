#!/usr/bin/env python3
"""Prepare and analyze the evaluation-only M12B-004B challenge."""

from __future__ import annotations

import argparse
import html
import json
import re
import shutil
import unicodedata
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
CHALLENGE = ROOT / "Evals/Refine/challenges/one-token-positive-controls.v1.jsonl"
REVIEW = ROOT / "Evals/Refine/challenges/one-token-positive-controls-review.md"
OUTPUT = ROOT / "Evals/Refine/experiments/M12B-004B-one-token-positive-controls"
PROMPT_VERSION = "refine-v2-language"
DISPOSITIONS = {"shouldChange", "shouldNotChange", "ambiguous"}
LANGUAGES = {"pt", "en", "es"}
LEXICAL_RE = re.compile(r"^[^\W\d_]+(?:['’\-][^\W\d_]+)*$", re.UNICODE)


def load_json(path: Path) -> Any:
    return json.loads(path.read_text())


def load_challenge() -> list[dict[str, Any]]:
    return [json.loads(line) for line in CHALLENGE.read_text().splitlines() if line.strip()]


def exact_equal(left: str, right: str) -> bool:
    return unicodedata.normalize("NFC", left.strip()) == unicodedata.normalize("NFC", right.strip())


def strip_diacritics(text: str) -> str:
    return "".join(
        char for char in unicodedata.normalize("NFD", text)
        if unicodedata.category(char) != "Mn"
    )


def levenshtein(left: str, right: str) -> int:
    if len(left) < len(right):
        left, right = right, left
    previous = list(range(len(right) + 1))
    for left_index, left_char in enumerate(left, start=1):
        current = [left_index]
        for right_index, right_char in enumerate(right, start=1):
            current.append(min(
                current[-1] + 1,
                previous[right_index] + 1,
                previous[right_index - 1] + (left_char != right_char),
            ))
        previous = current
    return previous[-1]


def lexical_units(text: str) -> list[str]:
    return re.findall(r"[^\W\d_]+(?:['’\-][^\W\d_]+)*", text, re.UNICODE)


def case_pattern(text: str) -> str:
    letters = "".join(char for char in text if char.isalpha())
    if not letters:
        return "none"
    if letters.islower():
        return "lower"
    if letters.isupper():
        return "upper"
    if letters.istitle():
        return "title"
    return "mixed"


def surface_features(input_text: str, output_text: str) -> dict[str, Any]:
    normalized_input = unicodedata.normalize("NFC", input_text)
    normalized_output = unicodedata.normalize("NFC", output_text)
    identical = normalized_input == normalized_output
    capitalization_only = not identical and normalized_input.casefold() == normalized_output.casefold()
    diacritic_only = (
        not identical
        and strip_diacritics(normalized_input).casefold() == strip_diacritics(normalized_output).casefold()
    )
    compact_input = re.sub(r"\s+", "", normalized_input).casefold()
    compact_output = re.sub(r"\s+", "", normalized_output).casefold()
    whitespace_split = (
        not identical
        and compact_input == compact_output
        and len(normalized_output.split()) > len(normalized_input.split())
    )
    alnum_input = "".join(char.casefold() for char in normalized_input if char.isalnum())
    alnum_output = "".join(char.casefold() for char in normalized_output if char.isalnum())
    punctuation_only = (
        not identical
        and not capitalization_only
        and not diacritic_only
        and not whitespace_split
        and alnum_input == alnum_output
        and bool(alnum_input)
    )
    input_units = lexical_units(normalized_input)
    output_units = lexical_units(normalized_output)
    edit_distance = levenshtein(normalized_input.casefold(), normalized_output.casefold())
    length_ratio = len(normalized_output) / max(1, len(normalized_input))
    lexical_typo = (
        len(input_units) == 1
        and len(output_units) == 1
        and LEXICAL_RE.fullmatch(input_units[0]) is not None
        and LEXICAL_RE.fullmatch(output_units[0]) is not None
        and edit_distance <= 2
        and 0.75 <= length_ratio <= 1.34
        and case_pattern(normalized_input) == case_pattern(normalized_output)
    )
    transform = "other"
    for name, active in [
        ("identical", identical),
        ("capitalizationOnly", capitalization_only),
        ("diacriticOnly", diacritic_only),
        ("whitespaceSplit", whitespace_split),
        ("punctuationOnly", punctuation_only),
        ("lowDistanceLexical", lexical_typo),
    ]:
        if active:
            transform = name
            break
    return {
        "transform": transform,
        "editDistance": edit_distance,
        "lengthRatio": length_ratio,
        "inputLexicalUnits": len(input_units),
        "outputLexicalUnits": len(output_units),
        "casePatternPreserved": case_pattern(normalized_input) == case_pattern(normalized_output),
        "capitalizationOnly": capitalization_only,
        "diacriticOnly": diacritic_only,
        "whitespaceSplit": whitespace_split,
        "punctuationOnly": punctuation_only,
        "lowDistanceLexical": lexical_typo,
    }


def validate_challenge(cases: list[dict[str, Any]]) -> None:
    assert 36 <= len(cases) <= 45, "Challenge must contain approximately 36–45 cases."
    ids = [case["id"] for case in cases]
    assert len(ids) == len(set(ids)), "Challenge IDs must be unique."
    for case in cases:
        assert case["source"] == "targetedChallenge"
        assert case["humanValidated"] is False
        assert case["maintainerApproved"] is False
        assert case["reviewStatus"] == "maintainer-unapproved"
        assert case["language"] in LANGUAGES
        assert case["expectedDisposition"] in DISPOSITIONS
        assert case["confidence"] in {"high", "medium"}
        assert case["scope"] == "wholeNote"
        assert len(case["input"].strip().split()) == 1, f"Not one input unit: {case['id']}"
        assert case.get("split") is None, "Challenge cases must not belong to frozen splits."
        assert case["allowedOutputs"]
        assert case["outputConstraint"]["type"] == "exactOneOf"
        assert case["allowedOutputs"] == case["outputConstraint"]["values"]
        assert case["expected"]["exactOutput"] in case["allowedOutputs"]
        if case["expectedDisposition"] == "shouldChange":
            assert case["allowedActions"] == ["cleanup"]
            assert case["expected"]["allowedActions"] == ["cleanup"]
            assert not exact_equal(case["input"], case["allowedOutputs"][0])
        else:
            assert case["allowedActions"] == ["noChange"]
            assert case["expected"]["allowedActions"] == ["noChange"]
            assert case["expected"].get("expectsNoChange") is True
            assert exact_equal(case["input"], case["allowedOutputs"][0])
    language_counts = Counter(case["language"] for case in cases)
    disposition_counts = Counter(case["expectedDisposition"] for case in cases)
    cross_counts = Counter((case["language"], case["expectedDisposition"]) for case in cases)
    assert language_counts == {"pt": 14, "en": 14, "es": 14}
    assert disposition_counts == {"shouldChange": 21, "shouldNotChange": 15, "ambiguous": 6}
    assert all(cross_counts[(language, "shouldChange")] == 7 for language in LANGUAGES)
    assert all(cross_counts[(language, "shouldNotChange")] == 5 for language in LANGUAGES)
    assert all(cross_counts[(language, "ambiguous")] == 2 for language in LANGUAGES)
    assert sum(case.get("inReviewQueue") is True for case in cases) == 15


def prepare_runner_root(destination: Path, cases: list[dict[str, Any]]) -> None:
    destination.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(CHALLENGE, destination / "corpus.v1.jsonl")
    (destination / "regression.jsonl").write_text("")
    manifest = {
        "version": 1,
        "seed": "m12b-004b-targeted-challenge-not-frozen-split",
        "ratios": {"dev": 1.0, "validation": 0.0, "holdout": 0.0},
        "assignments": {case["id"]: "dev" for case in cases},
        "notes": {
            "scope": "Temporary runner manifest for M12B-004B only.",
            "holdout": "No holdout cases are present or referenced.",
        },
    }
    (destination / "splits.v1.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")


def failure_kinds(score: dict[str, Any]) -> list[str]:
    return [failure["kind"] for failure in score.get("objectiveFailures", [])]


def record_indexes(bundle: dict[str, Any]) -> tuple[dict[tuple[str, int], dict[str, Any]], dict[tuple[str, int], dict[str, Any]]]:
    records = {(row["caseID"], row["runIndex"]): row for row in bundle["records"]}
    scores = {(row["caseID"], row["runIndex"]): row for row in bundle["scores"]}
    return records, scores


def effective_action(record: dict[str, Any]) -> str:
    decision = record.get("decision")
    if decision == "changed" and record.get("productionRejection"):
        return "rejected"
    return decision or "unavailable"


def wrong_language(record: dict[str, Any], score: dict[str, Any]) -> bool:
    if "languageDrift" in failure_kinds(score):
        return True
    diagnostics = record.get("languageDiagnostics") or {}
    if effective_action(record) != "changed":
        return False
    return diagnostics.get("generationLanguageCorrect") is False or diagnostics.get("userVisibleLanguageSafe") is False


def current_outcome(case: dict[str, Any], record: dict[str, Any], score: dict[str, Any]) -> dict[str, Any]:
    output = record.get("output") or ""
    action = effective_action(record)
    exact_allowed = action == "changed" and any(exact_equal(output, value) for value in case["allowedOutputs"])
    case_variant_allowed = action == "changed" and any(
        unicodedata.normalize("NFC", output.strip()).casefold()
        == unicodedata.normalize("NFC", value.strip()).casefold()
        for value in case["allowedOutputs"]
    )
    useful_repair = case["expectedDisposition"] == "shouldChange" and case_variant_allowed
    disposition = case["expectedDisposition"]
    harm = action == "changed" and not useful_repair
    unnecessary = disposition in {"shouldNotChange", "ambiguous"} and action == "changed"
    success = exact_allowed if disposition == "shouldChange" else action != "changed"
    failures = failure_kinds(score)
    return {
        "action": action,
        "recordedAction": record.get("decision"),
        "output": output,
        "productionRejection": record.get("productionRejection"),
        "expectedSuccess": success,
        "exactSurfaceRepairCorrect": exact_allowed,
        "usefulRepairCorrect": useful_repair,
        "caseVariantOfAllowedOutput": case_variant_allowed and not exact_allowed,
        "harmfulEdit": harm,
        "unnecessaryEdit": unnecessary,
        "wrongLanguageOutput": wrong_language(record, score),
        "inventedInformation": "forbiddenContentIntroduced" in failures,
        "excessiveExpansion": "expansionExceeded" in failures,
        "runnerObjectivePass": bool(score.get("passedObjectively")),
        "runnerObjectiveFailures": failures,
        "surface": surface_features(case["input"], output) if output else None,
        "latencyMs": record.get("latencyMs"),
        "languageDiagnostics": record.get("languageDiagnostics"),
        "providerError": record.get("providerError"),
    }


def policy_a_outcome(case: dict[str, Any]) -> dict[str, Any]:
    disposition = case["expectedDisposition"]
    return {
        "action": "noChange",
        "output": case["input"],
        "expectedSuccess": disposition != "shouldChange",
        "exactSurfaceRepairCorrect": False,
        "usefulRepairCorrect": False,
        "caseVariantOfAllowedOutput": False,
        "harmfulEdit": False,
        "unnecessaryEdit": False,
        "wrongLanguageOutput": False,
        "inventedInformation": False,
        "excessiveExpansion": False,
        "reason": "Unconditional one-content-unit abstention.",
    }


def envelope_decision(case: dict[str, Any], current: dict[str, Any]) -> tuple[bool, str]:
    if current["action"] != "changed":
        return False, "No accepted changed output is available."
    if current["wrongLanguageOutput"]:
        return False, "Existing language diagnostics do not consider the changed output safe."
    surface = current["surface"] or {}
    if surface.get("outputLexicalUnits", 99) > 2:
        return False, "Output exceeds two lexical units."
    if not 0.75 <= surface.get("lengthRatio", 99) <= 1.34:
        return False, "Output length ratio is outside 0.75–1.34."
    if surface.get("capitalizationOnly"):
        return False, "Capitalization-only changes are explicitly excluded."
    if surface.get("punctuationOnly"):
        return False, "Punctuation-only changes are explicitly excluded."
    if surface.get("diacriticOnly") and surface.get("casePatternPreserved"):
        return True, "Accepted diacritic-only repair with preserved case pattern."
    if surface.get("whitespaceSplit") and surface.get("casePatternPreserved"):
        return True, "Accepted exact whitespace split with preserved characters and case pattern."
    if surface.get("lowDistanceLexical") and surface.get("editDistance", 99) <= 2:
        return True, "Accepted one-word lexical edit within distance two and preserved case pattern."
    return False, "Changed output is outside the narrow surface envelope."


def policy_b_outcome(case: dict[str, Any], current: dict[str, Any]) -> dict[str, Any]:
    accepted, reason = envelope_decision(case, current)
    if not accepted:
        outcome = policy_a_outcome(case)
        outcome["reason"] = reason
        outcome["envelopeAccepted"] = False
        return outcome
    disposition = case["expectedDisposition"]
    exact_allowed = any(exact_equal(current["output"], value) for value in case["allowedOutputs"])
    useful_repair = case["expectedDisposition"] == "shouldChange" and current["usefulRepairCorrect"]
    return {
        "action": "changed",
        "output": current["output"],
        "expectedSuccess": exact_allowed if disposition == "shouldChange" else False,
        "exactSurfaceRepairCorrect": exact_allowed,
        "usefulRepairCorrect": useful_repair,
        "caseVariantOfAllowedOutput": current["caseVariantOfAllowedOutput"],
        "harmfulEdit": not useful_repair,
        "unnecessaryEdit": disposition in {"shouldNotChange", "ambiguous"},
        "wrongLanguageOutput": current["wrongLanguageOutput"],
        "inventedInformation": current["inventedInformation"],
        "excessiveExpansion": current["excessiveExpansion"],
        "reason": reason,
        "envelopeAccepted": True,
    }


def aggregate(rows: list[dict[str, Any]], outcome_key: str) -> dict[str, Any]:
    outcomes = [row[outcome_key] for row in rows]
    should_change = [row for row in rows if row["expectedDisposition"] == "shouldChange"]
    should_not_change = [row for row in rows if row["expectedDisposition"] == "shouldNotChange"]
    ambiguous = [row for row in rows if row["expectedDisposition"] == "ambiguous"]
    return {
        "cases": len(rows),
        "changed": sum(outcome["action"] == "changed" for outcome in outcomes),
        "noChange": sum(outcome["action"] == "noChange" for outcome in outcomes),
        "rejected": sum(outcome["action"] == "rejected" for outcome in outcomes),
        "expectedSuccess": sum(outcome["expectedSuccess"] for outcome in outcomes),
        "harmfulEdits": sum(outcome["harmfulEdit"] for outcome in outcomes),
        "exactCorrectionSuccess": sum(row[outcome_key]["exactSurfaceRepairCorrect"] for row in should_change),
        "caseVariantCorrectionSuccess": sum(row[outcome_key]["caseVariantOfAllowedOutput"] for row in should_change),
        "usefulRepairsRetained": sum(row[outcome_key]["usefulRepairCorrect"] for row in should_change),
        "usefulRepairsMissed": sum(not row[outcome_key]["usefulRepairCorrect"] for row in should_change),
        "shouldChangeCases": len(should_change),
        "shouldChangeSuccess": sum(row[outcome_key]["usefulRepairCorrect"] for row in should_change),
        "shouldNotChangeCases": len(should_not_change),
        "shouldNotChangeAccuracy": sum(row[outcome_key]["action"] != "changed" for row in should_not_change),
        "ambiguousCases": len(ambiguous),
        "ambiguousSafe": sum(row[outcome_key]["action"] != "changed" for row in ambiguous),
        "wrongLanguageOutputs": sum(outcome["wrongLanguageOutput"] for outcome in outcomes),
        "inventedInformation": sum(outcome["inventedInformation"] for outcome in outcomes),
        "excessiveExpansions": sum(outcome["excessiveExpansion"] for outcome in outcomes),
        "unnecessaryEdits": sum(outcome["unnecessaryEdit"] for outcome in outcomes),
        "providerErrors": sum(bool(outcome.get("providerError")) for outcome in outcomes),
    }


def breakdown(rows: list[dict[str, Any]], outcome_key: str, field: str) -> dict[str, dict[str, Any]]:
    values = sorted({row[field] for row in rows})
    return {value: aggregate([row for row in rows if row[field] == value], outcome_key) for value in values}


def stability_summary(
    cases_by_id: dict[str, dict[str, Any]],
    records: dict[tuple[str, int], dict[str, Any]],
    scores: dict[tuple[str, int], dict[str, Any]],
    policy: str,
) -> dict[str, Any]:
    by_case: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for (case_id, run_index), record in sorted(records.items()):
        case = cases_by_id[case_id]
        current = current_outcome(case, record, scores[(case_id, run_index)])
        if policy == "current":
            outcome = current
        elif policy == "A":
            outcome = policy_a_outcome(case)
        else:
            outcome = policy_b_outcome(case, current)
        by_case[case_id].append({"runIndex": run_index, **outcome})
    case_rows = []
    for case_id, runs in sorted(by_case.items()):
        actions = [run["action"] for run in runs]
        successes = [run["expectedSuccess"] for run in runs]
        case_rows.append({
            "caseID": case_id,
            "actions": actions,
            "expectedSuccesses": successes,
            "actionInstability": len(set(actions)) > 1,
            "successInstability": len(set(successes)) > 1,
            "providerErrorRuns": sum(bool(run.get("providerError")) for run in runs),
        })
    return {
        "cases": len(case_rows),
        "runsPerCase": 5,
        "actionInstabilityCases": sum(row["actionInstability"] for row in case_rows),
        "successInstabilityCases": sum(row["successInstability"] for row in case_rows),
        "providerErrorRuns": sum(row["providerErrorRuns"] for row in case_rows),
        "actionInstabilityCaseIDs": [row["caseID"] for row in case_rows if row["actionInstability"]],
        "successInstabilityCaseIDs": [row["caseID"] for row in case_rows if row["successInstability"]],
        "casesDetail": case_rows,
    }


def add_comparison_deltas(
    current: dict[str, Any],
    policy: dict[str, Any],
) -> dict[str, Any]:
    harm_prevented = current["harmfulEdits"] - policy["harmfulEdits"]
    utility_lost = max(0, current["usefulRepairsRetained"] - policy["usefulRepairsRetained"])
    result = dict(policy)
    result["harmPreventedVsCurrent"] = harm_prevented
    result["usefulRepairsLostVsCurrent"] = utility_lost
    result["harmPreventedPerUsefulRepairLost"] = None if utility_lost == 0 else harm_prevented / utility_lost
    result["tradeoffExplanation"] = (
        f"{harm_prevented} harms prevented with no currently demonstrated useful repair lost."
        if utility_lost == 0
        else f"{harm_prevented / utility_lost:.2f} harms prevented per currently demonstrated useful repair lost."
    )
    return result


def markdown_escape(value: Any) -> str:
    return str(value).replace("|", "\\|").replace("\n", "<br>")


def code_cell(value: Any) -> str:
    return f"<code>{html.escape(str(value))}</code>"


def build_review(cases: list[dict[str, Any]]) -> str:
    lines = [
        "# One-token positive controls v1 — maintainer review",
        "",
        "> Status: generated frontier challenge; **not human validated and not maintainer approved**. Review does not modify frozen corpus or establish ground truth.",
        "",
        "| ID | Lang | Input | Disposition | Allowed output | Category | Confidence | Semantic note |",
        "|---|---|---|---|---|---|---|---|",
    ]
    for case in cases:
        lines.append("| " + " | ".join(markdown_escape(value) for value in [
            case["id"], case["language"], f"`{case['input']}`", case["expectedDisposition"],
            " / ".join(f"`{value}`" for value in case["allowedOutputs"]),
            ", ".join(case["category"]), case["confidence"], case["semanticNotes"],
        ]) + " |")
    lines.extend([
        "",
        "## Separate future protected-token issue",
        "",
        "M12B-004A observed `R$` → `$`. Frontier review identified a likely missing protected-token constraint. This issue is recorded for future review only; M12B-004B does not modify the frozen corpus, benchmark constraint, validator, or production guard.",
        "",
    ])
    return "\n".join(lines)


def build_summary(cases: list[dict[str, Any]]) -> str:
    languages = Counter(case["language"] for case in cases)
    dispositions = Counter(case["expectedDisposition"] for case in cases)
    categories = Counter(category for case in cases for category in case["category"] if category != "one-token-positive-control")
    return "\n".join([
        "# M12B-004B challenge-set summary",
        "",
        "This is a separate targeted challenge, not dev, validation, regression, or holdout. It does not alter `corpus.v1.jsonl`, `splits.v1.json`, or baseline artifacts. Every case is frontier-generated, `humanValidated=false`, and maintainer-unapproved.",
        "",
        f"- Cases: {len(cases)}",
        f"- Languages: PT={languages['pt']}, EN={languages['en']}, ES={languages['es']}",
        f"- Dispositions: shouldChange={dispositions['shouldChange']}, shouldNotChange={dispositions['shouldNotChange']}, ambiguous={dispositions['ambiguous']}",
        f"- Critical stability subset: {sum(case.get('inReviewQueue') is True for case in cases)} cases ×5",
        "- Positive controls use exact canonical outputs only; no subjective ‘make nicer’ expectations are present.",
        "- The stock scorer normalizes case/diacritics, so this experiment independently scores exact NFC surface outputs to distinguish `nao` from `não`.",
        "",
        "## Category counts",
        "",
        *[f"- {key}: {value}" for key, value in sorted(categories.items())],
        "",
        "## Product asymmetry",
        "",
        "Missing a minor spelling repair has low cost for Rasc. Inventing, translating, formalizing, or substantially changing a one-word note has high trust cost. Policy B is preferable only if its simple envelope retains meaningful, highly reliable utility without reopening meaningful harm.",
        "",
        "## Separate R$ flag",
        "",
        "`R$` → `$` remains a future protected-token issue from M12B-004A. No corpus or production correction is applied here.",
        "",
    ])


def outcome_label(outcome: dict[str, Any], disposition: str) -> str:
    if outcome["harmfulEdit"]:
        return "harmful edit"
    if disposition == "shouldChange":
        if outcome["exactSurfaceRepairCorrect"]:
            return "exact useful repair"
        if outcome["usefulRepairCorrect"]:
            return "useful repair (case variant)"
        return "repair missed"
    return "safe abstention" if outcome["action"] != "changed" else "unnecessary edit"


def build_case_table(rows: list[dict[str, Any]]) -> str:
    lines = [
        "# M12B-004B case table",
        "",
        "| ID | Lang | Disposition | Input | Expected | Current output | Current | Current flags | Policy A | Policy B | B envelope reason |",
        "|---|---|---|---|---|---|---|---|---|---|---|",
    ]
    for row in rows:
        flags = [
            label for label, active in [
                ("wrongLanguage", row["current"]["wrongLanguageOutput"]),
                ("inventedInformation", row["current"]["inventedInformation"]),
                ("excessiveExpansion", row["current"]["excessiveExpansion"]),
                ("unnecessaryEdit", row["current"]["unnecessaryEdit"]),
                ("caseVariant", row["current"]["caseVariantOfAllowedOutput"]),
                ("productionRejected", bool(row["current"]["productionRejection"])),
            ] if active
        ]
        lines.append("| " + " | ".join(markdown_escape(value) for value in [
            row["caseID"], row["language"], row["expectedDisposition"], code_cell(row["input"]),
            " / ".join(code_cell(value) for value in row["allowedOutputs"]),
            code_cell(row["current"]["output"]), outcome_label(row["current"], row["expectedDisposition"]),
            ", ".join(flags) or "—",
            outcome_label(row["policyA"], row["expectedDisposition"]),
            outcome_label(row["policyB"], row["expectedDisposition"]), row["policyB"]["reason"],
        ]) + " |")
    return "\n".join(lines) + "\n"


def metric_table(policy_payloads: dict[str, dict[str, Any]]) -> list[str]:
    current = policy_payloads["current"]["metrics"]
    policy_a = policy_payloads["A"]["metrics"]
    policy_b = policy_payloads["B"]["metrics"]
    metrics = [
        ("Harmful edits", "harmfulEdits"),
        ("Useful repairs retained", "usefulRepairsRetained"),
        ("Exact canonical corrections", "exactCorrectionSuccess"),
        ("Useful case-variant corrections", "caseVariantCorrectionSuccess"),
        ("Useful repairs missed", "usefulRepairsMissed"),
        ("Wrong-language outputs", "wrongLanguageOutputs"),
        ("Invented information", "inventedInformation"),
        ("Excessive expansions", "excessiveExpansions"),
        ("Unnecessary edits", "unnecessaryEdits"),
        ("Should-not-change accuracy", "shouldNotChangeAccuracy"),
        ("Ambiguous safe", "ambiguousSafe"),
    ]
    lines = ["| Metric | Current | Policy A | Policy B |", "|---|---:|---:|---:|"]
    for label, key in metrics:
        lines.append(f"| {label} | {current[key]} | {policy_a[key]} | {policy_b[key]} |")
    return lines


def build_comparison(
    policy_payloads: dict[str, dict[str, Any]],
    rows: list[dict[str, Any]],
    recommendation: str,
) -> str:
    current = policy_payloads["current"]
    policy_a = policy_payloads["A"]
    policy_b = policy_payloads["B"]
    labels = {
        "A": "unconditional one-content-unit whole-note noChange gate",
        "B": "narrow one-content-unit surface-repair envelope",
        "C": "insufficient evidence / no policy yet",
    }
    lost_a = [row for row in rows if row["current"]["usefulRepairCorrect"] and not row["policyA"]["usefulRepairCorrect"]]
    lost_b = [row for row in rows if row["current"]["usefulRepairCorrect"] and not row["policyB"]["usefulRepairCorrect"]]
    decision_evidence = {
        "A": (
            f"Policy A prevents {policy_a['metrics']['harmPreventedVsCurrent']} challenge harms at the cost of "
            f"{policy_a['metrics']['usefulRepairsLostVsCurrent']} demonstrated repairs "
            f"({policy_a['metrics']['harmPreventedPerUsefulRepairLost']:.2f} harms prevented per repair lost). "
            f"Policy B retains {policy_b['metrics']['usefulRepairsRetained']} of {current['metrics']['usefulRepairsRetained']} demonstrated repairs but reopens {policy_b['metrics']['harmfulEdits']} unnecessary edit "
            f"and has {policy_b['stability']['actionInstabilityCases']} action-unstable stability cases. "
            f"Only {current['metrics']['usefulRepairsRetained']} of 21 positive controls produced useful canonical or case-variant repairs in the one-pass run, none in Spanish; this limited utility does not justify the semantic risk and extra envelope complexity under Rasc's asymmetric trust cost."
        ),
        "B": (
            f"Policy B retains {policy_b['metrics']['usefulRepairsRetained']} exact repairs while preventing "
            f"{policy_b['metrics']['harmPreventedVsCurrent']} harms. Its remaining harm and instability must be weighed against Policy A's utility loss."
        ),
        "C": (
            "The challenge evidence does not separate a safe, stable surface envelope from unconditional abstention strongly enough to authorize either production policy."
        ),
    }
    lines = [
        "# M12B-004B — One-token positive-control comparison",
        "",
        "| Field | Value |",
        "|---|---|",
        "| Production change | None |",
        "| Prompt | Accepted M12B-001 (`refine-v2-language`) |",
        "| Challenge | 42 separate maintainer-unapproved targeted cases |",
        "| Holdout | Not loaded or run |",
        f"| Recommendation | **{recommendation} — {labels[recommendation]}** |",
        "",
        "## Primary metrics",
        "",
        *metric_table(policy_payloads),
        "",
        f"Policy A: {policy_a['metrics']['tradeoffExplanation']}",
        "",
        f"Policy B: {policy_b['metrics']['tradeoffExplanation']}",
        "",
        "## Stability (15 cases ×5)",
        "",
        "| Policy | Action-instability cases | Success-instability cases | Provider-error runs |",
        "|---|---:|---:|---:|",
        f"| Current | {current['stability']['actionInstabilityCases']} | {current['stability']['successInstabilityCases']} | {current['stability']['providerErrorRuns']} |",
        f"| Policy A | {policy_a['stability']['actionInstabilityCases']} | {policy_a['stability']['successInstabilityCases']} | {policy_a['stability']['providerErrorRuns']} |",
        f"| Policy B | {policy_b['stability']['actionInstabilityCases']} | {policy_b['stability']['successInstabilityCases']} | {policy_b['stability']['providerErrorRuns']} |",
        "",
        "## Breakdowns",
        "",
    ]
    for dimension in ["byDisposition", "byLanguage"]:
        lines.extend([f"### {dimension}", ""])
        keys = sorted(current[dimension])
        lines.extend([
            "| Group | Current exact-expectation success | Current harm | A exact-expectation success | A harm | B exact-expectation success | B harm |",
            "|---|---:|---:|---:|---:|---:|---:|",
        ])
        for key in keys:
            lines.append(
                f"| {key} | {current[dimension][key]['expectedSuccess']}/{current[dimension][key]['cases']} | "
                f"{current[dimension][key]['harmfulEdits']} | {policy_a[dimension][key]['expectedSuccess']}/{policy_a[dimension][key]['cases']} | "
                f"{policy_a[dimension][key]['harmfulEdits']} | {policy_b[dimension][key]['expectedSuccess']}/{policy_b[dimension][key]['cases']} | "
                f"{policy_b[dimension][key]['harmfulEdits']} |"
            )
        lines.append("")
    lines.extend([
        "## Useful refinements Policy A would lose",
        "",
    ])
    if lost_a:
        lines.extend(f"- `{row['input']}` → `{row['current']['output']}` ({row['caseID']})" for row in lost_a)
    else:
        lines.append("- None demonstrated by current M12B-001 in the one-pass run.")
    lines.extend(["", "## Useful refinements Policy B would lose", ""])
    if lost_b:
        lines.extend(f"- `{row['input']}` → `{row['current']['output']}` ({row['caseID']})" for row in lost_b)
    else:
        lines.append("- None of the current run's demonstrated exact repairs.")
    lines.extend([
        "",
        "## Policy B envelope",
        "",
        "Policy B uses only output-surface and existing language-safety evidence: an accepted changed output, at most two lexical units, length ratio 0.75–1.34, preserved case pattern, and either diacritic-only, exact whitespace split, or one-word edit distance ≤2. Capitalization-only and punctuation-only changes are rejected. It has no word list and does not inspect challenge expectations when deciding acceptance.",
        "",
        "## Product asymmetry",
        "",
        "A missed minor spelling repair is low cost. An invented, translated, formalized, or substantially changed one-word note is a high trust cost. A narrow envelope is warranted only if the observed retained corrections are meaningful, reliable across PT/EN/ES, stable, and do not reopen material harm.",
        "",
        "## Combined decision context",
        "",
        "M12B-004A found 13 harmful edits prevented, zero demonstrated utility loss in its original cohort, four wrong-language outputs eliminated, and 15/18 stability-covered cases flapping. M12B-004B supplies the missing positive controls but remains frontier-generated and maintainer-unapproved.",
        "",
        "## R$ future issue",
        "",
        "`R$` → `$` remains separately flagged as a likely missing protected-token constraint. This experiment does not alter or solve protected-token production behavior.",
        "",
        f"## Recommendation — {recommendation}",
        "",
        f"Recommend **{recommendation}: {labels[recommendation]}**. This report is evaluation evidence only; the recommendation is not implemented.",
        "",
        decision_evidence[recommendation],
        "",
    ])
    return "\n".join(lines)


def analyze(current_path: Path, stability_path: Path, recommendation: str) -> None:
    cases = load_challenge()
    validate_challenge(cases)
    cases_by_id = {case["id"]: case for case in cases}
    current_bundle = load_json(current_path)
    stability_bundle = load_json(stability_path)
    for bundle, expected_repetitions, expected_cases in [
        (current_bundle, 1, 42),
        (stability_bundle, 5, 15),
    ]:
        assert bundle["environment"]["promptVersion"] == PROMPT_VERSION
        assert "production FoundationModelsRefinementProvider" in bundle["environment"]["samplingConfiguration"]
        assert bundle["configuration"]["split"] == "dev"
        assert bundle["configuration"]["repetitions"] == expected_repetitions
        assert bundle["configuration"]["caseCount"] == expected_cases
        assert set(row["caseID"] for row in bundle["records"]).issubset(cases_by_id)
    current_records, current_scores = record_indexes(current_bundle)
    stability_records, stability_scores = record_indexes(stability_bundle)
    assert len(current_records) == 42
    assert len(stability_records) == 75

    rows = []
    for case in cases:
        record = current_records[(case["id"], 0)]
        score = current_scores[(case["id"], 0)]
        current = current_outcome(case, record, score)
        row = {
            "caseID": case["id"],
            "input": case["input"],
            "language": case["language"],
            "category": case["category"],
            "expectedDisposition": case["expectedDisposition"],
            "allowedActions": case["allowedActions"],
            "allowedOutputs": case["allowedOutputs"],
            "confidence": case["confidence"],
            "humanValidated": False,
            "current": current,
            "policyA": policy_a_outcome(case),
        }
        row["policyB"] = policy_b_outcome(case, current)
        rows.append(row)

    current_metrics = aggregate(rows, "current")
    a_metrics = add_comparison_deltas(current_metrics, aggregate(rows, "policyA"))
    b_metrics = add_comparison_deltas(current_metrics, aggregate(rows, "policyB"))
    current_stability = stability_summary(cases_by_id, stability_records, stability_scores, "current")
    a_stability = stability_summary(cases_by_id, stability_records, stability_scores, "A")
    b_stability = stability_summary(cases_by_id, stability_records, stability_scores, "B")

    shared = {
        "schemaVersion": 1,
        "experiment": "M12B-004B-one-token-positive-controls",
        "productionModified": False,
        "holdoutUsed": False,
        "challengeHumanValidated": False,
        "challengePath": str(CHALLENGE.relative_to(ROOT)),
        "sourcePromptVersion": PROMPT_VERSION,
    }
    current_payload = {
        **shared,
        "policy": "CURRENT M12B-001",
        "environment": current_bundle["environment"],
        "stabilityEnvironment": stability_bundle["environment"],
        "metrics": current_metrics,
        "byDisposition": breakdown(rows, "current", "expectedDisposition"),
        "byLanguage": breakdown(rows, "current", "language"),
        "stability": current_stability,
        "cases": [{key: value for key, value in row.items() if key != "policyA" and key != "policyB"} for row in rows],
    }
    a_payload = {
        **shared,
        "policy": "A — unconditional one-content-unit whole-note noChange",
        "metrics": a_metrics,
        "byDisposition": breakdown(rows, "policyA", "expectedDisposition"),
        "byLanguage": breakdown(rows, "policyA", "language"),
        "stability": a_stability,
        "usefulRepairsLostCaseIDs": [
            row["caseID"] for row in rows
            if row["current"]["usefulRepairCorrect"] and not row["policyA"]["usefulRepairCorrect"]
        ],
        "cases": [{"caseID": row["caseID"], "input": row["input"], "outcome": row["policyA"]} for row in rows],
    }
    b_payload = {
        **shared,
        "policy": "B — narrow one-content-unit surface-repair envelope",
        "envelope": {
            "usesChallengeExpectationToDecide": False,
            "requiresAcceptedCurrentChange": True,
            "requiresExistingLanguageSafety": True,
            "maximumOutputLexicalUnits": 2,
            "lengthRatio": [0.75, 1.34],
            "maximumLexicalEditDistance": 2,
            "requiresCasePatternPreservation": True,
            "allowedTransformFamilies": ["diacriticOnly", "exactWhitespaceSplit", "lowDistanceSingleLexicalWord"],
            "excluded": ["capitalizationOnly", "punctuationOnly", "sentenceExpansion"],
        },
        "metrics": b_metrics,
        "byDisposition": breakdown(rows, "policyB", "expectedDisposition"),
        "byLanguage": breakdown(rows, "policyB", "language"),
        "stability": b_stability,
        "usefulRepairsLostCaseIDs": [
            row["caseID"] for row in rows
            if row["current"]["usefulRepairCorrect"] and not row["policyB"]["usefulRepairCorrect"]
        ],
        "cases": [{"caseID": row["caseID"], "input": row["input"], "outcome": row["policyB"]} for row in rows],
    }
    policy_payloads = {"current": current_payload, "A": a_payload, "B": b_payload}

    OUTPUT.mkdir(parents=True, exist_ok=True)
    REVIEW.write_text(build_review(cases))
    (OUTPUT / "challenge-set-summary.md").write_text(build_summary(cases))
    (OUTPUT / "current-results.json").write_text(json.dumps(current_payload, indent=2, sort_keys=True, ensure_ascii=False) + "\n")
    (OUTPUT / "policy-a-counterfactual.json").write_text(json.dumps(a_payload, indent=2, sort_keys=True, ensure_ascii=False) + "\n")
    (OUTPUT / "policy-b-counterfactual.json").write_text(json.dumps(b_payload, indent=2, sort_keys=True, ensure_ascii=False) + "\n")
    (OUTPUT / "case-table.md").write_text(build_case_table(rows))
    (OUTPUT / "comparison.md").write_text(build_comparison(policy_payloads, rows, recommendation))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--validate", action="store_true")
    parser.add_argument("--prepare-runner-root", type=Path)
    parser.add_argument("--current-results", type=Path)
    parser.add_argument("--stability-results", type=Path)
    parser.add_argument("--recommendation", choices=["A", "B", "C"])
    args = parser.parse_args()
    cases = load_challenge()
    validate_challenge(cases)
    if args.prepare_runner_root:
        prepare_runner_root(args.prepare_runner_root, cases)
        print(f"Prepared isolated M12B-004B runner root: {args.prepare_runner_root}")
        return
    if args.current_results or args.stability_results or args.recommendation:
        if not (args.current_results and args.stability_results and args.recommendation):
            parser.error("--current-results, --stability-results, and --recommendation are required together")
        analyze(args.current_results, args.stability_results, args.recommendation)
        print(f"M12B-004B artifacts written to {OUTPUT}")
        return
    print(f"Validated {len(cases)} M12B-004B cases; no model run.")


if __name__ == "__main__":
    main()

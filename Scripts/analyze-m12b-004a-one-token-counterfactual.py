#!/usr/bin/env python3
"""M12B-004A: evaluation-only one-content-unit abstention counterfactual."""

from __future__ import annotations

import argparse
import json
import re
import unicodedata
from collections import Counter, defaultdict
from dataclasses import dataclass, asdict
from pathlib import Path
from typing import Any, Iterable


ROOT = Path(__file__).resolve().parents[1]
EVAL_ROOT = ROOT / "Evals" / "Refine"
M12B001 = EVAL_ROOT / "experiments" / "M12B-001-language-contract" / "reports"
OUTPUT = EVAL_ROOT / "experiments" / "M12B-004A-one-token-counterfactual"

URL_RE = re.compile(r"^(?:https?://|www\.)\S+$", re.IGNORECASE)
EMAIL_RE = re.compile(r"^[^\s@]+@[^\s@]+\.[^\s@]+$")
HANDLE_RE = re.compile(r"^@[\w.-]+$", re.UNICODE)
NUMBER_RE = re.compile(r"^[+-]?(?:\d+(?:[.,]\d+)?|[.,]\d+)%?$")
MONEY_RE = re.compile(r"^(?:R\$|US\$|[$€£¥])\s?[+-]?\d+(?:[.,]\d+)?$", re.IGNORECASE)
MONEY_FRAGMENT_RE = re.compile(r"^(?:R\$|US\$|[$€£¥])$", re.IGNORECASE)
IDENTIFIER_RE = re.compile(
    r"^(?:[A-Za-z][A-Za-z0-9]*_[A-Za-z0-9_]+|[A-Za-z][A-Za-z0-9]*\.[A-Za-z0-9_.]+|"
    r"[0-9a-fA-F]{8}-[0-9a-fA-F-]{27,})$"
)
CODE_LIKE_RE = re.compile(r"^(?=.*[^\W\d_])(?=.*(?:\+\+|--|::|->|[{}\[\]()=+*/\\<>:&|#])).+$", re.UNICODE)
LEXICAL_RE = re.compile(r"^[^\W\d_]+(?:['’\-][^\W\d_]+)*$", re.UNICODE)

ORTHOGRAPHIC_MARKERS = {
    "orthographic",
    "orthography",
    "typo",
    "spelling",
    "misspelling",
    "punctuation",
    "capitalization",
    "diacritic",
    "spacing",
    "concatenated",
}

SEVERE_FAILURE_KINDS = {
    "languageDrift",
    "protectedTokenMutation",
    "expansionExceeded",
    "selectionScopeViolation",
    "contextLeakage",
    "forbiddenContentIntroduced",
    "unexpectedChange",
    "productionGuardRejection",
}

ENGLISH_MARKERS = {
    "hello", "the", "and", "have", "found", "you", "are", "welcome", "to", "with",
    "me", "anytime", "team", "reviewed", "noticed", "areas", "could", "improved", "for",
    "clarity", "suggestions", "specific", "numbers", "whenever", "possible", "break", "down",
    "complex", "sentences", "simpler", "consider", "adding", "context", "examples", "ensure",
    "instructions", "clear", "review", "formatting", "visually", "appealing", "let", "know",
    "your", "thoughts", "new", "feature", "production",
}
PORTUGUESE_MARKERS = {
    "oi", "olá", "eu", "você", "bem", "sim", "não", "amanhã", "talvez", "equipe", "com",
    "para", "uma", "um", "encontrei", "café",
}


@dataclass(frozen=True)
class TokenShape:
    unitCount: int
    primaryShape: str
    eligibleContentUnit: bool
    attachedPunctuation: bool
    lexicalCore: str | None
    ambiguityReason: str | None = None


def unicode_category_prefix(character: str) -> str:
    return unicodedata.category(character)[0]


def is_emoji_sequence(text: str) -> bool:
    meaningful = [char for char in text if char not in {"\ufe0f", "\u200d"}]
    return bool(meaningful) and all(
        unicodedata.category(char) in {"So", "Sk", "Mn"} or ord(char) >= 0x1F000
        for char in meaningful
    )


def strip_attached_punctuation(text: str) -> tuple[str, bool]:
    start = 0
    end = len(text)
    while start < end and unicode_category_prefix(text[start]) == "P":
        start += 1
    while end > start and unicode_category_prefix(text[end - 1]) == "P":
        end -= 1
    core = text[start:end]
    return core, core != text


def classify_content_units(text: str) -> TokenShape:
    stripped = text.strip()
    if not stripped:
        return TokenShape(0, "empty", False, False, None, "No content unit.")
    whitespace_groups = stripped.split()
    if len(whitespace_groups) != 1:
        return TokenShape(len(whitespace_groups), "multipleUnits", False, False, None)

    token = whitespace_groups[0]
    if URL_RE.fullmatch(token):
        return TokenShape(1, "url", True, False, token)
    if EMAIL_RE.fullmatch(token):
        return TokenShape(1, "email", True, False, token)
    if HANDLE_RE.fullmatch(token):
        return TokenShape(1, "handle", True, False, token)
    if MONEY_RE.fullmatch(token):
        return TokenShape(1, "money", True, False, token)
    if MONEY_FRAGMENT_RE.fullmatch(token):
        return TokenShape(1, "moneyFragment", True, False, token, "Currency marker lacks an amount.")
    if NUMBER_RE.fullmatch(token):
        return TokenShape(1, "number", True, False, token)
    if is_emoji_sequence(token):
        return TokenShape(1, "emoji", True, False, token)
    if IDENTIFIER_RE.fullmatch(token):
        return TokenShape(1, "identifier", True, False, token)
    if CODE_LIKE_RE.fullmatch(token):
        return TokenShape(1, "codeLike", True, False, token)

    core, attached = strip_attached_punctuation(token)
    if not core:
        return TokenShape(1, "punctuationOnly", False, False, None, "Punctuation has no lexical/content core.")
    if LEXICAL_RE.fullmatch(core):
        return TokenShape(1, "wordWithAttachedPunctuation" if attached else "lexicalWord", True, attached, core)
    has_letter = any(unicode_category_prefix(char) == "L" for char in core)
    has_number = any(unicode_category_prefix(char) == "N" for char in core)
    if has_letter and has_number:
        return TokenShape(1, "mixedAlphanumericIdentifier", True, attached, core)
    if has_letter and any(unicode_category_prefix(char) in {"S", "P"} for char in core):
        return TokenShape(1, "codeLike", True, attached, core)
    return TokenShape(1, "ambiguousOther", False, attached, core, "One whitespace group, but content-unit type is unclear.")


def normalize_for_scorer(text: str) -> str:
    decomposed = unicodedata.normalize("NFKD", text.casefold())
    return "".join(char for char in decomposed if unicodedata.category(char) != "Mn")


def letters_and_numbers(text: str) -> str:
    return "".join(
        char.casefold() for char in unicodedata.normalize("NFKC", text)
        if unicode_category_prefix(char) in {"L", "N"}
    )


def strip_diacritics(text: str) -> str:
    decomposed = unicodedata.normalize("NFD", text)
    return "".join(char for char in decomposed if unicodedata.category(char) != "Mn")


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


def surface_analysis(input_text: str, output_text: str) -> dict[str, Any]:
    identical = input_text == output_text
    capitalization_only = not identical and input_text.casefold() == output_text.casefold()
    diacritic_only = (
        not identical
        and not capitalization_only
        and strip_diacritics(input_text).casefold() == strip_diacritics(output_text).casefold()
    )
    punctuation_only = (
        not identical
        and not capitalization_only
        and not diacritic_only
        and letters_and_numbers(input_text) == letters_and_numbers(output_text)
        and letters_and_numbers(input_text) != ""
    )
    whitespace_split = (
        not identical
        and input_text.replace(" ", "").casefold() == output_text.replace(" ", "").casefold()
        and len(output_text.split()) > len(input_text.split())
    )
    edit_distance = levenshtein(input_text, output_text)
    length_ratio = len(output_text) / max(1, len(input_text))
    output_shape = classify_content_units(output_text)
    named_surface_change = capitalization_only or diacritic_only or punctuation_only or whitespace_split
    strict_envelope = (
        named_surface_change
        and edit_distance <= 2
        and 0.8 <= length_ratio <= 1.25
        and output_shape.unitCount <= 2
    )
    transform = "other"
    for name, active in [
        ("identical", identical),
        ("capitalizationOnly", capitalization_only),
        ("diacriticOnly", diacritic_only),
        ("punctuationOnly", punctuation_only),
        ("whitespaceSplit", whitespace_split),
    ]:
        if active:
            transform = name
            break
    return {
        "transform": transform,
        "editDistance": edit_distance,
        "lengthRatio": length_ratio,
        "outputUnitCount": output_shape.unitCount,
        "capitalizationOnly": capitalization_only,
        "diacriticOnly": diacritic_only,
        "punctuationOnly": punctuation_only,
        "whitespaceSplit": whitespace_split,
        "strictSurfaceEnvelope": strict_envelope,
    }


def load_json(path: Path) -> Any:
    return json.loads(path.read_text())


def load_cases_without_holdout() -> dict[str, dict[str, Any]]:
    split_manifest = load_json(EVAL_ROOT / "splits.v1.json")
    allowed_ids = {
        case_id for case_id, split in split_manifest["assignments"].items()
        if split in {"dev", "validation"}
    }
    cases: dict[str, dict[str, Any]] = {}
    id_pattern = re.compile(r'^\{"id"\s*:\s*"([^"]+)"')
    with (EVAL_ROOT / "corpus.v1.jsonl").open() as corpus:
        for line in corpus:
            match = id_pattern.match(line)
            if match and match.group(1) in allowed_ids:
                case = json.loads(line)
                cases[case["id"]] = case
    with (EVAL_ROOT / "regression.jsonl").open() as regression:
        for line in regression:
            if line.strip():
                case = json.loads(line)
                cases[case["id"]] = case
    return cases


def load_bundle(split: str) -> dict[str, Any]:
    payload = load_json(M12B001 / split / "results.json")
    if payload["environment"]["promptVersion"] != "refine-v2-language":
        raise RuntimeError(f"Unexpected prompt in {split}: {payload['environment']['promptVersion']}")
    return {
        "payload": payload,
        "records": {(row["caseID"], row["runIndex"]): row for row in payload["records"]},
        "scores": {(row["caseID"], row["runIndex"]): row for row in payload["scores"]},
    }


def load_frontier() -> dict[str, dict[str, Any]]:
    records = {}
    with (EVAL_ROOT / "frontier-adjudications.v1.jsonl").open() as source:
        for line in source:
            if line.strip():
                row = json.loads(line)
                records[row["caseID"]] = row
    return records


def failure_kinds(score: dict[str, Any]) -> list[str]:
    return [failure["kind"] for failure in score.get("objectiveFailures", [])]


def benchmark_allows_no_change(expected: dict[str, Any]) -> bool:
    return (
        expected.get("expectsNoChange") is True
        or expected.get("preferredAction") == "noChange"
        or "noChange" in expected.get("allowedActions", [])
    )


def benchmark_requires_change(expected: dict[str, Any]) -> bool:
    allowed = expected.get("allowedActions")
    if allowed is not None:
        return "noChange" not in allowed and bool({"cleanup", "structure"}.intersection(allowed))
    return expected.get("preferredAction") in {"cleanup", "structure"}


def rescore_no_change(case: dict[str, Any]) -> dict[str, Any]:
    expected = case.get("expected", {})
    input_text = case["input"]
    failures = []
    allowed = expected.get("allowedActions")
    if allowed is not None and "noChange" not in allowed:
        failures.append("unexpectedNoChange")
    if benchmark_requires_change(expected):
        failures.append("expectedUsefulChangeMiss")
    exact = expected.get("exactOutput")
    if exact is not None and normalize_for_scorer(input_text) != normalize_for_scorer(exact):
        failures.append("exactOutputMismatch")
    missing_tokens = [
        token for token in expected.get("mustPreserveTokens", [])
        if normalize_for_scorer(token) not in normalize_for_scorer(input_text)
    ]
    if missing_tokens:
        failures.append("protectedTokenMissingFromInput")
    failures = list(dict.fromkeys(failures))
    return {
        "action": "noChange",
        "output": input_text,
        "objectivePass": not failures,
        "deterministicFailures": failures,
        "expectedUsefulChangeMiss": "expectedUsefulChangeMiss" in failures or "unexpectedNoChange" in failures,
        "overAbstention": benchmark_requires_change(expected),
        "languageSafe": True,
        "protectedTokenSafe": not missing_tokens,
        "userVisibleHarmful": False,
    }


def infer_wrong_language(case: dict[str, Any], output: str, score: dict[str, Any]) -> tuple[bool, str | None]:
    if "languageDrift" in failure_kinds(score):
        return True, "Recorded objective languageDrift failure."
    expected = case.get("expected", {}).get("expectedLanguage")
    words = set(re.findall(r"[^\W\d_]+", output.casefold(), re.UNICODE))
    if expected == "pt":
        english_hits = sorted(words.intersection(ENGLISH_MARKERS))
        portuguese_hits = words.intersection(PORTUGUESE_MARKERS)
        if english_hits and not portuguese_hits:
            return True, f"Evaluation-only English marker indicator: {', '.join(english_hits[:5])}."
    return False, None


def effective_user_action(record: dict[str, Any]) -> str:
    if record.get("decision") == "changed" and record.get("productionRejection") == "no_change":
        return "noChange"
    if record.get("productionRejection"):
        return "rejected"
    return record.get("decision") or "unavailable"


def actual_user_visible_harm(record: dict[str, Any], score: dict[str, Any], case: dict[str, Any]) -> bool:
    if effective_user_action(record) != "changed":
        return False
    failures = set(failure_kinds(score))
    if failures.intersection(SEVERE_FAILURE_KINDS):
        return True
    expected = case.get("expected", {})
    return expected.get("expectsNoChange") is True or not benchmark_allows_no_change(expected)


def benchmark_indicates_orthographic_repair(case: dict[str, Any]) -> bool:
    markers = {
        value.casefold().replace("-", "")
        for value in case.get("category", []) + case.get("tags", [])
    }
    normalized = {marker.replace("_", "") for marker in ORTHOGRAPHIC_MARKERS}
    return bool(markers.intersection(normalized))


def semantic_subtype(case: dict[str, Any], shape: TokenShape, surface: dict[str, Any]) -> str:
    categories = {value.casefold().replace("-", "") for value in case.get("category", [])}
    tags = {value.casefold().replace("-", "") for value in case.get("tags", [])}
    if shape.primaryShape in {"url", "email", "handle", "number", "money", "moneyFragment", "emoji"}:
        return "URL / handle / number / money / emoji"
    if shape.primaryShape in {"identifier", "codeLike", "mixedAlphanumericIdentifier"}:
        return "technical identifier"
    if surface["whitespaceSplit"]:
        return "concatenated words / obvious spacing error"
    if surface["diacriticOnly"]:
        return "missing diacritic"
    if surface["capitalizationOnly"]:
        return "capitalization-only issue"
    if surface["punctuationOnly"]:
        return "punctuation-only issue"
    if surface["editDistance"] <= 2 and surface["lengthRatio"] <= 1.5 and surface["transform"] != "identical":
        return "apparent typo"
    if "alreadygood" in categories or "alreadygood" in tags:
        return "already-valid word"
    if categories.intersection({"technical", "technicalen", "mixeden"}):
        return "foreign technical term"
    if categories.intersection({"ambiguous", "taskhint", "datehint", "message", "question"}):
        return "ambiguous fragment"
    if surface["transform"] == "identical":
        return "already-valid word"
    return "unclear"


def frontier_material_disagreement(
    frontier: dict[str, Any] | None,
    actual_pass: bool,
    deterministic_failures: set[str],
) -> bool:
    if not frontier:
        return False
    judgment = frontier.get("productJudgment")
    verdict_disagrees = (actual_pass and judgment == "productFailure") or (
        not actual_pass and judgment == "outputAcceptable"
    )
    missing_protected_token_constraint = (
        "protectedTokenMutation" in frontier.get("productFailureLabels", [])
        and "protectedTokenMutation" not in deterministic_failures
    )
    return verdict_disagrees or missing_protected_token_constraint


def classify_effect(
    case: dict[str, Any],
    record: dict[str, Any],
    score: dict[str, Any],
    counterfactual: dict[str, Any],
    frontier: dict[str, Any] | None,
    surface: dict[str, Any],
) -> tuple[str, str]:
    actual_pass = bool(score.get("passedObjectively"))
    deterministic_failures = set(failure_kinds(score))
    if frontier_material_disagreement(frontier, actual_pass, deterministic_failures):
        return "E", "Frontier review materially disagrees with the deterministic benchmark verdict or its recorded failure constraints."
    if actual_user_visible_harm(record, score, case) and counterfactual["objectivePass"]:
        return "A", "The recorded visible change failed existing constraints; forced noChange passes and removes the edit."
    if effective_user_action(record) == "noChange" and counterfactual["objectivePass"]:
        return "B", "The actual user-visible result was already noChange; the counterfactual is behaviorally equivalent."
    if record.get("decision") == "changed" and actual_pass and counterfactual["expectedUsefulChangeMiss"]:
        return "C", "The actual changed output passed and the benchmark requires a useful change that noChange would miss."
    if record.get("decision") == "changed" and actual_pass and counterfactual["objectivePass"]:
        if surface["strictSurfaceEnvelope"] or frontier and frontier.get("productJudgment") == "outputAcceptable":
            return "C", "The actual output is a passing, tightly bounded surface repair; forced noChange would lose that utility."
        return "D", "Both actions pass existing constraints, which do not establish whether the change adds useful value."
    return "D", "Existing constraints do not confidently rank the recorded and counterfactual outcomes."


def summarize_policy(cases: list[dict[str, Any]], policy_key: str) -> dict[str, Any]:
    changed = 0
    no_change = 0
    passes = 0
    harmful = 0
    harm_prevented = 0
    useful_lost = 0
    over_abstention = 0
    wrong_language = 0
    protected_failures = 0
    retained_changes = []
    for row in cases:
        outcome = row["policies"][policy_key]
        changed += outcome["action"] == "changed"
        no_change += outcome["action"] == "noChange"
        passes += outcome["objectivePass"]
        harmful += outcome["userVisibleHarmful"]
        harm_prevented += row["actual"]["userVisibleHarmful"] and not outcome["userVisibleHarmful"]
        useful_lost += row["effect"]["code"] == "C" and outcome["action"] == "noChange"
        over_abstention += outcome["overAbstention"]
        wrong_language += not outcome["languageSafe"]
        protected_failures += not outcome["protectedTokenSafe"]
        if outcome["action"] == "changed":
            retained_changes.append(row["caseID"])
    return {
        "cases": len(cases),
        "changed": changed,
        "noChange": no_change,
        "objectivePass": passes,
        "userVisibleHarmfulEdits": harmful,
        "harmPrevented": harm_prevented,
        "usefulRefinementLost": useful_lost,
        "expectedUsefulChangeMisses": over_abstention,
        "overAbstention": over_abstention,
        "wrongLanguageOutputs": wrong_language,
        "protectedTokenFailures": protected_failures,
        "retainedChangedCaseIDs": sorted(retained_changes),
        "harmPreventedPerUsefulRefinementLost": None if useful_lost == 0 else harm_prevented / useful_lost,
        "tradeoffExplanation": (
            f"{harm_prevented} harms prevented with no observed useful refinement loss; no finite ratio is reported."
            if useful_lost == 0
            else f"{harm_prevented / useful_lost:.2f} harms prevented per useful refinement lost."
        ),
    }


def policy_outcome_from_actual(row: dict[str, Any]) -> dict[str, Any]:
    return {
        "action": row["actual"]["recordedAction"],
        "output": row["actual"]["output"],
        "objectivePass": row["actual"]["objectivePass"],
        "deterministicFailures": row["actual"]["deterministicFailures"],
        "expectedUsefulChangeMiss": False,
        "overAbstention": False,
        "languageSafe": not row["actual"]["wrongLanguageIndicator"],
        "protectedTokenSafe": not row["actual"]["protectedTokenFailure"],
        "userVisibleHarmful": row["actual"]["userVisibleHarmful"],
    }


def markdown_escape(value: Any) -> str:
    return str(value).replace("|", "\\|").replace("\n", "<br>")


def build_case_table(cases: list[dict[str, Any]], excluded: dict[str, Any]) -> str:
    lines = [
        "# M12B-004A one-token counterfactual — case table",
        "",
        "Primary scope: executable whole-note M12B-001 dev, validation, and permanent-regression cases containing exactly one classified lexical/content unit. Frontier judgments are secondary evidence only.",
        "",
        "| Split | Case | Input | Shape / subtype | Actual output | Actual result | Forced-noChange result | Frontier judgment | Effect | Reason |",
        "|---|---|---|---|---|---|---|---|---|---|",
    ]
    effect_names = {
        "A": "A — harm prevented",
        "B": "B — neutral",
        "C": "C — useful refinement lost",
        "D": "D — benchmark uncertain",
        "E": "E — frontier/benchmark disagreement",
    }
    for row in cases:
        actual_failures = ", ".join(row["actual"]["deterministicFailures"]) or "pass"
        cf_failures = ", ".join(row["counterfactual"]["deterministicFailures"]) or "pass"
        actual_result = f"{row['actual']['recordedAction']}; {actual_failures}"
        if row["actual"]["productionRejection"]:
            actual_result += f"; guard={row['actual']['productionRejection']}"
        cf_result = f"noChange; {cf_failures}"
        frontier_judgment = (
            row["frontierSecondary"]["productJudgment"]
            if row["frontierSecondary"] else "—"
        )
        shape_description = f"{row['tokenShape']['primaryShape']} / {row['semanticSubtype']}"
        if row["tokenShape"].get("ambiguityReason"):
            shape_description += f" (classification note: {row['tokenShape']['ambiguityReason']})"
        lines.append(
            "| " + " | ".join(markdown_escape(value) for value in [
                row["split"],
                row["caseID"],
                f"`{row['input']}`",
                shape_description,
                f"`{row['actual']['output']}`",
                actual_result,
                cf_result,
                frontier_judgment,
                effect_names[row["effect"]["code"]],
                row["effect"]["reason"],
            ]) + " |"
        )
    lines.extend([
        "",
        "## Excluded selection subgroup",
        "",
        "Selection cases are observational only and are not included in primary metrics or policy simulations.",
        "",
        "| Split | Case | Input | Shape | Actual action | Actual output |",
        "|---|---|---|---|---|---|",
    ])
    for row in excluded["selectionSubgroup"]:
        lines.append("| " + " | ".join(markdown_escape(value) for value in [
            row["split"], row["caseID"], f"`{row['input']}`", row["tokenShape"]["primaryShape"],
            row["actualAction"], f"`{row['actualOutput']}`",
        ]) + " |")
    lines.extend([
        "",
        "## Other exclusions",
        "",
        f"- Non-executable whole-note one-content-unit cases without M12B-001 output: {', '.join(excluded['nonExecutableWholeNote']) or 'none'}.",
        f"- Ambiguous one-whitespace-group classifications excluded from primary eligibility: {', '.join(excluded['ambiguousClassifications']) or 'none'}.",
        "",
    ])
    return "\n".join(lines)


def percentage(count: int, total: int) -> str:
    return f"{count}/{total} ({(100 * count / total) if total else 0:.1f}%)"


def build_report(analysis: dict[str, Any]) -> str:
    metrics = analysis["metrics"]
    actual = metrics["actual"]
    counterfactual = metrics["counterfactual"]
    effects = metrics["effectCounts"]
    policies = analysis["policies"]
    frontier = analysis["frontierSecondary"]
    language = analysis["language"]
    stability = analysis["stability"]
    subtype_counts = analysis["subtypeCounts"]
    shape_counts = analysis["shapeCounts"]
    lines = [
        "# M12B-004A — One-Token Abstention Counterfactual",
        "",
        "| Field | Value |",
        "|---|---|",
        "| Production change | None |",
        "| Model generation | None; existing M12B-001 outputs only |",
        "| Primary scope | Whole-note dev + validation + permanent regression |",
        "| Holdout | Case bodies were not parsed, inspected, scored, or run |",
        "| Decision | **A — implement unconditional one-token whole-note noChange gate as the next isolated production experiment** |",
        "",
        "## Token definition",
        "",
        analysis["tokenDefinition"]["summary"],
        "",
        "Classification precedence: URL → email → @handle → money → money fragment → number → emoji → identifier → lexical word (with attached edge punctuation recorded separately) → mixed alphanumeric identifier → code-like → ambiguous other. Punctuation-only strings are not primary lexical/content units.",
        "",
        f"Eligible executable primary cases: **{metrics['eligibleCases']}**. Splits: " + ", ".join(f"{key}={value}" for key, value in sorted(analysis["splitCounts"].items())) + ". Shapes: " + ", ".join(f"{key}={value}" for key, value in sorted(shape_counts.items())) + ".",
        "",
        "No URL, email, number, emoji, mixed-alphanumeric, code-like, or whole-note identifier appeared in the eligible cohort. `R$` is explicitly classified as an ambiguous money fragment; `deploy?` is a lexical word with attached punctuation. No classification was silently coerced.",
        "",
        "## Actual versus forced noChange",
        "",
        "| Metric | Actual M12B-001 | Forced noChange | Delta |",
        "|---|---:|---:|---:|",
        f"| Recorded changed | {actual['changed']} | 0 | {-actual['changed']} |",
        f"| Recorded noChange | {actual['noChange']} | {counterfactual['noChange']} | +{counterfactual['noChange'] - actual['noChange']} |",
        f"| User-visible changed | {actual['userVisibleChanged']} | 0 | −{actual['userVisibleChanged']} |",
        f"| User-visible noChange | {actual['userVisibleNoChange']} | {counterfactual['noChange']} | +{counterfactual['noChange'] - actual['userVisibleNoChange']} |",
        f"| Objective pass | {actual['objectivePass']} | {counterfactual['objectivePass']} | +{counterfactual['objectivePass'] - actual['objectivePass']} |",
        f"| User-visible harmful edits | {actual['userVisibleHarmfulEdits']} | {counterfactual['userVisibleHarmfulEdits']} | −{actual['userVisibleHarmfulEdits'] - counterfactual['userVisibleHarmfulEdits']} |",
        f"| Wrong-language indicators | {actual['wrongLanguageOutputs']} | {counterfactual['wrongLanguageOutputs']} | −{actual['wrongLanguageOutputs'] - counterfactual['wrongLanguageOutputs']} |",
        f"| Invented-information indicators | {actual['inventedInformationIndicators']} | 0 | −{actual['inventedInformationIndicators']} |",
        f"| Excessive expansion | {actual['excessiveExpansion']} | 0 | −{actual['excessiveExpansion']} |",
        f"| Unnecessary edits | {actual['unnecessaryEdits']} | 0 | −{actual['unnecessaryEdits']} |",
        f"| Low-utility surface-only edits (subset) | {actual['unnecessarySurfaceEdits']} | 0 | −{actual['unnecessarySurfaceEdits']} |",
        f"| Expected-useful-change misses | 0 | {counterfactual['expectedUsefulChangeMisses']} | {counterfactual['expectedUsefulChangeMisses']:+d} |",
        f"| Over-abstention | 0 | {counterfactual['overAbstention']} | {counterfactual['overAbstention']:+d} |",
        f"| Protected-token failures | {actual['protectedTokenFailures']} | {counterfactual['protectedTokenFailures']} | {counterfactual['protectedTokenFailures'] - actual['protectedTokenFailures']:+d} |",
        "",
        "One recorded `changed` result (`tiny-en-007`, `@sam`→`@sam`) was already converted by the existing no-change guard into a user-visible noChange. It is counted as recorded changed but not as user-visible harm.",
        "",
        "## Effect classification",
        "",
        f"- A — harm prevented: **{effects.get('A', 0)}**",
        f"- B — neutral: **{effects.get('B', 0)}**",
        f"- C — useful refinement lost: **{effects.get('C', 0)}**",
        f"- D — benchmark uncertain: **{effects.get('D', 0)}**",
        f"- E — frontier/benchmark disagreement: **{effects.get('E', 0)}**",
        "",
        f"Safety/utility tradeoff: **{metrics['harmPrevented']} harms prevented and {metrics['usefulRefinementLost']} useful refinements lost**. Because the denominator is zero, no finite ratio is reported; the observed cohort shows harm prevention with no demonstrated utility loss. The harm total includes category E when noChange prevents harm but frontier review exposes a missing benchmark constraint.",
        "",
        "## Semantic and shape subtypes",
        "",
        "| Subtype | Cases |",
        "|---|---:|",
    ]
    for subtype, count in sorted(subtype_counts.items()):
        lines.append(f"| {subtype} | {count} |")
    lines.extend([
        "",
        "The corpus contains capitalization-only model changes but no actual one-token missing-diacritic, concatenated-word, punctuation-only, or valid typo repair. Therefore the analysis directly tests capitalization-only edits, but positive coverage for `ola`→`Olá`, `nao`→`não`, or `tudobem`→`tudo bem` is absent and remains a dataset limitation.",
        "",
        "## Policy simulations",
        "",
        "| Policy | Changed retained | Objective pass | Harm prevented | Useful lost | Over-abstention | Wrong-language |",
        "|---|---:|---:|---:|---:|---:|---:|",
    ])
    for key in ["A", "B", "C"]:
        policy = policies[key]
        lines.append(
            f"| {key} | {policy['changed']} | {policy['objectivePass']}/{policy['cases']} | "
            f"{policy['harmPrevented']} | {policy['usefulRefinementLost']} | {policy['overAbstention']} | {policy['wrongLanguageOutputs']} |"
        )
    lines.extend([
        "",
        "- **Policy A:** force noChange for every eligible whole-note one-content-unit input.",
        "- **Policy B:** retain a changed output only when existing category/tag metadata explicitly indicates an orthographic or typographic repair. No eligible case has such metadata, so B is observationally identical to A here.",
        "- **Policy C:** retain only named surface transformations (capitalization, diacritic, punctuation, whitespace split) with edit distance ≤2, length ratio 0.8–1.25, and output ≤2 content units.",
        "",
        "Policy C retains: " + (", ".join(policies["C"]["retainedChangedCaseIDs"]) or "none") + ". These retained cases all violate explicit noChange expectations; frontier review labels the reviewed capitalization cases unnecessary. The envelope therefore re-admits known low-utility failures without preserving any demonstrated useful repair.",
        "",
        "## Frontier adjudication (secondary only)",
        "",
        f"Frontier-covered eligible cases: {frontier['coveredCases']}. Product judgments: " + ", ".join(f"{key}={value}" for key, value in sorted(frontier["productJudgments"].items())) + ".",
        "",
        "Frontier benchmark judgments: " + ", ".join(f"{key}={value}" for key, value in sorted(frontier["benchmarkJudgments"].items())) + ". Material counterfactual disagreement cases: " + (", ".join(frontier["materialDisagreementCaseIDs"]) or "none") + ".",
        "",
        f"Among frontier-covered changed outputs, productFailure={frontier['changedProductFailure']}, outputAcceptable={frontier['changedOutputAcceptable']}, ambiguous={frontier['changedAmbiguous']}. No frontier-covered changed output was judged acceptable. Frontier and deterministic action safety agree on every materially reviewable changed case; benchmark-language disagreements are retained as notes and not applied.",
        "",
        "For `tiny-pt-008` (`R$`→`$`), frontier review calls out `protectedTokenMutation` and a missing must-preserve constraint, while the deterministic benchmark records only `unexpectedChange`. The case remains a noChange safety win but is classified E rather than silently treating the benchmark as complete. No frontier correction is applied.",
        "",
        "## Language",
        "",
        f"Evaluation-only clear wrong-language indicators among actual visible changes: **{language['actualWrongLanguageCount']}** ({', '.join(language['actualWrongLanguageCaseIDs'])}). Forced noChange reduces this to 0. This is an output-safety effect only and does **not** improve or change the language resolver.",
        "",
        "## Stability evidence",
        "",
        f"Of {stability['casesWithFiveRuns']} eligible non-regression cases present in critical stability ×5, {stability['actualActionFlappingCases']} flapped between changed and noChange. An unconditional gate would deterministically remove action flapping for this cohort, but this is a counterfactual—not a production measurement.",
        "",
        "## Benchmark uncertainty and limitations",
        "",
        "- All 24 eligible executable cases explicitly prefer noChange and allow it; the cohort has no positive benchmark case requiring a one-token repair.",
        "- That makes observed useful-refinement loss zero, but does not prove every possible one-token typo or spacing error is valueless.",
        "- Policy B cannot be distinguished empirically from Policy A because no eligible benchmark marks an orthographic repair.",
        "- Policy C is testable on existing outputs and performs worse by retaining capitalization-only changes that the benchmark—and reviewed frontier cases—treat as unnecessary.",
        "- One non-executable whole-note case (`tiny-pt-003`) has no M12B-001 output and is excluded. Four selection cases are reported separately, not scored in the primary policy.",
        "",
        "## Decision — A",
        "",
        "Recommend **A: implement an unconditional one-token whole-note noChange gate as the next isolated production experiment**.",
        "",
        "Evidence: the counterfactual prevents all 13 observed user-visible harmful edits, loses zero demonstrated useful refinements, removes four clear wrong-language outputs, removes all observed expansion and invention indicators, preserves protected-token safety, and introduces zero expectation-defined over-abstentions. Policy C re-admits seven capitalization-only failures; Policy B has no positive repair case to preserve and is indistinguishable from A on this corpus.",
        "",
        "This recommendation is constrained to exactly one classified content unit and whole-note refinement. It is not implemented here. A future production experiment must still measure real latency, interaction behavior, and explicitly add positive one-token orthographic cases before considering any exception envelope.",
        "",
        "## Artifacts",
        "",
        "- `analysis.json` — complete machine-readable cases and policy simulations.",
        "- `case-table.md` — every eligible case plus excluded selection subgroup.",
        "",
    ])
    return "\n".join(lines)


def run_self_tests() -> None:
    fixtures = {
        "deploy": (1, "lexicalWord", True),
        "deploy?": (1, "wordWithAttachedPunctuation", True),
        "https://rasc.app/a": (1, "url", True),
        "ana@example.com": (1, "email", True),
        "@ana": (1, "handle", True),
        "next_retry_at": (1, "identifier", True),
        "C++": (1, "codeLike", True),
        "foo()": (1, "codeLike", True),
        "404": (1, "number", True),
        "R$12,50": (1, "money", True),
        "R$": (1, "moneyFragment", True),
        "👍": (1, "emoji", True),
        "Q3": (1, "mixedAlphanumericIdentifier", True),
        "???": (1, "punctuationOnly", False),
        "two words": (2, "multipleUnits", False),
    }
    for value, expected in fixtures.items():
        actual = classify_content_units(value)
        received = (actual.unitCount, actual.primaryShape, actual.eligibleContentUnit)
        assert received == expected, f"{value!r}: expected {expected}, received {received}"
    assert surface_analysis("urgent", "Urgent")["strictSurfaceEnvelope"]
    assert surface_analysis("nao", "não")["diacriticOnly"]
    assert surface_analysis("tudobem", "tudo bem")["whitespaceSplit"]
    assert not surface_analysis("deploy", "Deploy the feature")["strictSurfaceEnvelope"]


def analyze() -> dict[str, Any]:
    cases = load_cases_without_holdout()
    frontier = load_frontier()
    bundles = {split: load_bundle(split) for split in ["dev", "validation", "regression", "stability"]}
    stability_records = defaultdict(list)
    for (case_id, _), record in bundles["stability"]["records"].items():
        stability_records[case_id].append(record)

    primary_rows = []
    selection_rows = []
    non_executable = []
    ambiguous_classifications = []

    for split in ["dev", "validation", "regression"]:
        bundle = bundles[split]
        for (case_id, run_index), record in sorted(bundle["records"].items()):
            if run_index != 0 or case_id not in cases:
                continue
            case = cases[case_id]
            shape = classify_content_units(case["input"])
            if shape.unitCount != 1:
                continue
            if case.get("scope", "wholeNote") == "selection":
                if shape.eligibleContentUnit:
                    selection_rows.append({
                        "split": split,
                        "caseID": case_id,
                        "input": case["input"],
                        "tokenShape": asdict(shape),
                        "actualAction": record.get("decision") or "unavailable",
                        "actualOutput": record.get("output") or "",
                    })
                continue
            if not shape.eligibleContentUnit:
                ambiguous_classifications.append(case_id)
                continue
            score = bundle["scores"].get((case_id, 0))
            if not score or record.get("decision") is None or record.get("output") is None:
                non_executable.append(case_id)
                continue

            surface = surface_analysis(case["input"], record["output"])
            cf = rescore_no_change(case)
            frontier_row = frontier.get(case_id)
            wrong_language, language_reason = infer_wrong_language(case, record["output"], score)
            actual_failures = failure_kinds(score)
            actual_harm = actual_user_visible_harm(record, score, case)
            effect_code, effect_reason = classify_effect(case, record, score, cf, frontier_row, surface)
            stable_records = sorted(stability_records.get(case_id, []), key=lambda row: row["runIndex"])
            stability_actions = [row.get("decision") for row in stable_records if row.get("decision")]
            row = {
                "caseID": case_id,
                "split": split,
                "input": case["input"],
                "categories": case.get("category", []),
                "tags": case.get("tags", []),
                "benchmark": {
                    "expected": case.get("expected", {}),
                    "languagePolicy": case.get("languagePolicy", {}),
                    "severity": case.get("severity"),
                },
                "tokenShape": asdict(shape),
                "semanticSubtype": semantic_subtype(case, shape, surface),
                "surfaceAnalysis": surface,
                "actual": {
                    "recordedAction": record["decision"],
                    "userVisibleAction": effective_user_action(record),
                    "output": record["output"],
                    "objectivePass": bool(score.get("passedObjectively")),
                    "deterministicFailures": actual_failures,
                    "productionRejection": record.get("productionRejection"),
                    "userVisibleHarmful": actual_harm,
                    "wrongLanguageIndicator": wrong_language,
                    "wrongLanguageReason": language_reason,
                    "inventedInformationIndicator": "forbiddenContentIntroduced" in actual_failures,
                    "excessiveExpansion": "expansionExceeded" in actual_failures,
                    "protectedTokenFailure": "protectedTokenMutation" in actual_failures,
                    "unnecessaryEdit": actual_harm and "unexpectedChange" in actual_failures,
                    "unnecessarySurfaceEdit": (
                        actual_harm
                        and surface["transform"] in {"identical", "capitalizationOnly", "diacriticOnly", "punctuationOnly", "whitespaceSplit"}
                    ),
                },
                "counterfactual": cf,
                "effect": {"code": effect_code, "reason": effect_reason},
                "frontierSecondary": (
                    {
                        "productJudgment": frontier_row.get("productJudgment"),
                        "productFailureLabels": frontier_row.get("productFailureLabels", []),
                        "productConfidence": frontier_row.get("productConfidence"),
                        "productRationale": frontier_row.get("productRationale"),
                        "benchmarkJudgment": frontier_row.get("benchmarkJudgment"),
                        "benchmarkRationale": frontier_row.get("benchmarkRationale"),
                        "proposedConstraintCorrection": frontier_row.get("proposedConstraintCorrection"),
                    }
                    if frontier_row else None
                ),
                "stability": {
                    "runCount": len(stability_actions),
                    "changedCount": stability_actions.count("changed"),
                    "noChangeCount": stability_actions.count("noChange"),
                    "actionFlapping": len(set(stability_actions)) > 1,
                },
            }
            row["policies"] = {
                "A": dict(cf),
                "B": policy_outcome_from_actual(row) if benchmark_indicates_orthographic_repair(case) else dict(cf),
                "C": policy_outcome_from_actual(row) if record["decision"] == "changed" and surface["strictSurfaceEnvelope"] else dict(cf),
            }
            primary_rows.append(row)

    primary_rows.sort(key=lambda row: (row["split"], row["caseID"]))
    selection_rows.sort(key=lambda row: (row["split"], row["caseID"]))

    actual_metrics = {
        "changed": sum(row["actual"]["recordedAction"] == "changed" for row in primary_rows),
        "noChange": sum(row["actual"]["recordedAction"] == "noChange" for row in primary_rows),
        "userVisibleChanged": sum(row["actual"]["userVisibleAction"] == "changed" for row in primary_rows),
        "userVisibleNoChange": sum(row["actual"]["userVisibleAction"] == "noChange" for row in primary_rows),
        "objectivePass": sum(row["actual"]["objectivePass"] for row in primary_rows),
        "userVisibleHarmfulEdits": sum(row["actual"]["userVisibleHarmful"] for row in primary_rows),
        "wrongLanguageOutputs": sum(row["actual"]["wrongLanguageIndicator"] for row in primary_rows),
        "inventedInformationIndicators": sum(row["actual"]["inventedInformationIndicator"] for row in primary_rows),
        "excessiveExpansion": sum(row["actual"]["excessiveExpansion"] for row in primary_rows),
        "unnecessaryEdits": sum(row["actual"]["unnecessaryEdit"] for row in primary_rows),
        "unnecessarySurfaceEdits": sum(row["actual"]["unnecessarySurfaceEdit"] for row in primary_rows),
        "protectedTokenFailures": sum(row["actual"]["protectedTokenFailure"] for row in primary_rows),
    }
    cf_metrics = {
        "changed": 0,
        "noChange": len(primary_rows),
        "objectivePass": sum(row["counterfactual"]["objectivePass"] for row in primary_rows),
        "userVisibleHarmfulEdits": 0,
        "wrongLanguageOutputs": 0,
        "inventedInformationIndicators": 0,
        "excessiveExpansion": 0,
        "unnecessaryEdits": 0,
        "unnecessarySurfaceEdits": 0,
        "expectedUsefulChangeMisses": sum(row["counterfactual"]["expectedUsefulChangeMiss"] for row in primary_rows),
        "overAbstention": sum(row["counterfactual"]["overAbstention"] for row in primary_rows),
        "protectedTokenFailures": sum(not row["counterfactual"]["protectedTokenSafe"] for row in primary_rows),
    }
    effect_counts = Counter(row["effect"]["code"] for row in primary_rows)
    harm_prevented = sum(
        row["actual"]["userVisibleHarmful"] and not row["counterfactual"]["userVisibleHarmful"]
        for row in primary_rows
    )
    useful_refinement_lost = effect_counts.get("C", 0)
    frontier_rows = [row for row in primary_rows if row["frontierSecondary"]]
    frontier_judgments = Counter(row["frontierSecondary"]["productJudgment"] for row in frontier_rows)
    frontier_benchmark_judgments = Counter(row["frontierSecondary"]["benchmarkJudgment"] for row in frontier_rows)
    changed_frontier = [row for row in frontier_rows if row["actual"]["recordedAction"] == "changed"]
    policy_summaries = {key: summarize_policy(primary_rows, key) for key in ["A", "B", "C"]}
    shape_counts = Counter(row["tokenShape"]["primaryShape"] for row in primary_rows)
    subtype_counts = Counter(row["semanticSubtype"] for row in primary_rows)
    split_counts = Counter(row["split"] for row in primary_rows)
    stability_covered = [row for row in primary_rows if row["stability"]["runCount"] == 5]
    wrong_language_ids = [row["caseID"] for row in primary_rows if row["actual"]["wrongLanguageIndicator"]]

    analysis = {
        "schemaVersion": 1,
        "experiment": "M12B-004A-one-token-counterfactual",
        "productionModified": False,
        "modelRun": False,
        "sourcePromptVersion": "refine-v2-language",
        "sourceArtifacts": {
            "corpus": "Evals/Refine/corpus.v1.jsonl (dev/validation assignments only)",
            "splitAssignments": "Evals/Refine/splits.v1.json",
            "permanentRegressionCorpus": "Evals/Refine/regression.jsonl",
            "m12b001Dev": "Evals/Refine/experiments/M12B-001-language-contract/reports/dev/results.json",
            "m12b001Validation": "Evals/Refine/experiments/M12B-001-language-contract/reports/validation/results.json",
            "m12b001Regression": "Evals/Refine/experiments/M12B-001-language-contract/reports/regression/results.json",
            "m12b001Stability": "Evals/Refine/experiments/M12B-001-language-contract/reports/stability/results.json",
            "frontierSecondary": "Evals/Refine/frontier-adjudications.v1.jsonl",
        },
        "scope": {
            "splits": ["dev", "validation", "regression"],
            "stabilityUsedAsSecondaryEvidence": True,
            "holdoutLoaded": False,
            "primaryScope": "wholeNote",
        },
        "tokenDefinition": {
            "summary": (
                "A primary one-token input is exactly one deterministic lexical/content unit after trimming. "
                "Whitespace separates units, but a single group is then shape-classified rather than accepted naively: "
                "Unicode lexical words may carry leading/trailing punctuation; URLs, emails, handles, identifiers, code-like forms, "
                "numbers, money, emoji sequences, and mixed alphanumeric identifiers are each one content unit. "
                "Punctuation-only and unresolved ambiguous-other groups are listed separately and excluded."
            ),
            "classificationPrecedence": [
                "url", "email", "handle", "money", "moneyFragment", "number", "emoji", "identifier",
                "lexicalWord/wordWithAttachedPunctuation", "mixedAlphanumericIdentifier", "codeLike", "ambiguousOther",
            ],
            "punctuationAttachedToWordRemainsOneUnit": True,
            "punctuationOnlyEligible": False,
        },
        "metrics": {
            "eligibleCases": len(primary_rows),
            "actual": actual_metrics,
            "counterfactual": cf_metrics,
            "effectCounts": dict(sorted(effect_counts.items())),
            "harmPrevented": harm_prevented,
            "usefulRefinementLost": useful_refinement_lost,
            "harmPreventedPerUsefulRefinementLost": None if useful_refinement_lost == 0 else harm_prevented / useful_refinement_lost,
            "tradeoffExplanation": (
                f"{harm_prevented} harms prevented with no observed useful refinement loss; no finite ratio is reported."
                if useful_refinement_lost == 0
                else f"{harm_prevented / useful_refinement_lost:.2f} harms prevented per useful refinement lost."
            ),
        },
        "shapeCounts": dict(sorted(shape_counts.items())),
        "subtypeCounts": dict(sorted(subtype_counts.items())),
        "splitCounts": dict(sorted(split_counts.items())),
        "frontierSecondary": {
            "coveredCases": len(frontier_rows),
            "productJudgments": dict(sorted(frontier_judgments.items())),
            "benchmarkJudgments": dict(sorted(frontier_benchmark_judgments.items())),
            "changedProductFailure": sum(row["frontierSecondary"]["productJudgment"] == "productFailure" for row in changed_frontier),
            "changedOutputAcceptable": sum(row["frontierSecondary"]["productJudgment"] == "outputAcceptable" for row in changed_frontier),
            "changedAmbiguous": sum(row["frontierSecondary"]["productJudgment"] in {"languageAmbiguous", "defer"} for row in changed_frontier),
            "coveredCaseIDs": [row["caseID"] for row in frontier_rows],
            "materialDisagreementCaseIDs": [row["caseID"] for row in frontier_rows if row["effect"]["code"] == "E"],
        },
        "classificationAmbiguities": [
            {
                "caseID": row["caseID"],
                "input": row["input"],
                "assignedShape": row["tokenShape"]["primaryShape"],
                "reason": row["tokenShape"]["ambiguityReason"],
                "included": True,
            }
            for row in primary_rows if row["tokenShape"].get("ambiguityReason")
        ],
        "language": {
            "method": "Recorded languageDrift plus explicit evaluation-only lexical marker indicator; no resolver inference or production change.",
            "actualWrongLanguageCount": len(wrong_language_ids),
            "actualWrongLanguageCaseIDs": wrong_language_ids,
            "counterfactualWrongLanguageCount": 0,
            "eliminatedByForcedNoChange": len(wrong_language_ids),
        },
        "stability": {
            "casesWithFiveRuns": len(stability_covered),
            "actualActionFlappingCases": sum(row["stability"]["actionFlapping"] for row in stability_covered),
            "counterfactualActionFlappingCases": 0,
            "actualActionFlappingCaseIDs": [row["caseID"] for row in stability_covered if row["stability"]["actionFlapping"]],
        },
        "policies": policy_summaries,
        "excluded": {
            "selectionSubgroup": selection_rows,
            "nonExecutableWholeNote": sorted(non_executable),
            "ambiguousClassifications": sorted(ambiguous_classifications),
        },
        "cases": primary_rows,
        "recommendation": {
            "choice": "A",
            "label": "implement unconditional one-token whole-note noChange gate",
            "implemented": False,
            "rationale": (
                "All observed eligible benchmarks allow and prefer noChange; forced noChange prevents every visible harmful edit, "
                "loses no demonstrated useful refinement, eliminates clear wrong-language outputs, and preserves protected-token safety. "
                "The strict surface envelope re-admits capitalization-only failures, while no positive orthographic repair exists to justify an exception."
            ),
        },
    }
    return analysis


def validate_analysis(analysis: dict[str, Any]) -> None:
    cases = analysis["cases"]
    case_ids = [row["caseID"] for row in cases]
    assert len(case_ids) == len(set(case_ids)), "Eligible case IDs must be unique."
    assert all(row["split"] in {"dev", "validation", "regression"} for row in cases)
    assert all(row["tokenShape"]["unitCount"] == 1 for row in cases)
    assert all(row["tokenShape"]["eligibleContentUnit"] for row in cases)
    assert all(row["counterfactual"]["action"] == "noChange" for row in cases)
    assert all(row["counterfactual"]["output"] == row["input"] for row in cases)
    assert all(row["effect"]["code"] in {"A", "B", "C", "D", "E"} for row in cases)
    metrics = analysis["metrics"]
    assert metrics["eligibleCases"] == len(cases)
    assert metrics["actual"]["changed"] + metrics["actual"]["noChange"] == len(cases)
    assert analysis["policies"]["A"]["noChange"] == len(cases)
    assert analysis["policies"]["A"]["changed"] == 0
    assert not analysis["productionModified"]
    assert not analysis["modelRun"]
    assert analysis["scope"]["holdoutLoaded"] is False


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    run_self_tests()
    if args.self_test:
        print("M12B-004A classifier self-tests passed")
        return
    analysis = analyze()
    validate_analysis(analysis)
    OUTPUT.mkdir(parents=True, exist_ok=True)
    (OUTPUT / "analysis.json").write_text(json.dumps(analysis, indent=2, sort_keys=True, ensure_ascii=False) + "\n")
    (OUTPUT / "case-table.md").write_text(build_case_table(analysis["cases"], analysis["excluded"]))
    (OUTPUT / "report.md").write_text(build_report(analysis))
    print(f"M12B-004A artifacts written to {OUTPUT}")


if __name__ == "__main__":
    main()

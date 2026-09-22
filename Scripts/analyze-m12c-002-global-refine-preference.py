#!/usr/bin/env python3
"""Analyze M12C-002 global refine preference."""

from __future__ import annotations

import json
import re
import statistics
from collections import Counter, defaultdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
EVAL = ROOT / "Evals/Refine"
OUT = EVAL / "experiments/M12C-002-global-refine-preference"
REPORTS = OUT / "reports"
M12C001 = EVAL / "experiments/M12C-001-language-preference/reports"
CHALLENGE = OUT / "challenge-set.jsonl"


def read_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text())


def read_jsonl(path: Path) -> list[dict[str, Any]]:
    return [json.loads(line) for line in path.read_text().splitlines() if line.strip()]


def write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False, sort_keys=True) + "\n")


def load_records(path: Path) -> list[dict[str, Any]]:
    if not path.exists():
        return []
    return read_json(path).get("records", [])


def load_summary(path: Path) -> dict[str, Any]:
    if not path.exists():
        return {}
    return read_json(path)


def run_zero(records: list[dict[str, Any]]) -> list[dict[str, Any]]:
    return [record for record in records if record.get("runIndex", 0) == 0]


def pct(num: float) -> float:
    return round(num, 4)


def expansion_ratio(record: dict[str, Any], case: dict[str, Any]) -> float | None:
    output = record.get("output")
    if not output:
        return None
    return len(output) / max(1, len(case.get("input", "")))


def has_invented_information(record: dict[str, Any], case: dict[str, Any]) -> bool:
    if record.get("decision") != "changed":
        return False
    output = (record.get("output") or "").lower()
    input_text = case.get("input", "").lower()
    if case.get("expected", {}).get("mustNotIntroduceInformation") and record.get("decision") == "changed":
        invention_markers = [
            "attendees",
            "location:",
            "purpose:",
            "conference room",
            "sala ",
            "because we",
            "porque vamos",
            "for example",
            "por exemplo",
        ]
        for marker in invention_markers:
            if marker in output and marker not in input_text:
                return True
    return False


def wrong_language(record: dict[str, Any], case: dict[str, Any]) -> bool:
    diag = record.get("languageDiagnostics") or {}
    if diag.get("userVisibleLanguageSafe") is False and record.get("decision") == "changed":
        return True
    return False


def protected_literal_failure(record: dict[str, Any], case: dict[str, Any]) -> bool:
    if record.get("decision") != "changed":
        return False
    output = record.get("output") or ""
    for token in case.get("expected", {}).get("mustPreserveTokens") or []:
        if token not in output:
            return True
    diag = record.get("protectedLiteralDiagnostics") or {}
    return bool(diag.get("validatorRejected")) and record.get("decision") == "changed"


def selection_failure(record: dict[str, Any], case: dict[str, Any]) -> bool:
    if case.get("scope") != "selection":
        return False
    return record.get("productionRejection") in {
        "context_leak",
        "selectionDuplicateContextLeak",
        "runaway_expansion",
    }


def score_preference_adherence(record: dict[str, Any], case: dict[str, Any]) -> str:
    expected = case.get("expected", {})
    expected_label = expected.get("preferenceAdherenceExpectation") or "notApplicable"
    profile = expected.get("preferenceProfile") or "unknown"
    preference = case.get("refinePreference") or ""
    if not preference.strip():
        return "notApplicable"
    if expected.get("expectsPreferenceSuppressedForSafety"):
        if record.get("decision") == "noChange" or record.get("productionRejection"):
            return "suppressedForSafety"
        if has_invented_information(record, case) or wrong_language(record, case):
            return "violated"
        return "suppressedForSafety"

    if record.get("decision") == "noChange":
        if profile in {"concise", "combo"} and expected.get("expectsNoChange"):
            return "satisfied"
        if profile in {"bullets"} and expected_label == "notApplicable":
            return "notApplicable"
        return "partially"

    output = record.get("output") or ""
    ratio = expansion_ratio(record, case) or 1.0

    if profile == "concise" or (profile == "combo" and "concise" in preference.lower()):
        max_ratio = expected.get("maxExpansionRatio") or 1.5
        if ratio <= max(1.1, max_ratio - 0.2):
            return "satisfied"
        if ratio <= max_ratio:
            return "partially"
        return "violated"

    if profile == "casual" or (profile == "combo" and "casual" in preference.lower()):
        formal_markers = ["furthermore", "therefore", "accordingly", "portanto", "ademais", "por conseguinte"]
        if any(marker in output.lower() for marker in formal_markers):
            return "violated"
        return "satisfied" if expected_label == "satisfied" else "partially"

    if profile == "bullets":
        if re.search(r"(^|\n)\s*[-•*]\s+", output):
            return "satisfied"
        if "," in case.get("input", "") or len(case.get("input", "").split()) >= 3:
            return "partially"
        return "notApplicable"

    if profile == "avoid-formality":
        formal_markers = ["cordialmente", "atenciosamente", "sincerely", "kind regards", "prezado", "estimado"]
        if any(marker in output.lower() for marker in formal_markers):
            return "violated"
        return "satisfied"

    if profile == "technical":
        for token in expected.get("mustPreserveTokens") or []:
            if token not in output:
                return "violated"
        return "satisfied"

    if profile == "adversarial":
        return "suppressedForSafety"

    return expected_label


def safety_metrics(records: list[dict[str, Any]], case_map: dict[str, dict[str, Any]]) -> dict[str, Any]:
    records = run_zero(records)
    invented = 0
    wrong_lang = 0
    protected = 0
    selection = 0
    excessive = 0
    forced_change = 0
    for record in records:
        case = case_map[record["caseID"]]
        if has_invented_information(record, case):
            invented += 1
        if wrong_language(record, case):
            wrong_lang += 1
        if protected_literal_failure(record, case):
            protected += 1
        if selection_failure(record, case):
            selection += 1
        ratio = expansion_ratio(record, case)
        if ratio is not None and ratio > (case.get("expected", {}).get("maxExpansionRatio") or 2.5):
            excessive += 1
        if case.get("expected", {}).get("expectsNoChange") and record.get("decision") == "changed":
            forced_change += 1
    total = len(records)
    return {
        "runs": total,
        "inventedInformationCount": invented,
        "wrongLanguageCount": wrong_lang,
        "protectedLiteralFailureCount": protected,
        "selectionFailureCount": selection,
        "excessiveExpansionCount": excessive,
        "inappropriateForcedChangeCount": forced_change,
    }


def adherence_metrics(records: list[dict[str, Any]], case_map: dict[str, dict[str, Any]]) -> dict[str, Any]:
    records = run_zero(records)
    by_profile: dict[str, Counter[str]] = defaultdict(Counter)
    overall = Counter()
    for record in records:
        case = case_map[record["caseID"]]
        label = score_preference_adherence(record, case)
        profile = case.get("expected", {}).get("preferenceProfile") or "unknown"
        by_profile[profile][label] += 1
        overall[label] += 1
    return {
        "overall": dict(overall),
        "byProfile": {profile: dict(counts) for profile, counts in by_profile.items()},
    }


def latency_stats(records: list[dict[str, Any]]) -> dict[str, float | None]:
    latencies = [float(r["latencyMs"]) for r in run_zero(records) if r.get("latencyMs") is not None]
    if not latencies:
        return {"p50": None, "p95": None}
    latencies.sort()
    p50 = statistics.median(latencies)
    idx = max(0, min(len(latencies) - 1, int(round(0.95 * (len(latencies) - 1)))))
    return {"p50": pct(p50), "p95": pct(latencies[idx])}


def compare_empty(name: str, current: dict[str, Any], baseline: dict[str, Any]) -> dict[str, Any]:
    cur_pass = current.get("objectivePassRate")
    base_pass = baseline.get("objectivePassRate")
    return {
        "split": name,
        "objectivePassRate": {"current": cur_pass, "m12c001": base_pass, "delta": None if cur_pass is None or base_pass is None else pct(cur_pass - base_pass)},
        "criticalFailureCount": {
            "current": current.get("criticalFailureCount"),
            "m12c001": baseline.get("criticalFailureCount"),
            "delta": None,
        },
    }


def stability_metrics(records: list[dict[str, Any]]) -> dict[str, Any]:
    by_case: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for record in records:
        by_case[record["caseID"]].append(record)
    decision_instability = 0
    output_instability = 0
    for case_records in by_case.values():
        decisions = {r.get("decision") for r in case_records}
        if len(decisions) > 1:
            decision_instability += 1
        outputs = {r.get("output") for r in case_records if r.get("output") is not None}
        if len(outputs) > 1:
            output_instability += 1
    return {
        "cases": len(by_case),
        "decisionInstabilityCases": decision_instability,
        "outputInstabilityCases": output_instability,
    }


def acceptance(analysis: dict[str, Any]) -> tuple[str, list[str]]:
    blockers: list[str] = []
    safety = analysis["challengeSafety"]
    if safety["protectedLiteralFailureCount"] > 0:
        blockers.append("protected literal failure under preference")
    if safety["selectionFailureCount"] > 0:
        blockers.append("selection failure under preference")
    if safety["wrongLanguageCount"] > 0:
        blockers.append("wrong language under preference")
    if safety["inventedInformationCount"] > 2:
        blockers.append("invented information from preference cases")

    for split, payload in analysis["emptyPreferenceRegression"].items():
        delta = payload.get("objectivePassRate", {}).get("delta")
        if delta is not None and delta < -0.05:
            blockers.append(f"empty preference causal regression on {split}")

    adherence = analysis["challengeAdherence"]["overall"]
    if adherence.get("violated", 0) > adherence.get("satisfied", 0) // 2 + 3:
        blockers.append("preference violations exceed acceptable style noise")

    if blockers:
        return "REJECT", blockers
    return "ACCEPT", blockers


def write_docs(analysis: dict[str, Any], decision: str, blockers: list[str]) -> None:
    (OUT / "report.md").write_text(
        "\n".join(
            [
                "# M12C-002 — Global Refine preference",
                "",
                f"## Decision: **{decision}**",
                "",
                "## Challenge safety",
                "",
                *(f"- {key}: {value}" for key, value in analysis["challengeSafety"].items()),
                "",
                "## Empty preference regression vs M12C-001",
                "",
                *[
                    f"- **{name}**: objective Δ {payload['objectivePassRate']['delta']}"
                    for name, payload in analysis["emptyPreferenceRegression"].items()
                ],
                "",
                "## Preference adherence (challenge)",
                "",
                f"- Overall: {analysis['challengeAdherence']['overall']}",
                "",
                *(["## Blockers", ""] + [f"- {item}" for item in blockers] if blockers else []),
                "",
                "See `analysis.json`, `preference-policy.md`, and `production-diff.md`.",
            ]
        )
        + "\n"
    )

    (OUT / "preference-policy.md").write_text(
        "\n".join(
            [
                "# M12C-002 global refine preference policy",
                "",
                "## Authority hierarchy",
                "1. Rasc safety contract",
                "2. Language policy (M12C-001)",
                "3. Semantic preservation requirements",
                "4. User Refine preference",
                "5. Note content (untrusted)",
                "",
                "## Integration",
                "- Optional Settings text persisted locally (max 500 chars, trimmed)",
                "- Omitted entirely from instructions when empty",
                "- Wrapped in `<refine_preference>` when present",
                "- One Foundation Models generation only",
            ]
        )
        + "\n"
    )

    (OUT / "production-diff.md").write_text(
        "\n".join(
            [
                "# M12C-002 production diff",
                "",
                "## Added",
                "- `RefinePreferenceSettingsStore`",
                "- Settings → Refine → Refine preferences text field",
                "- `RefinementRequest.stylePreference`",
                "",
                "## Changed",
                "- `RefinementPrompt` preference authority + optional `<refine_preference>` block",
                "- Prompt version → `refine-v2-global-preference`",
                "",
                "## Unchanged",
                "- All deterministic safety guards",
                "- Language preference behavior",
            ]
        )
        + "\n"
    )

    (OUT / "experiment.md").write_text(
        "\n".join(
            [
                "# M12C-002 — Global Refine preference",
                "",
                "Optional global style preference under Settings → Refine.",
                "",
                f"Decision: **{decision}**",
            ]
        )
        + "\n"
    )


def main() -> None:
    case_map = {row["id"]: row for row in read_jsonl(CHALLENGE)}
    challenge_records = load_records(REPORTS / "preference-challenge/results.json")
    stability_records = load_records(REPORTS / "stability/results.json")

    analysis: dict[str, Any] = {
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        "baseline": "M12C-001",
        "promptIntegration": {
            "version": "refine-v2-global-preference",
            "blockTag": "<refine_preference>",
            "omittedWhenEmpty": True,
        },
        "challengeSafety": safety_metrics(challenge_records, case_map),
        "challengeAdherence": adherence_metrics(challenge_records, case_map),
        "emptyPreferenceRegression": {
            "dev": compare_empty(
                "dev",
                load_summary(REPORTS / "empty-preference-dev/summary.json"),
                load_summary(M12C001 / "matchnote-regression-dev/summary.json"),
            ),
            "validation": compare_empty(
                "validation",
                load_summary(REPORTS / "empty-preference-validation/summary.json"),
                load_summary(M12C001 / "matchnote-regression-validation/summary.json"),
            ),
            "regression": compare_empty(
                "regression",
                load_summary(REPORTS / "empty-preference-regression/summary.json"),
                load_summary(M12C001 / "matchnote-regression/summary.json"),
            ),
        },
        "latency": latency_stats(challenge_records),
        "stability": stability_metrics(stability_records),
    }

    decision, blockers = acceptance(analysis)
    analysis["decision"] = decision
    analysis["blockers"] = blockers

    write_json(OUT / "analysis.json", analysis)
    write_docs(analysis, decision, blockers)
    print(f"M12C-002 analysis complete: {decision}")


if __name__ == "__main__":
    main()

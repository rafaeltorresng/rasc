#!/usr/bin/env python3
"""Analyze M12C-001 Refine language preference."""

from __future__ import annotations

import json
import statistics
from collections import Counter, defaultdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
EVAL = ROOT / "Evals/Refine"
OUT = EVAL / "experiments/M12C-001-language-preference"
REPORTS = OUT / "reports"
REFINE_V2 = EVAL / "experiments/M12B-008-integrated-reliability/reports"
CORPUS = OUT / "eval-corpus.v1.jsonl"


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


def pct(num: float) -> float:
    return round(num, 4)


def run_zero(records: list[dict[str, Any]]) -> list[dict[str, Any]]:
    return [record for record in records if record.get("runIndex", 0) == 0]


def latency_stats(records: list[dict[str, Any]]) -> dict[str, float | None]:
    latencies = [float(r["latencyMs"]) for r in run_zero(records) if r.get("latencyMs") is not None]
    if not latencies:
        return {"p50": None, "p95": None}
    latencies.sort()
    p50 = statistics.median(latencies)
    idx = max(0, min(len(latencies) - 1, int(round(0.95 * (len(latencies) - 1)))))
    return {"p50": pct(p50), "p95": pct(latencies[idx])}


LABEL_MAP = {
    "pt": "portuguese",
    "en": "english",
    "es": "spanish",
    "portuguese": "portuguese",
    "english": "english",
    "spanish": "spanish",
}


def normalize_language_label(label: str | None) -> str | None:
    if not label:
        return None
    return LABEL_MAP.get(label.lower(), label.lower())


def wrong_target_language(record: dict[str, Any], case: dict[str, Any]) -> bool:
    if case.get("languagePolicy", {}).get("mode") != "fixedLocale":
        return False
    if record.get("decision") != "changed":
        return False
    expected = normalize_language_label(case.get("expected", {}).get("expectedLanguage"))
    diag = record.get("languageDiagnostics") or {}
    if diag.get("userVisibleLanguageSafe") is False:
        return True
    assessment = diag.get("generatedLanguageAssessment") or {}
    generated = normalize_language_label(assessment.get("label"))
    if not expected or not generated:
        return False
    return generated != expected


def final_visible_failures(record: dict[str, Any]) -> list[str]:
    failures: list[str] = []
    if record.get("productionRejection"):
        failures.append(str(record["productionRejection"]))
    for score in record.get("objectiveFailures") or []:
        kind = score.get("kind") if isinstance(score, dict) else None
        if kind:
            failures.append(str(kind))
    return failures


def split_metrics(records: list[dict[str, Any]], case_map: dict[str, dict[str, Any]]) -> dict[str, Any]:
    records = run_zero(records)
    total = len(records)
    changed = sum(1 for r in records if r.get("decision") == "changed")
    no_change = sum(1 for r in records if r.get("decision") == "noChange")
    wrong_target = 0
    protected_failures = 0
    selection_failures = 0
    critical_failures = 0

    for record in records:
        case = case_map.get(record["caseID"], {})
        if wrong_target_language(record, case):
            wrong_target += 1
        output = record.get("output") or ""
        for token in case.get("expected", {}).get("mustPreserveTokens") or []:
            if record.get("decision") == "changed" and token not in output:
                protected_failures += 1
        if case.get("scope") == "selection" and record.get("productionRejection") in {
            "context_leak",
            "selectionDuplicateContextLeak",
            "runaway_expansion",
        }:
            selection_failures += 1
        if record.get("severity") == "critical" and record.get("decision") == "changed":
            objective_pass = record.get("passedObjectively")
            if objective_pass is False:
                critical_failures += 1

    return {
        "runs": total,
        "changedRate": pct(changed / total) if total else None,
        "noChangeRate": pct(no_change / total) if total else None,
        "wrongTargetLanguageCount": wrong_target,
        "wrongTargetLanguageRate": pct(wrong_target / total) if total else None,
        "protectedLiteralFailureCount": protected_failures,
        "selectionFailureCount": selection_failures,
        "criticalFailureCount": critical_failures,
        **latency_stats(records),
    }


def cohort_metrics(records: list[dict[str, Any]], case_map: dict[str, Any], mode: str) -> dict[str, Any]:
    ids = {
        case_id
        for case_id, case in case_map.items()
        if case.get("languagePolicy", {}).get("mode") == mode
    }
    filtered = [record for record in run_zero(records) if record["caseID"] in ids]
    return split_metrics(filtered, case_map)


def compare_regression(name: str, current_summary: dict[str, Any], baseline_summary: dict[str, Any]) -> dict[str, Any]:
    def metric(key: str) -> Any:
        return current_summary.get(key), baseline_summary.get(key)

    cur_pass, base_pass = metric("objectivePassRate")
    cur_crit, base_crit = metric("criticalFailureCount")
    cur_harm, base_harm = metric("userVisibleHarmfulEditRate")
    return {
        "split": name,
        "objectivePassRate": {"current": cur_pass, "refineV2": base_pass, "delta": None if cur_pass is None or base_pass is None else pct(cur_pass - base_pass)},
        "criticalFailureCount": {"current": cur_crit, "refineV2": base_crit, "delta": None if cur_crit is None or base_crit is None else cur_crit - base_crit},
        "userVisibleHarmfulEditRate": {"current": cur_harm, "refineV2": base_harm, "delta": None if cur_harm is None or base_harm is None else pct(cur_harm - base_harm)},
    }


def acceptance(analysis: dict[str, Any]) -> tuple[str, list[str]]:
    blockers: list[str] = []
    lp = analysis["languagePreference"]
    if lp.get("wrongTargetLanguageCount", 0) > 0:
        blockers.append("wrong fixed-target language reached preview")
    if lp.get("protectedLiteralFailureCount", 0) > 0:
        blockers.append("protected literal corruption under fixed locale")
    if lp.get("selectionFailureCount", 0) > 0:
        blockers.append("selection boundary failure under fixed locale")

    for regression in analysis["matchNoteRegression"].values():
        crit_delta = regression.get("criticalFailureCount", {}).get("delta")
        if crit_delta is not None and crit_delta > 2:
            blockers.append(f"causal critical regression on {regression['split']}")

    if blockers:
        return "REJECT", blockers
    return "ACCEPT", blockers


def write_docs(analysis: dict[str, Any], decision: str, blockers: list[str]) -> None:
    report = OUT / "report.md"
    report.write_text(
        "\n".join(
            [
                "# M12C-001 — Refine language preference",
                "",
                f"## Decision: **{decision}**",
                "",
                "## Language preference corpus",
                "",
                f"- Runs: {analysis['languagePreference'].get('runs')}",
                f"- Wrong target language: {analysis['languagePreference'].get('wrongTargetLanguageCount')}",
                f"- Protected literal failures: {analysis['languagePreference'].get('protectedLiteralFailureCount')}",
                f"- Selection failures: {analysis['languagePreference'].get('selectionFailureCount')}",
                f"- noChange rate: {analysis['languagePreference'].get('noChangeRate')}",
                f"- Latency p50/p95: {analysis['languagePreference'].get('p50')} / {analysis['languagePreference'].get('p95')} ms",
                "",
                "## Match note regression vs refine-v2 (M12B-008)",
                "",
            ]
            + [
                f"- **{name}**: objective Δ {payload['objectivePassRate']['delta']}, critical Δ {payload['criticalFailureCount']['delta']}"
                for name, payload in analysis["matchNoteRegression"].items()
            ]
            + ([ "", "## Blockers", ""] + [f"- {item}" for item in blockers] if blockers else [])
            + ["", "See `analysis.json`, `language-preference-policy.md`, and `production-diff.md`."],
        )
        + "\n"
    )

    policy = OUT / "language-preference-policy.md"
    policy.write_text(
        "\n".join(
            [
                "# M12C-001 language preference policy",
                "",
                "## Default",
                "- Match note language (`RefineLanguagePolicy.matchNote`)",
                "",
                "## Fixed locale",
                "- User selects a supported Foundation Models locale in Settings → Refine → Language",
                "- Resolver uses fixed target contract (`fixed_locale_policy`)",
                "- Validator checks output against selected target, not source note language",
                "- Intentional translation is authorized; ignored target rejects to existing noChange",
                "",
                "## Unsupported saved locale",
                "- Execute with Match note language",
                "- Keep stored preference; surface fallback in Settings",
                "",
                "## Safety invariants",
                "- Preflight, protected literals, money/percentage/time, selection guards remain active",
                "- One Foundation Models generation only",
            ]
        )
        + "\n"
    )

    diff = OUT / "production-diff.md"
    diff.write_text(
        "\n".join(
            [
                "# M12C-001 production diff",
                "",
                "## Added",
                "- `RefineLanguageSettingsStore` (UserDefaults persistence)",
                "- `RefineSupportedLocales` (SystemLanguageModel.supportedLanguages / supportsLocale)",
                "- Settings → Refine → Language picker",
                "",
                "## Changed",
                "- `ScratchpadSession` passes effective language policy into `RefinementRequest`",
                "- `RefinementPrompt` fixed-target instructions + prompt version bump",
                "- Eval runner executes fixedLocale cases via `isExecutableUnderProduction`",
                "",
                "## Unchanged",
                "- Match note resolver/validator/unresolved-guard behavior for default preference",
                "- Single-generation FM pipeline and deterministic safety guards",
            ]
        )
        + "\n"
    )

    experiment = OUT / "experiment.md"
    experiment.write_text(
        "\n".join(
            [
                "# M12C-001 — Refine language preference",
                "",
                "First M12C personalization feature: explicit fixed output language.",
                "",
                "Baseline: `refine-v2` (M12B closeout).",
                "",
                f"Decision: **{decision}**",
            ]
        )
        + "\n"
    )


def main() -> None:
    case_map = {row["id"]: row for row in read_jsonl(CORPUS)}
    lp_records = load_records(REPORTS / "language-preference/results.json")

    by_target: dict[str, Any] = defaultdict(dict)
    for record in run_zero(lp_records):
        case = case_map[record["caseID"]]
        if case.get("languagePolicy", {}).get("mode") != "fixedLocale":
            continue
        locale = case["languagePolicy"].get("locale") or "unknown"
        bucket = by_target[locale]
        bucket.setdefault("cases", []).append(record["caseID"])
        if wrong_target_language(record, case):
            bucket["wrongTarget"] = bucket.get("wrongTarget", 0) + 1

    analysis: dict[str, Any] = {
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        "baseline": RefinementImplementationBaseline_identifier(),
        "languagePreference": split_metrics(lp_records, case_map),
        "matchNoteCohort": cohort_metrics(lp_records, case_map, "matchNote"),
        "fixedLocaleCohort": cohort_metrics(lp_records, case_map, "fixedLocale"),
        "fixedLocaleByTarget": {
            locale: {
                "caseIDs": payload.get("cases", []),
                "wrongTargetLanguageCount": payload.get("wrongTarget", 0),
            }
            for locale, payload in by_target.items()
        },
        "matchNoteRegression": {
            "dev": compare_regression("dev", load_summary(REPORTS / "matchnote-regression-dev/summary.json"), load_summary(REFINE_V2 / "dev/summary.json")),
            "validation": compare_regression(
                "validation",
                load_summary(REPORTS / "matchnote-regression-validation/summary.json"),
                load_summary(REFINE_V2 / "validation/summary.json"),
            ),
            "regression": compare_regression(
                "regression",
                load_summary(REPORTS / "matchnote-regression/summary.json"),
                load_summary(REFINE_V2 / "regression/summary.json"),
            ),
        },
    }

    decision, blockers = acceptance(analysis)
    analysis["decision"] = decision
    analysis["blockers"] = blockers

    write_json(OUT / "analysis.json", analysis)
    write_docs(analysis, decision, blockers)
    print(f"M12C-001 analysis complete: {decision}")


def RefinementImplementationBaseline_identifier() -> str:
    return "refine-v2"


if __name__ == "__main__":
    main()

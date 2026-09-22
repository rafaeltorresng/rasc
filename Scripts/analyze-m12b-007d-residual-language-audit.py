#!/usr/bin/env python3
"""M12B-007D residual language failure audit (evaluation-only)."""

from __future__ import annotations

import json
from collections import Counter, defaultdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
EVAL = ROOT / "Evals/Refine"
OUT = EVAL / "experiments/M12B-007D-residual-language-audit"
REPORTS = EVAL / "experiments/M12B-007B-language-resolver-v2/reports"
CORPUS = EVAL / "corpus.v1.jsonl"
REGRESSION = EVAL / "regression.jsonl"

PRIORITY_CASES = [
    "legacy-selection-unicode-pt-001",
    "numbers-003",
    "meeting-dump-003",
    "selection-extra-007",
    "variant-pt-022",
    "variant-pt-023",
    "variant-pt-024",
    "short-pt-009",
    "short-pt-012",
    "telegraphic-pt-009",
    "variant-pt-013",
]

CAUSAL_REGRESSIONS = [
    "legacy-selection-unicode-pt-001",
    "numbers-003",
    "short-pt-009",
    "short-pt-012",
    "telegraphic-pt-009",
    "variant-pt-013",
]

PT_MARKERS = {
    "ação", "amanhã", "acho", "depois", "falar", "não", "obrigado", "reunião", "talvez", "ver",
    "você", "pra", "tá", "também", "porque", "então", "hoje", "sexta", "relatório", "enviar",
    "revisar", "com", "sobre", "né", "msg", "cadê", "demora", "ideia", "mandar", "versão",
    "preciso", "fechar", "subir", "filas", "fila", "ajustar", "ideia", "café", "otimo", "ótimo",
    "instruções", "ignorar", "rollback", "preciso", "checar", "validar", "pingar", "export", "hj",
}
EN_MARKERS = {
    "the", "and", "maybe", "tomorrow", "check", "should", "would", "meeting", "thanks", "please",
    "review", "before", "after", "might", "could", "about", "team", "launch", "later", "please",
    "expand", "project", "plan", "milestones", "sales", "units", "target", "version", "build",
}
ES_MARKERS = {
    "el", "la", "los", "las", "quizás", "quizá", "mañana", "hola", "gracias", "reunión", "tal vez",
    "equipo", "después", "hoy", "viernes", "debería", "informe", "instrucciones", "instrucciones",
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


def norm_label(value: str | None) -> str:
    mapping = {
        "portuguese": "pt",
        "english": "en",
        "spanish": "es",
        "mixed": "mixed",
        "ambiguous": "ambiguous",
        "unknown": "unknown",
        "pt": "pt",
        "en": "en",
        "es": "es",
    }
    if value is None:
        return "unknown"
    return mapping.get(str(value).lower(), str(value).lower())


def load_case_map() -> dict[str, dict[str, Any]]:
    case_map = {row["id"]: row for row in read_jsonl(CORPUS)}
    case_map.update({row["id"]: row for row in read_jsonl(REGRESSION)})
    return case_map


def load_primary_records() -> dict[str, dict[str, Any]]:
    records: dict[str, dict[str, Any]] = {}
    for split in ["dev", "validation", "regression"]:
        path = REPORTS / split / "results.json"
        if not path.exists():
            continue
        for record in read_json(path).get("records", []):
            if record.get("runIndex", 0) != 0:
                continue
            record = dict(record)
            record["_split"] = split
            records[record["caseID"]] = record
    return records


def token_count(text: str) -> int:
    return len([part for part in text.split() if part.strip()])


def token_bucket(count: int) -> str:
    if count <= 3:
        return "1-3"
    if count <= 8:
        return "4-8"
    return "9+"


def is_unresolved(diag: dict[str, Any]) -> bool:
    label = norm_label(diag.get("resolvedLabel"))
    return diag.get("resolverConfidence") != "high" or label in {"ambiguous", "unknown"}


def labels_match(resolver: str, expected: str | None) -> bool:
    if not expected or expected in {"unknown", "mixed"}:
        return True
    return norm_label(resolver) == norm_label(expected)


def marker_score(text: str, markers: set[str]) -> int:
    lowered = f" {text.lower()} "
    score = 0
    for marker in markers:
        if " " in marker:
            if marker in text.lower():
                score += 1
        elif f" {marker} " in lowered or lowered.startswith(f" {marker} ") or lowered.endswith(f" {marker} "):
            score += 1
    return score


EN_INFINITIVE_FALSE_POSITIVES = {
    "after", "answer", "buffer", "character", "cluster", "error", "filter", "footer", "header",
    "master", "monitor", "number", "offer", "order", "over", "parameter", "partner", "render",
    "super", "timer", "tracker", "transfer", "under", "user", "review",
}


def portuguese_morphology_score(text: str) -> int:
    score = 0
    if any(ch in text.lower() for ch in "ãõáéíóúâêôç"):
        score += 2
    for token in text.lower().split():
        cleaned = token.strip(".,!?;:")
        if len(cleaned) >= 4 and (
            cleaned.endswith("ar") or cleaned.endswith("er") or cleaned.endswith("ir")
        ):
            if cleaned not in EN_INFINITIVE_FALSE_POSITIVES:
                score += 2
    if " no " in f" {text.lower()} " or " na " in f" {text.lower()} ":
        score += 1
    return score


def source_language_evidence(text: str, expected: str | None, case: dict[str, Any]) -> tuple[str, bool]:
    pt = marker_score(text, PT_MARKERS) + portuguese_morphology_score(text)
    en = marker_score(text, EN_MARKERS)
    es = marker_score(text, ES_MARKERS)
    ordered = sorted([("pt", pt), ("en", en), ("es", es)], key=lambda item: item[1], reverse=True)
    top, second = ordered[0], ordered[1]
    if top[1] == 0:
        if expected in {"pt", "en", "es"} and case.get("tags"):
            tags = set(case.get("tags") or [])
            if expected == "pt" and tags.intersection({"pt", "short", "telegraphic", "variant"}):
                return "pt", False
        return "ambiguous", False
    if second[1] > 0 and abs(top[1] - second[1]) <= 1:
        return "mixed", False
    return top[0], top[1] >= 2


def is_user_visible_wrong_language(record: dict[str, Any]) -> bool:
    diag = record.get("languageDiagnostics") or {}
    return record.get("decision") == "changed" and diag.get("userVisibleLanguageSafe") is False


def is_language_false_rejection(record: dict[str, Any]) -> bool:
    diag = record.get("languageDiagnostics") or {}
    return bool(diag.get("postValidatorRejected") and diag.get("generationLanguageCorrect") is True)


def is_useful_refinement(record: dict[str, Any]) -> bool:
    diag = record.get("languageDiagnostics") or {}
    return (
        record.get("decision") == "changed"
        and not record.get("productionRejection")
        and diag.get("generationLanguageCorrect") is True
        and diag.get("userVisibleLanguageSafe") is True
    )


def classify_wrong_language_primary(record: dict[str, Any], case: dict[str, Any]) -> tuple[str, list[str]]:
    diag = record.get("languageDiagnostics") or {}
    expected = norm_label((case.get("expected") or {}).get("expectedLanguage") or diag.get("expectedLanguage"))
    resolver_label = norm_label(diag.get("resolvedLabel"))
    resolver_conf = diag.get("resolverConfidence")
    assessment = diag.get("generatedLanguageAssessment") or {}
    raw_label = norm_label(assessment.get("label"))
    contributing: list[str] = []

    resolver_wrong_high = (
        resolver_conf == "high"
        and expected not in {"unknown", "mixed"}
        and not labels_match(resolver_label, expected)
    )
    if resolver_wrong_high:
        if raw_label == norm_label(resolver_label):
            contributing.append("generationFollowedWrongTarget")
        return "resolverWrongHighConfidence", contributing

    if is_unresolved(diag):
        if expected == "pt" and raw_label == "en":
            contributing.append("shortTelegraphicPTDrift")
        return "resolverUnresolved", contributing

    resolver_correct = resolver_conf == "high" and labels_match(resolver_label, expected)
    if resolver_correct:
        if diag.get("postValidatorEvaluated") and not diag.get("postValidatorRejected"):
            if raw_label not in {resolver_label, expected, "mixed", "ambiguous", "unknown"}:
                return "validatorMissedMismatch", contributing + ["postValidatorEvaluatedButPassed"]
        if raw_label not in {resolver_label, expected, "mixed", "ambiguous", "unknown"}:
            return "generationIgnoredCorrectTarget", contributing + ["modelIgnoredResolvedTarget"]
        return "evaluatorDisagreement", contributing

    if assessment.get("disagreesWithMarkers"):
        return "evaluatorDisagreement", contributing + ["markerAssessmentDisagreement"]
    return "other", contributing


def classify_false_rejection_primary(record: dict[str, Any], case: dict[str, Any]) -> tuple[str, list[str]]:
    diag = record.get("languageDiagnostics") or {}
    expected = norm_label((case.get("expected") or {}).get("expectedLanguage") or diag.get("expectedLanguage"))
    assessment = diag.get("generatedLanguageAssessment") or {}
    raw_label = norm_label(assessment.get("label"))
    resolved = norm_label(diag.get("resolvedLabel"))
    contributing: list[str] = []

    if expected == "mixed" or "mixed" in set(case.get("tags") or []):
        return "mixedTechnicalMisclassified", contributing + ["mixedExpectedEnglishDominantOutput"]

    if assessment.get("confidence") in {"requiresReview", "low"}:
        return "languageEvaluatorWrong", contributing + ["lowConfidenceAssessment"]

    if raw_label == resolved and diag.get("generationLanguageCorrect") is True:
        marker = norm_label(assessment.get("markerLabel"))
        if marker and marker != resolved:
            return "validatorTooAggressive", contributing + ["markerDetectDisagreedWithCorrectOutput"]
        return "validatorTooAggressive", contributing

    if diag.get("generationLanguageCorrect") is False:
        return "outputActuallyWrongLanguage", contributing

    if not expected or expected == "unknown":
        return "other", contributing + ["missingExpectedLanguage"]

    return "validatorTooAggressive", contributing


def current_validator_rejects(record: dict[str, Any]) -> bool:
    return bool((record.get("languageDiagnostics") or {}).get("postValidatorRejected"))


def policy_a_would_reject(record: dict[str, Any], case: dict[str, Any]) -> bool:
    diag = record.get("languageDiagnostics") or {}
    if not is_unresolved(diag):
        return False
    if diag.get("rawGeneratedDecision") != "changed":
        return False

    assessment = diag.get("generatedLanguageAssessment") or {}
    out_label = norm_label(assessment.get("label"))
    out_conf = assessment.get("confidence")
    if out_conf != "high" or out_label in {"ambiguous", "unknown", "mixed"}:
        return False

    expected = norm_label((case.get("expected") or {}).get("expectedLanguage") or diag.get("expectedLanguage"))
    source_label, strong = source_language_evidence(record.get("input", ""), expected, case)
    if source_label in {"ambiguous", "mixed"} or not strong:
        return False
    return out_label != source_label


def policy_b_validator_decision(record: dict[str, Any], case: dict[str, Any]) -> bool | None:
    """Return True reject, False accept, None unchanged (validator not applicable)."""
    diag = record.get("languageDiagnostics") or {}
    if is_unresolved(diag):
        return None
    if not diag.get("postValidatorEvaluated"):
        return None

    assessment = diag.get("generatedLanguageAssessment") or {}
    resolved = norm_label(diag.get("resolvedLabel"))
    raw_label = norm_label(assessment.get("label"))
    raw_conf = assessment.get("confidence")

    if resolved in {"mixed", "ambiguous", "unknown"}:
        return None

    # Relaxation: trust high-confidence independent assessment matching resolved target.
    if raw_conf == "high" and raw_label == resolved:
        return False

    # Tightening: reject on high-confidence assessment mismatch even if marker detect passed.
    if raw_conf == "high" and raw_label not in {resolved, "mixed", "ambiguous", "unknown"}:
        return True

    return current_validator_rejects(record)


def build_case_row(record: dict[str, Any], case: dict[str, Any], cohort: str) -> dict[str, Any]:
    diag = record.get("languageDiagnostics") or {}
    assessment = diag.get("generatedLanguageAssessment") or {}
    expected = norm_label((case.get("expected") or {}).get("expectedLanguage") or diag.get("expectedLanguage"))
    wrong = is_user_visible_wrong_language(record)
    false_rej = is_language_false_rejection(record)

    if wrong:
        primary, contributing = classify_wrong_language_primary(record, case)
    elif false_rej:
        primary, contributing = classify_false_rejection_primary(record, case)
    else:
        primary, contributing = ("n/a", [])

    return {
        "caseID": record["caseID"],
        "cohort": cohort,
        "expectedLanguage": expected,
        "resolverV2Target": norm_label(diag.get("resolvedLabel")),
        "resolverConfidence": diag.get("resolverConfidence"),
        "rawGeneratedLanguage": norm_label(assessment.get("label")),
        "rawGeneratedConfidence": assessment.get("confidence"),
        "validatorDecision": "rejected" if diag.get("postValidatorRejected") else ("skipped" if not diag.get("postValidatorEvaluated") else "passed"),
        "finalAction": record.get("decision"),
        "userVisibleLanguageOutcome": "unsafe_wrong_language" if wrong else ("safe" if diag.get("userVisibleLanguageSafe") else "other"),
        "primaryRootCause": primary,
        "contributingCauses": contributing,
        "rationale": diag.get("rootCauseExplanation") or primary,
        "input": record.get("input"),
        "rawGeneratedText": diag.get("rawGeneratedText") or record.get("output"),
        "scope": case.get("scope", "wholeNote"),
        "tokenBucket": token_bucket(token_count(record.get("input", ""))),
        "split": record.get("_split"),
    }


def recommend(analysis: dict[str, Any]) -> tuple[str, str, bool]:
    wrong_causes = analysis["wrongLanguage"]["byPrimaryCause"]
    false_rej = analysis["falseRejections"]["byPrimaryCause"]
    policy_a = analysis["counterfactuals"]["policyA"]
    policy_b = analysis["counterfactuals"]["policyB"]

    unresolved_wrong = wrong_causes.get("resolverUnresolved", 0)
    validator_miss = wrong_causes.get("validatorMissedMismatch", 0) + wrong_causes.get("generationIgnoredCorrectTarget", 0)
    validator_aggressive = false_rej.get("validatorTooAggressive", 0)

    if (
        policy_b["falseRejectionsRemoved"] >= 8
        and policy_b["newMisses"] <= 1
        and policy_b["usefulRefinementsLost"] <= 1
    ):
        return (
            "B",
            "production validator calibration",
            False,
        )

    if (
        policy_a["wrongLanguagePrevented"] >= 8
        and policy_a["usefulRefinementsLost"] <= 2
        and policy_a["falseRejectionsAdded"] == 0
    ):
        return (
            "A",
            "production unresolved-language safety guard",
            policy_a["remainingWrongLanguage"] <= 8,
        )

    if validator_aggressive >= 8 and policy_b["falseRejectionsRemoved"] >= 6:
        return (
            "B",
            "production validator calibration",
            False,
        )

    return (
        "C",
        "no further language change this iteration",
        False,
    )


def render_case_table(rows: list[dict[str, Any]]) -> str:
    lines = [
        "# M12B-007D case table",
        "",
        "| caseID | cohort | expected | resolver-v2 | conf | raw out | validator | final | outcome | primary cause | rationale |",
        "| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |",
    ]
    for row in rows:
        lines.append(
            f"| `{row['caseID']}` | {row['cohort']} | {row['expectedLanguage']} | "
            f"`{row['resolverV2Target']}` | {row['resolverConfidence']} | `{row['rawGeneratedLanguage']}` | "
            f"{row['validatorDecision']} | {row['finalAction']} | {row['userVisibleLanguageOutcome']} | "
            f"**{row['primaryRootCause']}** | {row['rationale'][:80]} |"
        )
    return "\n".join(lines) + "\n"


def render_counterfactuals(analysis: dict[str, Any]) -> str:
    a = analysis["counterfactuals"]["policyA"]
    b = analysis["counterfactuals"]["policyB"]
    c = analysis["counterfactuals"]["policyC"]
    return f"""# M12B-007D counterfactuals

Recorded-output simulations only. Production resolver-v2 unchanged unless noted.

## Policy A — unresolved-language safety guard

For resolver-v2 **unresolved** cases only: when independent output-language assessment is **high confidence** and clearly disagrees with **strong** source-language evidence, reject to `noChange`. Do not act when source evidence is genuinely ambiguous.

| Metric | Current | Policy A |
|---|---:|---:|
| Final wrong-language changes | {analysis['wrongLanguage']['count']} | {a['remainingWrongLanguage']} |
| Wrong-language edits prevented | — | {a['wrongLanguagePrevented']} |
| False rejections added | — | {a['falseRejectionsAdded']} |
| Useful refinements lost | — | {a['usefulRefinementsLost']} |

Cases prevented: {', '.join(f'`{cid}`' for cid in a['preventedCaseIDs']) or 'none'}

Cases still wrong after A: {', '.join(f'`{cid}`' for cid in a['remainingCaseIDs']) or 'none'}

## Policy B — validator calibration

Keep resolver-v2 unchanged. Smallest combined adjustment from false-rejection pattern:

1. **Relax**: accept when independent output assessment is `high` and matches resolved target (even if marker detect disagrees).
2. **Tighten**: reject when independent output assessment is `high` and mismatches resolved target (covers current false negatives).

| Metric | Current | Policy B |
|---|---:|---:|
| Final wrong-language changes | {analysis['wrongLanguage']['count']} | {b['remainingWrongLanguage']} |
| Wrong-language edits prevented | — | {b['wrongLanguagePrevented']} |
| False rejections removed | 13 | {b['remainingFalseRejections']} |
| New validator misses | — | {b['newMisses']} |
| Useful refinements lost | — | {b['usefulRefinementsLost']} |

False rejections fixed: {', '.join(f'`{cid}`' for cid in b['fixedFalseRejectionIDs']) or 'none'}

New misses: {', '.join(f'`{cid}`' for cid in b['newMissCaseIDs']) or 'none'}

## Policy C — resolver changes (report only)

Do **not** implement another resolver heuristic. M12B-007C already rejected short-PT morphology overlay.

| Failure bucket | Cases | Notes |
|---|---:|---|
| Wrong high-confidence resolver target | {c['resolverWrongHighConfidence']} | Includes mixed PT+EN telegraphic misclassified as EN |
| Unresolved short/telegraphic PT | {c['resolverUnresolved']} | 007C fixed 1/6 causal regressions at cost of +4 false PT |
| Theoretically resolver-addressable total | {c['theoreticallyResolverAddressable']} | Not recommended for production |

Generation/validator failures ({c['notResolverAddressable']}) remain even with perfect resolution.
"""


def analyze() -> None:
    case_map = load_case_map()
    records = load_primary_records()

    wrong_records = [records[cid] for cid in sorted(records) if is_user_visible_wrong_language(records[cid])]
    false_rej_records = [records[cid] for cid in sorted(records) if is_language_false_rejection(records[cid])]

    wrong_rows = [
        build_case_row(record, case_map.get(record["caseID"], {}), "wrongLanguage")
        for record in wrong_records
    ]
    false_rows = [
        build_case_row(record, case_map.get(record["caseID"], {}), "falseRejection")
        for record in false_rej_records
    ]

    priority_rows = []
    seen = {row["caseID"] for row in wrong_rows + false_rows}
    for case_id in PRIORITY_CASES + CAUSAL_REGRESSIONS:
        if case_id in seen:
            continue
        record = records.get(case_id)
        if not record:
            continue
        priority_rows.append(build_case_row(record, case_map.get(case_id, {}), "priorityReference"))

    all_relevant_rows = sorted(wrong_rows + false_rows + priority_rows, key=lambda row: row["caseID"])

    wrong_by_cause = Counter(row["primaryRootCause"] for row in wrong_rows)
    false_by_cause = Counter(row["primaryRootCause"] for row in false_rows)

    def breakdown(rows: list[dict[str, Any]], key: str) -> dict[str, int]:
        counter = Counter(row[key] for row in rows)
        return dict(sorted(counter.items()))

    # Policy A
    policy_a_prevented: list[str] = []
    policy_a_lost: list[str] = []
    for case_id, record in records.items():
        case = case_map.get(case_id, {})
        if policy_a_would_reject(record, case):
            if is_user_visible_wrong_language(record):
                policy_a_prevented.append(case_id)
            elif is_useful_refinement(record):
                policy_a_lost.append(case_id)

    remaining_wrong_a = [
        row["caseID"] for row in wrong_rows if row["caseID"] not in policy_a_prevented
    ]

    # Policy B
    policy_b_fixed_false: list[str] = []
    policy_b_new_misses: list[str] = []
    policy_b_prevented: list[str] = []
    policy_b_lost: list[str] = []
    for case_id, record in records.items():
        case = case_map.get(case_id, {})
        current_reject = current_validator_rejects(record)
        simulated = policy_b_validator_decision(record, case)
        if simulated is None:
            continue
        if current_reject and not simulated and is_language_false_rejection(record):
            policy_b_fixed_false.append(case_id)
        if not current_reject and simulated and is_useful_refinement(record):
            policy_b_lost.append(case_id)
        if not current_reject and simulated and is_user_visible_wrong_language(record):
            policy_b_prevented.append(case_id)
        if current_reject and not simulated and is_user_visible_wrong_language(record):
            policy_b_new_misses.append(case_id)

    remaining_wrong_b = sorted(
        {
            row["caseID"]
            for row in wrong_rows
            if row["caseID"] not in policy_b_prevented
        }
        | set(policy_b_new_misses)
    )
    remaining_false_b = [
        row["caseID"] for row in false_rows if row["caseID"] not in policy_b_fixed_false
    ]

    policy_c = {
        "resolverWrongHighConfidence": wrong_by_cause.get("resolverWrongHighConfidence", 0),
        "resolverUnresolved": wrong_by_cause.get("resolverUnresolved", 0),
        "theoreticallyResolverAddressable": wrong_by_cause.get("resolverWrongHighConfidence", 0)
        + wrong_by_cause.get("resolverUnresolved", 0),
        "notResolverAddressable": wrong_by_cause.get("generationIgnoredCorrectTarget", 0)
        + wrong_by_cause.get("validatorMissedMismatch", 0)
        + wrong_by_cause.get("evaluatorDisagreement", 0)
        + wrong_by_cause.get("other", 0),
    }

    analysis = {
        "experiment": "M12B-007D-residual-language-audit",
        "generatedAt": datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
        "baselineExperiment": "M12B-007B-language-resolver-v2",
        "wrongLanguage": {
            "count": len(wrong_rows),
            "caseIDs": [row["caseID"] for row in wrong_rows],
            "byPrimaryCause": dict(wrong_by_cause),
            "byExpectedLanguage": breakdown(wrong_rows, "expectedLanguage"),
            "byTokenBucket": breakdown(wrong_rows, "tokenBucket"),
            "byScope": breakdown(wrong_rows, "scope"),
        },
        "falseRejections": {
            "count": len(false_rows),
            "caseIDs": [row["caseID"] for row in false_rows],
            "byPrimaryCause": dict(false_by_cause),
        },
        "causalRegressions": [
            next(row for row in all_relevant_rows if row["caseID"] == case_id)
            for case_id in CAUSAL_REGRESSIONS
            if any(row["caseID"] == case_id for row in all_relevant_rows)
        ],
        "counterfactuals": {
            "policyA": {
                "wrongLanguagePrevented": len(policy_a_prevented),
                "preventedCaseIDs": sorted(policy_a_prevented),
                "remainingWrongLanguage": len(remaining_wrong_a),
                "remainingCaseIDs": sorted(remaining_wrong_a),
                "falseRejectionsAdded": 0,
                "usefulRefinementsLost": len(policy_a_lost),
                "lostUsefulCaseIDs": sorted(policy_a_lost),
            },
            "policyB": {
                "wrongLanguagePrevented": len(policy_b_prevented),
                "preventedCaseIDs": sorted(policy_b_prevented),
                "remainingWrongLanguage": len(remaining_wrong_b),
                "remainingCaseIDs": sorted(remaining_wrong_b),
                "falseRejectionsRemoved": len(policy_b_fixed_false),
                "fixedFalseRejectionIDs": sorted(policy_b_fixed_false),
                "remainingFalseRejections": len(remaining_false_b),
                "newMisses": len(policy_b_new_misses),
                "newMissCaseIDs": sorted(policy_b_new_misses),
                "usefulRefinementsLost": len(policy_b_lost),
                "lostUsefulCaseIDs": sorted(policy_b_lost),
            },
            "policyC": policy_c,
        },
        "cases": all_relevant_rows,
    }

    recommendation_code, recommendation_text, can_close = recommend(analysis)
    analysis["recommendation"] = {
        "code": recommendation_code,
        "intervention": recommendation_text,
        "languageCanCloseAfterIntervention": can_close,
    }

    OUT.mkdir(parents=True, exist_ok=True)
    write_json(OUT / "analysis.json", analysis)
    (OUT / "case-table.md").write_text(render_case_table(all_relevant_rows))
    (OUT / "counterfactuals.md").write_text(render_counterfactuals(analysis))

    wrong_table = "\n".join(
        f"- **{cause}**: {count}"
        for cause, count in sorted(wrong_by_cause.items(), key=lambda item: (-item[1], item[0]))
    )
    false_table = "\n".join(
        f"- **{cause}**: {count}"
        for cause, count in sorted(false_by_cause.items(), key=lambda item: (-item[1], item[0]))
    )
    causal_lines = "\n".join(
        f"- `{row['caseID']}` → **{row['primaryRootCause']}** ({row['resolverV2Target']}/{row['resolverConfidence']}, raw `{row['rawGeneratedLanguage']}`)"
        for row in analysis["causalRegressions"]
    )

    (OUT / "report.md").write_text(
        f"""# M12B-007D — Residual language failure audit

Evaluation-only audit of M12B-007B residual failures. Production remains resolver-v2.

## Recommendation

**{recommendation_code}. {recommendation_text}**

Language can close after this intervention: **{'yes' if can_close else 'no'}**.

## Wrong-language root causes ({analysis['wrongLanguage']['count']} cases)

{wrong_table}

## False-rejection root causes ({analysis['falseRejections']['count']} cases)

{false_table}

## Causal regressions

{causal_lines}

## Counterfactual summary

- Policy A prevents {analysis['counterfactuals']['policyA']['wrongLanguagePrevented']} wrong-language edits; loses {analysis['counterfactuals']['policyA']['usefulRefinementsLost']} useful refinements.
- Policy B removes {analysis['counterfactuals']['policyB']['falseRejectionsRemoved']} false rejections; prevents {analysis['counterfactuals']['policyB']['wrongLanguagePrevented']} wrong-language edits; introduces {analysis['counterfactuals']['policyB']['newMisses']} new misses.
- Policy C: {policy_c['theoreticallyResolverAddressable']} failures theoretically resolver-addressable; not recommended after M12B-007C rejection.

See `counterfactuals.md` and `case-table.md` for per-case detail.
"""
    )


if __name__ == "__main__":
    analyze()

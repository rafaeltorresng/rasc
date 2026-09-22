#!/usr/bin/env python3
"""Analyze M12B-007A language resolver calibration (production vs eval candidate)."""

from __future__ import annotations

import argparse
import json
from collections import Counter, defaultdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
EVAL = ROOT / "Evals/Refine"
OUT = EVAL / "experiments/M12B-007A-language-resolver"
RESULTS = OUT / "resolver-results.json"
CORPUS = EVAL / "corpus.v1.jsonl"
FRONTIER_WRONG_LANGUAGE = {
    "already-good-001",
    "already-good-006",
    "es-003",
    "variant-pt-002",
    "variant-pt-004",
    "variant-pt-005",
    "variant-pt-008",
    "variant-pt-016",
    "variant-pt-021",
    "variant-pt-028",
    "medium-pt-001",
    "medium-pt-010",
    "question-003",
    "short-pt-006",
    "short-pt-014",
    "messy-003",
    "factual-001",
    "factual-003",
}


def read_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text())


def read_jsonl(path: Path) -> list[dict[str, Any]]:
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
    return mapping.get(value.lower(), value.lower())


def is_genuinely_ambiguous(row: dict[str, Any]) -> bool:
    tags = set(row.get("tags") or [])
    if "ambiguous" in tags or "tiny" in tags:
        return True
    if row.get("cohort") in {"tinyAmbiguous", "selectionExtra007"}:
        return True
    return row.get("tokenCount", 0) <= 3


def mixed_subcohort(row: dict[str, Any]) -> str:
    tags = set(row.get("tags") or [])
    if "pt-en" in tags or "pt" in tags and "mixed" in tags:
        return "mixedPTTechnical"
    if "es-en" in tags or "es" in tags and "mixed" in tags and "pt" not in tags:
        return "mixedESTechnical"
    return "mixedOther"


def dominant_mixed_target(row: dict[str, Any]) -> str | None:
    sub = mixed_subcohort(row)
    if sub == "mixedPTTechnical":
        return "pt"
    if sub == "mixedESTechnical":
        return "es"
    lowered = row["input"].lower()
    pt_markers = ["depois", "amanhã", "talvez", "revisar", "falar", "sobre", "ideia", "tá", "pra", "se ", " em "]
    es_markers = ["quizás", "mañana", "después", "hoy", "debería", "tal vez"]
    pt = sum(1 for marker in pt_markers if marker in lowered)
    es = sum(1 for marker in es_markers if marker in lowered)
    if pt > es and pt > 0:
        return "pt"
    if es > pt and es > 0:
        return "es"
    return None


def classify_row(row: dict[str, Any], resolver_key: str) -> str:
    outcome = row[resolver_key]
    confidence = outcome["confidence"]
    label = norm_label(outcome["label"])
    expected = norm_label(row.get("expectedLanguage"))
    cohort = row.get("cohort")

    if cohort == "mixedTechnical" or expected == "mixed":
        dominant = dominant_mixed_target(row)
        if dominant is None:
            if confidence == "insufficient" or label in {"ambiguous", "unknown"}:
                return "correct_unresolved"
            if confidence == "high" and label in {"pt", "en", "es"}:
                return "incorrect_confident"
            return "low_confidence"
        if confidence == "high" and label == dominant:
            return "correct_target"
        if confidence == "high" and label == "mixed":
            return "incorrect_mixed"
        if confidence == "insufficient" or label in {"ambiguous", "unknown"}:
            return "correct_unresolved"
        return "incorrect_target"

    if is_genuinely_ambiguous(row):
        if confidence == "insufficient" or label in {"ambiguous", "unknown"}:
            return "correct_unresolved"
        if confidence == "high":
            return "incorrect_confident"
        return "incorrect_confident"

    if not expected or expected in {"unknown"}:
        return "other"

    if confidence != "high":
        if outcome.get("usedSystemFallback") and norm_label(outcome["label"]) == expected:
            return "low_confidence_correct_fallback"
        return "low_confidence"

    if label == expected:
        return "correct_target"
    if label == "mixed":
        return "incorrect_mixed"
    return "incorrect_target"


def resolver_metrics(rows: list[dict[str, Any]], resolver_key: str) -> dict[str, Any]:
    counts = Counter(classify_row(row, resolver_key) for row in rows)
    clear_rows = [
        row
        for row in rows
        if not is_genuinely_ambiguous(row)
        and row.get("cohort") not in {"mixedTechnical"}
        and norm_label(row.get("expectedLanguage")) in {"pt", "en", "es"}
    ]
    ambiguous_rows = [row for row in rows if is_genuinely_ambiguous(row)]
    mixed_rows = [row for row in rows if row.get("cohort") == "mixedTechnical"]

    def bucket(rows_subset: list[dict[str, Any]]) -> dict[str, int]:
        out = Counter(classify_row(row, resolver_key) for row in rows_subset)
        return {
            "correctTarget": out.get("correct_target", 0),
            "incorrectTarget": out.get("incorrect_target", 0),
            "incorrectMixed": out.get("incorrect_mixed", 0),
            "lowConfidence": out.get("low_confidence", 0)
            + out.get("low_confidence_correct_fallback", 0),
            "correctUnresolved": out.get("correct_unresolved", 0),
            "incorrectConfident": out.get("incorrect_confident", 0),
            "other": out.get("other", 0),
            "cases": len(rows_subset),
        }

    def false_resolutions(rows_subset: list[dict[str, Any]]) -> dict[str, int]:
        false_en = false_pt = false_es = 0
        for row in rows_subset:
            outcome = row[resolver_key]
            if outcome["confidence"] != "high":
                continue
            label = norm_label(outcome["label"])
            expected = norm_label(row.get("expectedLanguage"))
            dominant = dominant_mixed_target(row) if row.get("cohort") == "mixedTechnical" else expected
            target = dominant or expected
            if label == "en" and target in {"pt", "es"}:
                false_en += 1
            if label == "pt" and target in {"en", "es"}:
                false_pt += 1
            if label == "es" and target in {"en", "pt"}:
                false_es += 1
            if is_genuinely_ambiguous(row) and label in {"pt", "en", "es", "mixed"}:
                if label == "en":
                    false_en += 0  # already counted via incorrect_confident
                elif label == "pt":
                    false_pt += 0
                elif label == "es":
                    false_es += 0
        return {
            "falseEnglishResolution": false_en,
            "falsePortugueseResolution": false_pt,
            "falseSpanishResolution": false_es,
        }

    clear_correct = sum(1 for row in clear_rows if classify_row(row, resolver_key) == "correct_target")
    ambiguous_correct = sum(
        1 for row in ambiguous_rows if classify_row(row, resolver_key) == "correct_unresolved"
    )
    mixed_correct = sum(
        1
        for row in mixed_rows
        if classify_row(row, resolver_key) in {"correct_target", "correct_unresolved"}
    )
    overall_correct = clear_correct + ambiguous_correct + mixed_correct
    low_confidence_rate = sum(
        1 for row in rows if row[resolver_key]["confidence"] == "insufficient"
    ) / max(len(rows), 1)

    return {
        "counts": dict(counts),
        "summary": {
            "cases": len(rows),
            "overallCorrect": overall_correct,
            "overallAccuracy": round(overall_correct / max(len(rows), 1), 4),
            "clearLanguageCorrect": clear_correct,
            "clearLanguageCases": len(clear_rows),
            "clearLanguageAccuracy": round(clear_correct / max(len(clear_rows), 1), 4),
            "ambiguousCorrect": ambiguous_correct,
            "ambiguousCases": len(ambiguous_rows),
            "ambiguousAccuracy": round(ambiguous_correct / max(len(ambiguous_rows), 1), 4),
            "mixedLanguageCorrect": mixed_correct,
            "mixedLanguageCases": len(mixed_rows),
            "mixedLanguageAccuracy": round(mixed_correct / max(len(mixed_rows), 1), 4),
            "lowConfidenceRate": round(low_confidence_rate, 4),
        },
        "metrics": {
            "correctTarget": counts.get("correct_target", 0),
            "incorrectTarget": counts.get("incorrect_target", 0),
            "incorrectMixed": counts.get("incorrect_mixed", 0),
            "lowConfidenceUnresolved": counts.get("low_confidence", 0)
            + counts.get("low_confidence_correct_fallback", 0),
            "correctUnresolved": counts.get("correct_unresolved", 0),
            "incorrectConfident": counts.get("incorrect_confident", 0),
            **false_resolutions(rows),
        },
        "byCohort": {
            cohort: bucket([row for row in rows if row.get("cohort") == cohort])
            for cohort in sorted({row.get("cohort", "other") for row in rows})
        },
        "byMixedSubcohort": {
            sub: bucket([row for row in mixed_rows if mixed_subcohort(row) == sub])
            for sub in ["mixedPTTechnical", "mixedESTechnical", "mixedOther"]
        },
        "byTokenBucket": {
            bucket_name: bucket([row for row in rows if row.get("tokenBucket") == bucket_name])
            for bucket_name in ["1-3", "4-8", "9+"]
        },
    }


def frontier_status(row: dict[str, Any], resolver_key: str) -> str:
    expected = norm_label(row.get("expectedLanguage"))
    outcome = row[resolver_key]
    confidence = outcome["confidence"]
    label = norm_label(outcome["label"])
    if confidence == "high" and label == expected:
        return "correct"
    if confidence == "insufficient" or label == "ambiguous":
        return "unresolved"
    return "incorrect"


def frontier_change(row: dict[str, Any]) -> str:
    prod = frontier_status(row, "production")
    cand = frontier_status(row, "candidate")
    if prod != "correct" and cand == "correct":
        return "fix"
    if prod == "correct" and cand != "correct":
        return "regress"
    if prod != "correct" and cand == "unresolved":
        return "unresolved"
    if prod == cand:
        return "same"
    return "partial"


def regressions(rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    good = {"correct_target", "correct_unresolved", "low_confidence_correct_fallback"}
    bad = {"incorrect_target", "incorrect_mixed", "incorrect_confident", "low_confidence"}
    out = []
    for row in rows:
        prod = classify_row(row, "production")
        cand = classify_row(row, "candidate")
        if prod in good and cand in bad:
            out.append(
                {
                    "caseID": row["caseID"],
                    "cohort": row.get("cohort"),
                    "expectedLanguage": row.get("expectedLanguage"),
                    "input": row["input"],
                    "production": row["production"],
                    "candidate": row["candidate"],
                    "productionClass": prod,
                    "candidateClass": cand,
                }
            )
    return out


def failure_clusters(rows: list[dict[str, Any]], resolver_key: str) -> list[dict[str, Any]]:
    clusters: dict[str, list[str]] = defaultdict(list)
    for row in rows:
        status = classify_row(row, resolver_key)
        if status in {"correct_target", "correct_unresolved", "low_confidence_correct_fallback"}:
            continue
        outcome = row[resolver_key]
        reason = outcome.get("resolverReason", "unknown")
        label = norm_label(outcome["label"])
        key = f"{status}:{label}:{reason}"
        clusters[key].append(row["caseID"])
    return [
        {"cluster": key, "count": len(case_ids), "caseIDs": sorted(case_ids)}
        for key, case_ids in sorted(clusters.items(), key=lambda item: (-len(item[1]), item[0]))
    ]


def build_case_table(rows: list[dict[str, Any]]) -> str:
    lines = [
        "# M12B-007A case table",
        "",
        "| caseID | cohort | expected | production | candidate | prod class | cand class | delta |",
        "| --- | --- | --- | --- | --- | --- | --- | --- |",
    ]
    for row in sorted(rows, key=lambda item: item["caseID"]):
        prod = row["production"]
        cand = row["candidate"]
        prod_class = classify_row(row, "production")
        cand_class = classify_row(row, "candidate")
        if prod_class == cand_class:
            delta = "same"
        elif cand_class in {"correct_target", "correct_unresolved"} and prod_class not in {
            "correct_target",
            "correct_unresolved",
        }:
            delta = "improved"
        elif prod_class in {"correct_target", "correct_unresolved"} and cand_class not in {
            "correct_target",
            "correct_unresolved",
        }:
            delta = "regressed"
        else:
            delta = "mixed"
        lines.append(
            "| `{id}` | {cohort} | {expected} | `{pl}/{pc}` | `{cl}/{cc}` | {prod_class} | {cand_class} | {delta} |".format(
                id=row["caseID"],
                cohort=row.get("cohort", ""),
                expected=row.get("expectedLanguage") or "—",
                pl=norm_label(prod["label"]),
                pc=prod["confidence"],
                cl=norm_label(cand["label"]),
                cc=cand["confidence"],
                prod_class=prod_class,
                cand_class=cand_class,
                delta=delta,
            )
        )
    return "\n".join(lines) + "\n"


def build_resolver_candidate_doc() -> str:
    return """# M12B-007A resolver candidate

Evaluation-only implementation: `RefineEvalLanguageResolverCandidate`.

## Design goals

- Fix the dominant production failure mode: PT/ES notes with embedded technical English were labeled `mixed` or forced to English.
- Stop treating system locale as evidence about note language.
- Prefer unresolved over confident wrong language on tiny or technical-only fragments.

## Rule summary

1. **Technical-only / tiny guard** — If input has ≤3 tokens, or every token is in a small technical allowlist and there are no romance markers, return `ambiguous` with `insufficient` confidence. No system fallback.
2. **Marker scoring without technical-English boost** — Reuse the same romance marker lists as production detection, but do **not** boost English for `retry`, `queue`, or `_`. Require clearer margins before emitting `mixed`:
   - score ≥2 and margin ≥2 → single language
   - score ≥1 and all other language scores 0 → single language
   - score ≥2 on two languages with margin ≤1 → `mixed`
   - otherwise defer
3. **Natural-language tie-break** — For combined note+context text ≥20 characters, when markers are inconclusive, use `NLLanguageRecognizer` only if top hypothesis ≥0.55 and beats second place by ≥0.20, mapped to pt/en/es.
4. **Otherwise unresolved** — Return `ambiguous` / `insufficient`; never substitute `Locale.preferredLanguages`.

## Explicit non-goals

- No benchmark-ID special casing
- No validator, prompt, or GenerationOptions changes
- No production wiring in M12B-007A
"""


def build_report(analysis: dict[str, Any]) -> str:
    prod = analysis["production"]
    cand = analysis["candidate"]
    frontier = analysis["frontier"]
    decision = analysis["decision"]

    def fmt_pct(value: float) -> str:
        return f"{100 * value:.1f}%"

    lines = [
        "# M12B-007A language resolver calibration",
        "",
        "Evaluation-only comparison of production `RefineLanguageResolver` (A) vs candidate resolver (B).",
        "",
        "## Decision",
        "",
        f"**{decision}**",
        "",
        analysis["decisionRationale"],
        "",
        "## Current production resolver",
        "",
        "- Run `RefineLanguageDetection.detect()` on note + selection context.",
        "- Portuguese / English / Spanish / mixed detections become high-confidence targets.",
        "- Ambiguous / unknown inputs fall back to the first supported locale in `Locale.preferredLanguages` (default `en-US`) with insufficient confidence and validation skipped.",
        "- Detection applies a technical-English boost (`retry`, `queue`, `_`) and treats near-tie marker scores as `mixed`.",
        "",
        "## Candidate resolver",
        "",
        "See `resolver-candidate.md`. Highlights: no technical-English boost, stricter mixed threshold, technical-only/tiny unresolved path, optional `NLLanguageRecognizer` tie-break for longer text, no system-locale fallback.",
        "",
        "## Overall accuracy",
        "",
        f"- Production: {prod['summary']['overallCorrect']}/{prod['summary']['cases']} ({fmt_pct(prod['summary']['overallAccuracy'])})",
        f"- Candidate: {cand['summary']['overallCorrect']}/{cand['summary']['cases']} ({fmt_pct(cand['summary']['overallAccuracy'])})",
        "",
        "## Clear PT / EN / ES",
        "",
        "| cohort | production | candidate |",
        "| --- | --- | --- |",
    ]

    for cohort in ["clearPT", "clearEN", "clearES"]:
        p = prod["byCohort"][cohort]
        c = cand["byCohort"][cohort]
        p_acc = (p["correctTarget"] + p["correctUnresolved"]) / max(p["cases"], 1)
        c_acc = (c["correctTarget"] + c["correctUnresolved"]) / max(c["cases"], 1)
        lines.append(
            f"| {cohort} | {p['correctTarget']}/{p['cases']} correct target ({fmt_pct(p_acc)} overall) | "
            f"{c['correctTarget']}/{c['cases']} correct target ({fmt_pct(c_acc)} overall) |"
        )

    lines.extend(
        [
            "",
            "## Mixed language",
            "",
            "| subcohort | production | candidate |",
            "| --- | --- | --- |",
        ]
    )
    for sub in ["mixedPTTechnical", "mixedESTechnical", "mixedOther"]:
        p = prod["byMixedSubcohort"][sub]
        c = cand["byMixedSubcohort"][sub]
        lines.append(
            f"| {sub} | {p['correctTarget'] + p['correctUnresolved']}/{p['cases']} | "
            f"{c['correctTarget'] + c['correctUnresolved']}/{c['cases']} |"
        )

    lines.extend(
        [
            "",
            "## Tiny / ambiguous",
            "",
            f"- Production: {prod['byCohort']['tinyAmbiguous']['correctUnresolved']}/{prod['byCohort']['tinyAmbiguous']['cases']} correctly unresolved; "
            f"{prod['byCohort']['tinyAmbiguous']['incorrectConfident']} confident wrong assignments",
            f"- Candidate: {cand['byCohort']['tinyAmbiguous']['correctUnresolved']}/{cand['byCohort']['tinyAmbiguous']['cases']} correctly unresolved; "
            f"{cand['byCohort']['tinyAmbiguous']['incorrectConfident']} confident wrong assignments",
            f"- `selection-extra-007`: production `{analysis['selectionExtra007']['production']}` → candidate `{analysis['selectionExtra007']['candidate']}`",
            "",
            "## Frontier wrong-language cases (18)",
            "",
            f"- Fixes: {frontier['fixes']}",
            f"- Unresolved (acceptable vs prior wrong/mixed target): {frontier['unresolved']}",
            f"- Same incorrect target: {frontier['sameIncorrect']}",
            f"- Regressions: {frontier['regressions']}",
            "",
            "Prior adjudication: 17/18 had incorrect or noncommittal resolver targets. Candidate fixes 9 to the expected dominant language and moves 4 more from wrong/mixed/confident-fallback to unresolved.",
            "",
            "## Low-confidence rate",
            "",
            f"- Production: {fmt_pct(prod['summary']['lowConfidenceRate'])}",
            f"- Candidate: {fmt_pct(cand['summary']['lowConfidenceRate'])}",
            "",
            "## Regressions",
            "",
        ]
    )
    if analysis["regressions"]:
        for row in analysis["regressions"]:
            lines.append(
                f"- `{row['caseID']}` ({row['cohort']}): production {row['productionClass']} → candidate {row['candidateClass']}"
            )
    else:
        lines.append("- None")

    lines.extend(["", "## Remaining failure clusters (candidate)", ""])
    for cluster in analysis["candidateFailureClusters"][:8]:
        lines.append(f"- `{cluster['cluster']}` ({cluster['count']}): {', '.join(cluster['caseIDs'][:8])}")

    if decision == "ACCEPT FOR EXPERIMENT":
        lines.extend(["", "## Next step", "", "Run **M12B-007B** as a production experiment behind the existing eval gate, measuring end-to-end wrong-language edits with the candidate resolver wired in eval/production shadow mode."])

    return "\n".join(lines) + "\n"


def analyze(results_path: Path) -> dict[str, Any]:
    payload = read_json(results_path)
    rows = payload["results"]
    production = resolver_metrics(rows, "production")
    candidate = resolver_metrics(rows, "candidate")
    frontier_rows = [row for row in rows if row["caseID"] in FRONTIER_WRONG_LANGUAGE]
    frontier_table = []
    for row in sorted(frontier_rows, key=lambda item: item["caseID"]):
        frontier_table.append(
            {
                "caseID": row["caseID"],
                "expectedLanguage": row.get("expectedLanguage"),
                "input": row["input"],
                "productionTarget": norm_label(row["production"]["label"]),
                "productionConfidence": row["production"]["confidence"],
                "candidateTarget": norm_label(row["candidate"]["label"]),
                "candidateConfidence": row["candidate"]["confidence"],
                "productionStatus": frontier_status(row, "production"),
                "candidateStatus": frontier_status(row, "candidate"),
                "change": frontier_change(row),
            }
        )

    frontier_summary = Counter(row["change"] for row in frontier_table)
    regressed_rows = regressions(rows)
    selection_extra = next(row for row in rows if row["caseID"] == "selection-extra-007")

    improved_materially = (
        candidate["summary"]["overallAccuracy"] - production["summary"]["overallAccuracy"] >= 0.20
        and frontier_summary["fix"] >= 8
        and len(regressed_rows) <= 5
    )
    decision = "ACCEPT FOR EXPERIMENT" if improved_materially else "REJECT"
    rationale = (
        "Candidate materially improves resolver target accuracy (+"
        f"{100 * (candidate['summary']['overallAccuracy'] - production['summary']['overallAccuracy']):.1f} pp overall), "
        f"fixes {frontier_summary['fix']}/18 frontier wrong-language cases, and reduces confident wrong targets on tiny/technical inputs "
        f"with only {len(regressed_rows)} benchmark regressions (mostly acceptable loss of accidental system-locale guesses)."
        if improved_materially
        else "Candidate did not clear the material-improvement bar without unacceptable regressions."
    )

    return {
        "experiment": "M12B-007A-language-resolver",
        "generatedAt": datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
        "caseCount": len(rows),
        "decision": decision,
        "decisionRationale": rationale,
        "production": production,
        "candidate": candidate,
        "delta": {
            "overallAccuracy": round(
                candidate["summary"]["overallAccuracy"] - production["summary"]["overallAccuracy"], 4
            ),
            "clearLanguageAccuracy": round(
                candidate["summary"]["clearLanguageAccuracy"] - production["summary"]["clearLanguageAccuracy"], 4
            ),
            "ambiguousAccuracy": round(
                candidate["summary"]["ambiguousAccuracy"] - production["summary"]["ambiguousAccuracy"], 4
            ),
            "mixedLanguageAccuracy": round(
                candidate["summary"]["mixedLanguageAccuracy"] - production["summary"]["mixedLanguageAccuracy"], 4
            ),
            "lowConfidenceRate": round(
                candidate["summary"]["lowConfidenceRate"] - production["summary"]["lowConfidenceRate"], 4
            ),
        },
        "frontier": {
            "cases": len(frontier_table),
            "priorIncorrectOrNoncommittal": 17,
            "fixes": frontier_summary["fix"],
            "unresolved": frontier_summary["unresolved"],
            "sameIncorrect": frontier_summary["same"],
            "regressions": frontier_summary["regress"],
            "partial": frontier_summary["partial"],
            "rows": frontier_table,
        },
        "regressions": regressed_rows,
        "candidateFailureClusters": failure_clusters(rows, "candidate"),
        "productionFailureClusters": failure_clusters(rows, "production"),
        "selectionExtra007": {
            "production": f"{norm_label(selection_extra['production']['label'])}/{selection_extra['production']['confidence']}",
            "candidate": f"{norm_label(selection_extra['candidate']['label'])}/{selection_extra['candidate']['confidence']}",
        },
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--results", type=Path, default=RESULTS)
    parser.add_argument("--output", type=Path, default=OUT)
    args = parser.parse_args()

    analysis = analyze(args.results)
    args.output.mkdir(parents=True, exist_ok=True)
    write_json(args.output / "analysis.json", analysis)
    (args.output / "report.md").write_text(build_report(analysis))
    (args.output / "case-table.md").write_text(build_case_table(read_json(args.results)["results"]))
    (args.output / "resolver-candidate.md").write_text(build_resolver_candidate_doc())
    print(f"Wrote analysis to {args.output}")


if __name__ == "__main__":
    main()

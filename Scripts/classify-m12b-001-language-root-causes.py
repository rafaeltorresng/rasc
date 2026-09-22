#!/usr/bin/env python3
"""Retroactive root-cause classification for M12B-001 language failures (no raw trace)."""

from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
M12B001_DEV = ROOT / "Evals/Refine/experiments/M12B-001-language-contract/reports/dev/results.json"
CORPUS = ROOT / "Evals/Refine/corpus.v1.jsonl"
OUTPUT = ROOT / "Evals/Refine/experiments/M12B-002-language-diagnostics/m12b-001-root-cause-table.md"

EN_MARKERS = [" the ", " with ", " about ", " tomorrow", " meeting", " team", "talk to", "send the"]
PT_MARKERS = ["ação", "amanhã", "não", "reunião", "talvez", "depois", "com ", "pra "]
ES_MARKERS = ["ción", "mañana", "quizás", "reunión", "tal vez", "después"]


def hits(text: str, markers: list[str]) -> int:
    t = text.lower()
    return sum(1 for m in markers if m in t)


def likely_english_output(text: str) -> bool:
    t = text.lower()
    return hits(t, EN_MARKERS) > 0 or any(
        p in t for p in ["tomorrow", "meeting", "talk to", "send the", "review the"]
    )


def classify(case: dict, record: dict, score: dict) -> tuple[str, str]:
    expected = case.get("expected", {}).get("expectedLanguage")
    inp = case["input"]
    out = record.get("output") or ""
    decision = record.get("decision")
    drift = any(f["kind"] == "languageDrift" for f in score.get("objectiveFailures", []))

    if not drift:
        return "other", "No language drift failure scored."

    if len(inp) <= 8:
        return "low_confidence_unclassifiable", "Tiny/short input; independent assessment requires review."

    if expected in ("pt", "es") and likely_english_output(out):
        if decision == "noChange" and out == inp:
            return "validator_false_positive", "Final noChange with original text; likely safety rejection unrelated to visible drift."
        if decision == "changed":
            return "validator_false_negative", "Unauthorized translation reached changed output (M12B-001 validator miss)."
        return "generation_ignored_contract", "Model translated output; final action ambiguous without raw trace."

    if expected == "en" and hits(out, PT_MARKERS + ES_MARKERS) > hits(inp, PT_MARKERS + ES_MARKERS):
        return "generation_ignored_contract", "Output shifted away from English."

    return "evaluator_disagreement", "Drift flagged but heuristic classification uncertain without raw trace."


def main() -> None:
    cases = {json.loads(line)["id"]: json.loads(line) for line in CORPUS.read_text().splitlines() if line.strip()}
    data = json.loads(M12B001_DEV.read_text())
    scores = {s["caseID"]: s for s in data["scores"] if s["runIndex"] == 0}
    records = {r["caseID"]: r for r in data["records"] if r["runIndex"] == 0}

    rows = []
    counts: dict[str, int] = {}
    for case_id, score in scores.items():
        if not any(f["kind"] == "languageDrift" for f in score.get("objectiveFailures", [])):
            continue
        case = cases.get(case_id, {"input": records[case_id]["input"], "expected": {}})
        record = records[case_id]
        cause, explanation = classify(case, record, score)
        counts[cause] = counts.get(cause, 0) + 1
        rows.append((case_id, case.get("expected", {}).get("expectedLanguage"), record.get("decision"), cause, explanation))

    lines = [
        "# M12B-001 Language Failure Root Causes (retroactive)",
        "",
        "Retroactive classification from M12B-001 dev `results.json` without `languageTrace`.",
        "M12B-002 adds full per-run diagnostics for future runs.",
        "",
        "## Distribution",
        "",
        "| Root cause | Count |",
        "|---|---:|",
    ]
    for cause, count in sorted(counts.items(), key=lambda x: -x[1]):
        lines.append(f"| {cause} | {count} |")

    lines.extend(["", "## Cases", "", "| Case ID | Expected | Final decision | Root cause | Explanation |", "|---|---|---|---|---|"])
    for row in sorted(rows):
        lines.append(f"| `{row[0]}` | {row[1]} | {row[2]} | {row[3]} | {row[4]} |")

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"Wrote {OUTPUT}")
    print(counts)


if __name__ == "__main__":
    main()

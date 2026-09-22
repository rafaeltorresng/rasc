#!/usr/bin/env python3
"""Summarize language-specific metrics for M12B-001 vs baseline-v2."""

from __future__ import annotations

import json
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def load(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def language_drift_cases(summary: dict) -> list[str]:
    return [
        item["caseID"]
        for item in summary.get("criticalFailures", [])
        if any(f["kind"] == "languageDrift" for f in item.get("failures", []))
    ]


def tag_drift(summary: dict, tag: str) -> int:
    count = 0
    for item in summary.get("criticalFailures", []):
        if not any(f["kind"] == "languageDrift" for f in item.get("failures", [])):
            continue
        case_id = item["caseID"]
        if tag == "pt" and ("pt" in case_id or case_id.startswith("variant-pt")):
            count += 1
        elif tag == "es" and ("es" in case_id or case_id.startswith("variant-es")):
            count += 1
        elif tag == "en" and ("en" in case_id or case_id.startswith("variant-en")):
            count += 1
    return count


def main() -> None:
    baseline_root = ROOT / "Evals/Refine/reports"
    candidate_root = ROOT / "Evals/Refine/experiments/M12B-001-language-contract/reports"
    splits = ["dev", "validation", "regression", "stability"]

    print("# M12B-001 language metrics\n")
    for split in splits:
        base_path = baseline_root / f"baseline-{split}-v2/summary.json"
        cand_path = candidate_root / f"{split}/summary.json"
        if not base_path.exists() or not cand_path.exists():
            print(f"## {split}: pending\n")
            continue
        base = load(base_path)
        cand = load(cand_path)
        comp_path = candidate_root / f"{split}/comparison.json"
        comp = load(comp_path) if comp_path.exists() else {}

        print(f"## {split}")
        print(f"- baseline pass: {base['objectivePassRate']*100:.1f}%")
        print(f"- candidate pass: {cand['objectivePassRate']*100:.1f}%")
        print(f"- delta: {(cand['objectivePassRate']-base['objectivePassRate'])*100:+.1f}pp")
        print(f"- baseline critical failures: {len(base.get('criticalFailures', []))}")
        print(f"- candidate critical failures: {len(cand.get('criticalFailures', []))}")
        print(f"- language drift failures baseline: {len(language_drift_cases(base))}")
        print(f"- language drift failures candidate: {len(language_drift_cases(cand))}")
        print(f"- PT drift cases (heuristic id): baseline {tag_drift(base, 'pt')} → candidate {tag_drift(cand, 'pt')}")
        print(f"- ES drift cases (heuristic id): baseline {tag_drift(base, 'es')} → candidate {tag_drift(cand, 'es')}")
        print(f"- EN drift cases (heuristic id): baseline {tag_drift(base, 'en')} → candidate {tag_drift(cand, 'en')}")
        if comp:
            print(f"- improvements: {len(comp.get('improvements', []))}")
            print(f"- regressions: {len(comp.get('regressions', []))}")
            print(f"- critical regressions: {len(comp.get('criticalRegressions', []))}")
            print(f"- latency Δ p50: {comp.get('latencyDeltaMsP50', 0):+.0f} ms")
        print()


if __name__ == "__main__":
    main()

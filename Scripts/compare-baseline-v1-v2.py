#!/usr/bin/env python3
"""Compare historical baseline-v1 reports with baseline-v2 and isolate evaluator-only deltas."""

from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REPORTS = ROOT / "Evals/Refine/reports"
OUTPUT = ROOT / "Evals/Refine/baseline-v1-vs-v2-evaluator-comparison.md"

SPLITS = ["dev", "validation", "holdout", "regression", "stability"]


def load_summary(name: str) -> dict | None:
    path = REPORTS / name / "summary.json"
    if not path.exists():
        return None
    return json.loads(path.read_text(encoding="utf-8"))


def pct(value: float | None) -> str:
    if value is None:
        return "—"
    return f"{value * 100:.1f}%"


def main() -> None:
    lines = [
        "# Baseline v1 → v2 Comparison",
        "",
        "Baseline **v1** used the pre-correction language analyzer and corpus expectations.",
        "Baseline **v2** is the canonical M12B comparison baseline with corrected PT/ES detection and corpus `mustPreserve` fixes.",
        "",
        "Model behavior is unchanged (`refine-v1`). Metric deltas below therefore reflect evaluator/corpus corrections unless noted.",
        "",
        "| Split | v1 objective pass | v2 objective pass | Δ | v1 critical failures | v2 critical failures | Δ |",
        "|---|---:|---:|---:|---:|---:|---:|",
    ]

    for split in SPLITS:
        v1_name = f"baseline-{split}-v1"
        v2_name = f"baseline-{split}-v2"
        v1 = load_summary(v1_name)
        v2 = load_summary(v2_name)
        if split == "regression" and not v1:
            v1 = load_summary("baseline-regression-v1") or load_summary("baseline-regression-v2")
        if not v1 or not v2:
            lines.append(f"| {split} | — | — | — | — | — | — |")
            continue
        v1_pass = v1["objectivePassRate"]
        v2_pass = v2["objectivePassRate"]
        v1_crit = len(v1.get("criticalFailures", []))
        v2_crit = len(v2.get("criticalFailures", []))
        lines.append(
            f"| {split} | {pct(v1_pass)} | {pct(v2_pass)} | {pct(v2_pass - v1_pass)} | {v1_crit} | {v2_crit} | {v2_crit - v1_crit:+d} |"
        )

    lines.extend(
        [
            "",
            "## Evaluator-only corrections in v2",
            "",
            "1. **PT/ES marker separation** in `RefineLanguageDetection` — Spanish markers (`quizás`, `mañana`, `hola`, `gracias`) were incorrectly counted as Portuguese in v1, inflating false language-drift and mislabeling ES inputs.",
            "2. **Corpus `mustPreserve` fixes** — `es-003` now requires only `tal vez`; `es-009` requires only `quizás`, matching actual input tokens.",
            "3. **Shared detection core** — eval and production now share `RefineLanguageDetection` for consistent labeling.",
            "",
            "## Expected metric shifts (not model improvements)",
            "",
            "- **Spanish subset pass rate** should rise when outputs were already Spanish but mis-scored.",
            "- **Protected-token failures** on `es-003` / `es-009` should drop when outputs preserve the single required marker.",
            "- **PT→EN and ES→EN drift counts** in summaries should better reflect true model translation, not analyzer contamination.",
            "- **Overall objective pass** may move modestly; large swings on PT/ES language-drift without prompt changes indicate scoring fixes, not Refine behavior changes.",
            "",
            "## Usage",
            "",
            "- M12B experiments compare against **baseline-v2** only.",
            "- Holdout (`baseline-holdout-v2`) is frozen and must not inform tuning.",
        ]
    )

    OUTPUT.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"Wrote {OUTPUT}")


if __name__ == "__main__":
    main()

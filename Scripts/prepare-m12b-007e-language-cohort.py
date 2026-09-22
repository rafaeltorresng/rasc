#!/usr/bin/env python3
"""Prepare M12B-007D targeted language cohort for M12B-007E verification."""

from __future__ import annotations

import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
EVAL = ROOT / "Evals/Refine"
CORPUS = EVAL / "corpus.v1.jsonl"
REGRESSION = EVAL / "regression.jsonl"
AUDIT = json.loads((EVAL / "experiments/M12B-007D-residual-language-audit/analysis.json").read_text())

CASE_IDS = set(AUDIT["wrongLanguage"]["caseIDs"]) | set(AUDIT["falseRejections"]["caseIDs"])
CASE_IDS.update(
    {
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
    }
)


def read_jsonl(path: Path) -> list[dict]:
    if not path.exists():
        return []
    return [json.loads(line) for line in path.read_text().splitlines() if line.strip()]


def main() -> None:
    out = Path(sys.argv[1] if len(sys.argv) > 1 else "/tmp/m12b-007e-language-cohort")
    out.mkdir(parents=True, exist_ok=True)

    rows = [row for row in read_jsonl(CORPUS) + read_jsonl(REGRESSION) if row["id"] in CASE_IDS]
    (out / "corpus.v1.jsonl").write_text(
        "".join(json.dumps(row, ensure_ascii=False, sort_keys=True) + "\n" for row in rows)
    )
    (out / "regression.jsonl").write_text("")
    (out / "splits.v1.json").write_text(
        json.dumps(
            {
                "version": 1,
                "seed": "m12b-007e-language-cohort",
                "ratios": {"dev": 1.0, "validation": 0.0, "holdout": 0.0},
                "assignments": {row["id"]: "dev" for row in rows},
                "notes": {"holdout": "M12B-007D targeted cohort only."},
            },
            indent=2,
            sort_keys=True,
        )
        + "\n"
    )
    print(f"Prepared {len(rows)} cases at {out}")


if __name__ == "__main__":
    main()

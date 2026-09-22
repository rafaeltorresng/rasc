#!/usr/bin/env python3
"""Prepare M12C-001 language-preference eval corpus root."""

from __future__ import annotations

import json
import shutil
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
EXP = ROOT / "Evals/Refine/experiments/M12C-001-language-preference"
OUT = Path(sys.argv[1] if len(sys.argv) > 1 else EXP / "corpus-root")


def main() -> None:
    if OUT.exists():
        shutil.rmtree(OUT)
    OUT.mkdir(parents=True)

    rows = [
        json.loads(line)
        for line in (EXP / "eval-corpus.v1.jsonl").read_text().splitlines()
        if line.strip()
    ]
    (OUT / "corpus.v1.jsonl").write_text(
        "".join(json.dumps(row, ensure_ascii=False, sort_keys=True) + "\n" for row in rows)
    )
    (OUT / "regression.jsonl").write_text("")
    (OUT / "splits.v1.json").write_text(
        json.dumps(
            {
                "version": 1,
                "seed": "m12c-001-language-preference",
                "ratios": {"dev": 1.0, "validation": 0.0, "holdout": 0.0},
                "assignments": {row["id"]: "dev" for row in rows},
                "notes": {"holdout": "Dedicated M12C language-preference corpus only."},
            },
            indent=2,
            sort_keys=True,
        )
        + "\n"
    )
    print(f"Prepared corpus under {OUT} ({len(rows)} cases)")


if __name__ == "__main__":
    main()

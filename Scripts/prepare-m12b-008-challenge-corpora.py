#!/usr/bin/env python3
"""Prepare maintainer-unapproved challenge corpora for M12B-008."""

from __future__ import annotations

import json
import shutil
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
EVAL = ROOT / "Evals/Refine"
OUT = Path(sys.argv[1] if len(sys.argv) > 1 else "/tmp/m12b-008-challenges")


def read_jsonl(path: Path) -> list[dict]:
    return [json.loads(line) for line in path.read_text().splitlines() if line.strip()]


def write_corpus(name: str, rows: list[dict]) -> Path:
    root = OUT / name
    root.mkdir(parents=True, exist_ok=True)
    (root / "corpus.v1.jsonl").write_text(
        "".join(json.dumps(row, ensure_ascii=False, sort_keys=True) + "\n" for row in rows)
    )
    (root / "regression.jsonl").write_text("")
    (root / "splits.v1.json").write_text(
        json.dumps(
            {
                "version": 1,
                "seed": f"m12b-008-{name}",
                "ratios": {"dev": 1.0, "validation": 0.0, "holdout": 0.0},
                "assignments": {row["id"]: "dev" for row in rows},
                "notes": {"holdout": "Maintainer-unapproved challenge corpus only."},
            },
            indent=2,
            sort_keys=True,
        )
        + "\n"
    )
    return root


def main() -> None:
    if OUT.exists():
        shutil.rmtree(OUT)
    OUT.mkdir(parents=True)

    one_token = read_jsonl(EVAL / "challenges/one-token-positive-controls.v1.jsonl")
    semantic = read_jsonl(EVAL / "challenges/semantic-literals.v1.jsonl")
    selection = read_jsonl(EVAL / "experiments/M12B-006A-selection-reliability/challenge-set.jsonl")

    write_corpus("one-token-challenge", one_token)
    write_corpus("semantic-money-challenge", [r for r in semantic if r.get("literalClass") == "money"])
    write_corpus("semantic-percentage-challenge", [r for r in semantic if r.get("literalClass") == "percentage"])
    write_corpus("semantic-time-challenge", [r for r in semantic if r.get("literalClass") == "time"])
    write_corpus("semantic-protected-challenge", semantic)
    write_corpus("selection-challenge", selection)

    # Language cohort reuses existing preparer output if present, else inline minimal set.
    lang_script = ROOT / "Scripts/prepare-m12b-007f-unresolved-cohort.py"
    lang_root = OUT / "language-cohort"
    import subprocess

    subprocess.run([sys.executable, str(lang_script), str(lang_root)], check=True)
    print(f"Prepared challenge corpora under {OUT}")


if __name__ == "__main__":
    main()

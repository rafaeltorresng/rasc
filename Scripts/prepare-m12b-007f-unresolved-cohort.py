#!/usr/bin/env python3
"""Prepare unresolved-language cohort for M12B-007F verification."""

from __future__ import annotations

import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
EVAL = ROOT / "Evals/Refine"
CORPUS = EVAL / "corpus.v1.jsonl"
REGRESSION = EVAL / "regression.jsonl"
AUDIT_007E = EVAL / "experiments/M12B-007E-language-validator-calibration/analysis.json"

POLICY_A_CASES = {
    "selection-extra-007",
    "short-pt-012",
    "short-pt-013",
    "telegraphic-pt-010",
}

AMBIGUOUS_CONTROLS = {
    "retry",
    "deploy",
    "technical-only-001",
    "technical-only-002",
    "tiny-en-001",
    "tiny-en-002",
}


def read_jsonl(path: Path) -> list[dict]:
    if not path.exists():
        return []
    return [json.loads(line) for line in path.read_text().splitlines() if line.strip()]


def main() -> None:
    out = Path(sys.argv[1] if len(sys.argv) > 1 else "/tmp/m12b-007f-unresolved-cohort")
    out.mkdir(parents=True, exist_ok=True)

    audit = json.loads(AUDIT_007E.read_text()) if AUDIT_007E.exists() else {}
    case_ids = set(POLICY_A_CASES)
    case_ids.update(AMBIGUOUS_CONTROLS)
    case_ids.update(audit.get("remainingWrongLanguageCaseIDs", []))

    rows = []
    for row in read_jsonl(CORPUS) + read_jsonl(REGRESSION):
        if row["id"] in case_ids:
            rows.append(row)
        elif any(tag in {"tiny", "ambiguous", "technical"} for tag in row.get("tags") or []):
            if row["id"].startswith(("tiny-", "technical-", "short-en-", "variant-en-")):
                rows.append(row)

    seen = set()
    unique_rows = []
    for row in rows:
        if row["id"] in seen:
            continue
        seen.add(row["id"])
        unique_rows.append(row)

    (out / "corpus.v1.jsonl").write_text(
        "".join(json.dumps(row, ensure_ascii=False, sort_keys=True) + "\n" for row in unique_rows)
    )
    (out / "regression.jsonl").write_text("")
    (out / "splits.v1.json").write_text(
        json.dumps(
            {
                "version": 1,
                "seed": "m12b-007f-unresolved-cohort",
                "ratios": {"dev": 1.0, "validation": 0.0, "holdout": 0.0},
                "assignments": {row["id"]: "dev" for row in unique_rows},
                "notes": {"holdout": "M12B-007F unresolved-language cohort only."},
            },
            indent=2,
            sort_keys=True,
        )
        + "\n"
    )
    print(f"Prepared {len(unique_rows)} cases at {out}")


if __name__ == "__main__":
    main()

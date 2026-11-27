#!/usr/bin/env python3
"""Stage a separate regression corpus, leaving the frozen corpus unchanged."""
import json
import sys
from pathlib import Path

cases_path = Path(__file__).resolve().with_name("intent-cases.json")
root = cases_path.parents[2]
out = Path(sys.argv[1])
out.mkdir(parents=True, exist_ok=False)
for name in ("corpus.v1.jsonl", "splits.v1.json"):
    (out / name).symlink_to(root / "Evals/Refine" / name)

cases = json.loads(cases_path.read_text())
if len(sys.argv) > 2:
    # NC evaluation inputs stay in the local run directory only.
    voice = json.loads(Path(sys.argv[2]).read_text())
    cases += [
        {"id": row["id"], "kind": "voicearena-ai-prompt", "text": row["intended_text"]}
        for row in voice if row.get("domain") == "ai_prompt"
    ]

with (out / "regression.jsonl").open("w") as output:
    for case in cases:
        text = case["text"]
        row = {
            "id": case["id"], "source": "intent-reliability", "category": [case["kind"]],
            "tags": ["intent"], "input": text, "scope": "wholeNote",
            "languagePolicy": {"mode": "matchNote"},
            "expected": {"allowedActions": ["noChange", "cleanup", "structure"],
                         "mustNotIntroduceInformation": True},
            "severity": "high", "split": "regression",
        }
        if target := case.get("target"):
            row["languagePolicy"] = {"mode": "fixedLocale", "preferredLocale": target}
        if "before" in case:
            row.update(scope="selection", selection=text, surroundingContext={
                "before": case["before"], "after": case["after"],
                "fullNote": case["before"] + text + case["after"],
            })
        output.write(json.dumps(row, ensure_ascii=False) + "\n")

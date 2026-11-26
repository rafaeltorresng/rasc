#!/usr/bin/env python3
"""Pool fixed transcripts by cohort without exporting public recordings or their text."""
import json
from pathlib import Path
from runpy import run_path
import sys

held_manifest, held_runs, dev_manifest, measurements = map(Path, sys.argv[1:])
round2_score = run_path(str(Path(__file__).resolve().parents[2] / "Round2" / "score-round2.py"))
words, distance = round2_score["words"], round2_score["distance"]
profiles = ("neural", "lead80", "encoderCPU")
evidence = {}
for split, paths, manifest in (("held", held_runs, held_manifest), ("synthetic", measurements, dev_manifest)):
    rows = json.loads(manifest.read_text())
    names = {r["id"] + ".wav" for r in rows}
    variants = {}
    for profile in profiles:
        run = [json.loads(line) for line in (paths / f"{split}-{profile}.jsonl").read_text().splitlines()]
        mapped = {r["fixture"]: r for r in run}
        if set(mapped) != names or any("error" in r for r in run):
            raise SystemExit(f"Incomplete comparison in {split} / {profile}")
        cohorts = {}
        for row in rows:
            name = row["id"] + ".wav"
            group = row.get("scenario") or row["group"]
            entry = cohorts.setdefault(group, dict(clips=0, words=0, errors=0, unchanged=0, empty=0))
            predicted = mapped[name]["transcript"]
            reference = words(row["reference"])
            entry["clips"] += 1
            entry["words"] += len(reference)
            entry["errors"] += distance(reference, words(predicted))
            entry["empty"] += not predicted.strip()
            if profile in ("lead80", "encoderCPU"):
                entry["unchanged"] += predicted == baseline[name]["transcript"]
            else:
                entry["unchanged"] += 1
        for entry in cohorts.values():
            entry["wer"] = round(100 * entry["errors"] / entry["words"], 2) if entry["words"] else None
        if profile == "neural":
            baseline = mapped
        variants[profile] = cohorts
    evidence[split] = variants
print(json.dumps(evidence, indent=2))

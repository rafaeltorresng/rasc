#!/usr/bin/env python3
"""Paired clip resampling of held-out WER differences, without redistributing transcripts."""
import argparse
import json
from pathlib import Path
import random
from runpy import run_path

score = run_path(str(Path(__file__).with_name("score-round2.py")))
words, distance = score["words"], score["distance"]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("bench", type=Path)
parser.add_argument("manifest", type=Path)
args = parser.parse_args()
models = ["apple", "fluid", "ultra", "granite", "qwen17"]
transcripts = {}
for model in models:
    rows = [json.loads(line) for line in (args.bench / (model + "-held.jsonl")).read_text().splitlines()]
    transcripts[model] = {row["fixture"]: words(row.get("transcript", "")) for row in rows if "fixture" in row}

result = {}
manifest = json.loads(args.manifest.read_text())
for locale in ("pt-BR", "en-US"):
    rows = [row for row in manifest if row["split"] == "held" and row["locale"] == locale]
    lengths = []
    errors = {model: [] for model in models}
    for row in rows:
        ref = words(row["reference"])
        lengths.append(len(ref))
        for model in models:
            errors[model].append(distance(ref, transcripts[model][row["id"] + ".wav"]))
    rng = random.Random(5347)
    samples = [rng.choices(range(len(rows)), k=len(rows)) for _ in range(5000)]
    ranges = {}
    for model in models[1:]:
        delta = [candidate - base for candidate, base in zip(errors[model], errors["apple"])]
        values = sorted(100 * sum(delta[i] for i in sample) / sum(lengths[i] for i in sample) for sample in samples)
        ranges[model] = dict(delta_vs_apple=round(100 * sum(delta) / sum(lengths), 2),
                             clip_resampled_95_interval=[round(values[125], 2), round(values[4874], 2)])
    result[locale] = dict(clips=len(rows), differences_in_percentage_points=ranges)
print(json.dumps(result, indent=2))

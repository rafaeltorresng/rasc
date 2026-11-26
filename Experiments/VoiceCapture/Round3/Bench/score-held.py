#!/usr/bin/env python3
"""Score all three finalists on matched human data without publishing text."""
from collections import Counter
import csv
import json
from pathlib import Path
import random
from runpy import run_path
import sys
import wave

inputs, results, archive = map(Path, sys.argv[1:])
round2_score = run_path(str(Path(__file__).resolve().parents[2] / "Round2" / "score-round2.py"))
words, distance = round2_score["words"], round2_score["distance"]
distribution = round2_score["distribution"]
manifest = json.loads((inputs / "manifest.json").read_text())
engines = ("apple", "ultra", "fluid")
predictions = {}
for engine in engines:
    rows = [json.loads(line) for line in (results / (engine + ".jsonl")).read_text().splitlines()]
    predictions[engine] = {row["fixture"]: row for row in rows if "fixture" in row}
    if len(predictions[engine]) != len(manifest):
        raise RuntimeError(f"Incorrect sample count for {engine}")
summary = {}
clip_stats = []
for row in manifest:
    filename = row["id"] + ".wav"
    with wave.open(str(inputs / filename)) as f:
        duration = f.getnframes() / f.getframerate()
    ref = words(row["reference"])
    chars = "".join(ref)
    for engine in engines:
        result = predictions[engine][filename]
        value = words(result.get("transcript", ""))
        clip_stats.append(dict(clip=row["id"], scenario=row["scenario"], words=len(ref), chars=len(chars),
                               seconds=round(duration, 3), engine=engine, errors=distance(ref, value),
                               char_errors=distance(chars, "".join(value)),
                               first=bool(ref and value and ref[0] == value[0]),
                               last=bool(ref and value and ref[-1] == value[-1]),
                               failed="error" in result, empty=not value,
                               prepare_ms=round(result.get("prepare_ms", 0), 2),
                               finish_ms=round(result.get("finish_ms", 0), 2)))
for scenario in sorted({row["scenario"] for row in manifest}):
    cohort = [r for r in clip_stats if r["scenario"] == scenario]
    summary[scenario] = {}
    for engine in engines:
        sample = [r for r in cohort if r["engine"] == engine]
        total = Counter()
        for row in sample:
            total.update({k:row[k] for k in ("words", "chars", "errors", "char_errors", "first", "last", "failed", "empty")})
        summary[scenario][engine] = dict(n=len(sample), wer=round(100 * total["errors"] / total["words"], 2),
                                         cer=round(100 * total["char_errors"] / total["chars"], 2),
                                         first=total["first"], last=total["last"], failed=total["failed"],
                                         empty=total["empty"],
                                         short_finish_ms=distribution([r["finish_ms"] for r in sample if r["seconds"] < 6]))
    by_engine = {e: {r["clip"]: r for r in cohort if r["engine"] == e} for e in engines}
    names = sorted(by_engine["ultra"])
    baseline = [by_engine["ultra"][i] for i in names]
    rng = random.Random(15036)
    comparisons = {}
    for challenger in ("fluid", "apple"):
        trial = []
        for _ in range(4000):
            sample = rng.choices(range(len(names)), k=len(names))
            trial.append(100 * sum(by_engine[challenger][names[i]]["errors"] - baseline[i]["errors"]
                                   for i in sample) / sum(baseline[i]["words"] for i in sample))
        trial.sort()
        comparisons[challenger] = [round(trial[100], 2), round(trial[3899], 2)]
    summary[scenario]["paired_clip_95_interval_delta_vs_ultra"] = comparisons

archive.mkdir(parents=True, exist_ok=True)
(archive / "held-summary.json").write_text(json.dumps(summary, indent=2) + "\n")
with (archive / "held-clip-metrics.csv").open("w") as stream:
    output = csv.DictWriter(stream, fieldnames=clip_stats[0].keys())
    output.writeheader()
    output.writerows(clip_stats)

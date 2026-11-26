#!/usr/bin/env python3
"""Run the signed analyzer probe on the synthetic fixture matrix."""
import argparse
import json
import subprocess
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("app", type=Path)
parser.add_argument("fixtures", type=Path)
parser.add_argument("output", type=Path)
parser.add_argument("--mode", choices=("batch", "paced"), default="paced")
parser.add_argument("--engine", choices=("speech", "dictation"), action="append")
parser.add_argument("--fixture", action="append", help="Select a subset; defaults to the whole corpus")
args = parser.parse_args()
rows = json.loads((args.fixtures / "manifest.json").read_text())
probe = args.app.resolve() / "Contents/MacOS/VoiceProbe"
args.output.mkdir(parents=True, exist_ok=True)
for engine in args.engine or ["speech", "dictation"]:
    log = args.output / f"{engine}-{args.mode}.jsonl"
    stats = args.output / f"{engine}-{args.mode}-resources.txt"
    with log.open("w") as results, stats.open("w") as resources:
        for locale in ("en-US", "pt-BR"):
            filenames = ["@" + row["id"] + ".wav" for row in rows
                         if row["locale"] == locale and (not args.fixture or row["id"] in args.fixture)]
            if not filenames:
                continue
            resources.write(locale + "\n")
            resources.flush()
            subprocess.run(["/usr/bin/time", "-l", probe, args.mode, engine, locale, *filenames],
                           stdout=results, stderr=resources, check=True, timeout=240)

#!/usr/bin/env python3
"""Stage fixtures ahead of time. Run one engine at a time and leave raw public-source transcripts local."""
import argparse
import json
from pathlib import Path
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--study", type=Path, required=True)
parser.add_argument("--python-mlx", type=Path, required=True)
parser.add_argument("--models", type=Path, required=True)
parser.add_argument("--fixtures", type=Path, required=True)
parser.add_argument("--human-manifest", type=Path, required=True)
parser.add_argument("--synthetic-manifest", type=Path, required=True)
parser.add_argument("--output", type=Path, required=True)
parser.add_argument("--split", choices=("screen", "held"), default="screen")
parser.add_argument("engines", nargs="+")
args = parser.parse_args()

human = json.loads(args.human_manifest.read_text())
synthetic = [] if args.split != "screen" else json.loads(args.synthetic_manifest.read_text())
rows = [{**row, "scenario": "synthetic"} for row in synthetic] + [r for r in human if r["split"] == args.split]
args.output.mkdir(parents=True, exist_ok=True)
for engine in args.engines:
    if engine in {"apple", "fluid", "ultra"}:
        groups = [(locale, [row for row in rows if row["locale"] == locale]) for locale in ("en-US", "pt-BR")]
        if engine != "apple":
            groups = [("auto", rows)]
        cmds = [[args.study, "--benchmark", engine, locale, *(row["id"] + ".wav" for row in subset)]
                for locale, subset in groups]
    else:
        cmds = [[args.python_mlx, Path(__file__).with_name("bench-mlx.py"), engine,
                args.models / engine, *(args.fixtures / (row["id"] + ".wav") for row in rows)]]
    with (args.output / (engine + "-" + args.split + ".jsonl")).open("w") as result, \
         (args.output / (engine + "-" + args.split + ".stderr")).open("w") as resource:
        for cmd in cmds:
            subprocess.run(["/usr/bin/time", "-l", *cmd], stdout=result, stderr=resource,
                           check=True, timeout=500)

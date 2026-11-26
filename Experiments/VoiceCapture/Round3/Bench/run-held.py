#!/usr/bin/env python3
"""Run the identical new holdout through the three finalists; keep raw predictions local."""
from pathlib import Path
import json
import subprocess
import sys

binary, manifest, out = map(Path, sys.argv[1:])
rows = json.loads(manifest.read_text())
out.mkdir(parents=True, exist_ok=True)
for engine in ["apple", "ultra", "fluid"]:
    with (out / f"{engine}.jsonl").open("w") as output, (out / f"{engine}.resources").open("w") as resources:
        batches = [("auto", rows)] if engine != "apple" else [
            (locale, [r for r in rows if r["locale"] == locale]) for locale in ["pt-BR", "en-US"]
        ]
        for locale, batch in batches:
            subprocess.run(["/usr/bin/time", "-lp", binary, "--benchmark", engine, locale,
                            *(r["id"] + ".wav" for r in batch)], stdout=output, stderr=resources,
                           timeout=360, check=True)

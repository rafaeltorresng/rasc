#!/usr/bin/env python3
"""Compare Fluid Speech Pro CPU outputs to the locked CPU+ANE configuration."""
import json
from pathlib import Path
import subprocess
import sys

app, inputs, neural, directory = map(Path, sys.argv[1:])
directory.mkdir(parents=True, exist_ok=True)
manifest = json.loads((inputs / "manifest.json").read_text())
names = [r["id"] + ".wav" for r in manifest]


def read(path):
    return {r["fixture"]: r for line in path.read_text().splitlines()
            if (r := json.loads(line)).get("fixture")}


raw = directory / "cpu-parity.raw.jsonl"
with raw.open("w") as output, (directory / "cpu-parity.resources").open("w") as resources:
    subprocess.run(["/usr/bin/time", "-l", app, "--benchmark", "fluid", "auto", "compute=cpu",
                    *names], stdout=output, stderr=resources, check=True, timeout=360)
control, trial = read(neural), read(raw)
if set(control) != set(names) or set(trial) != set(names):
    raise RuntimeError("Matched clip counts differ")
different = [name for name in names if trial[name].get("transcript") != control[name].get("transcript")]
times = sorted(r["finish_ms"] for r in trial.values() if "finish_ms" in r and r.get("prepare_ms", 0) < 3)
print(json.dumps(dict(n=len(names), results=len(trial), identical=len(trial) - len(different),
                      differing_clip_ids=different, warm_p50_ms=round(times[len(times)//2], 2),
                      warm_p95_ms=round(times[int(len(times)*.95)], 2)), indent=2))

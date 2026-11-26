#!/usr/bin/env python3
"""Report raw WER/CER and timing aggregates. Public speech transcripts remain in the local bench workspace."""
import argparse
import json
import math
from pathlib import Path
import re
import statistics
import unicodedata
import wave

def words(value):
    value = unicodedata.normalize("NFC", value.casefold().replace("’", "'"))
    return re.findall(r"[^\W_]+(?:'[^\W_]+)*", value, flags=re.UNICODE)

def distance(a, b):
    prior = list(range(len(b) + 1))
    for i, x in enumerate(a, 1):
        current = [i]
        for j, y in enumerate(b, 1):
            current.append(min(prior[j]+1, current[-1]+1, prior[j-1]+(x != y)))
        prior = current
    return prior[-1]

def distribution(values):
    samples = sorted(values)
    if not samples:
        return None
    return {"n": len(samples), "p50": round(statistics.median(samples), 2),
            "p95": round(samples[math.ceil(len(samples)*.95)-1], 2), "max": round(samples[-1], 2)}

def score(rows):
    word_ref = char_ref = w_edits = c_edits = first = last = 0
    for fx, line in rows:
        a, b = words(fx["reference"]), words(line.get("transcript", ""))
        ca, cb = "".join(a), "".join(b)
        word_ref += len(a)
        char_ref += len(ca)
        w_edits += distance(a, b)
        c_edits += distance(ca, cb)
        first += bool(a and b and a[0] == b[0])
        last += bool(a and b and a[-1] == b[-1])
    return {"n": len(rows), "wer": round(100*w_edits/word_ref, 2) if word_ref else None,
            "cer": round(100*c_edits/char_ref, 2) if char_ref else None,
            "first_match": first, "last_match": last,
            "errors": sum("error" in line for _, line in rows)}

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("bench", type=Path)
    parser.add_argument("synthetic", type=Path)
    parser.add_argument("human", type=Path)
    parser.add_argument("fixtures", type=Path)
    args = parser.parse_args()
    synthetic = {row["id"] + ".wav": row for row in json.loads(args.synthetic.read_text())}
    human = {row["id"] + ".wav": row for row in json.loads(args.human.read_text())}
    durations = {}
    for name in (synthetic | human):
        with wave.open(str(args.fixtures / name)) as audio:
            durations[name] = audio.getnframes() / audio.getframerate()
    output = {}
    for path in sorted(args.bench.glob("*.jsonl")):
        if not any(path.stem.endswith("-" + sw) for sw in ("screen", "held", "synthetic")):
            continue
        raw = [json.loads(line) for line in path.read_text().splitlines() if line.startswith("{")]
        rows = {row["fixture"]: row for row in raw if row.get("fixture") in synthetic or row.get("fixture") in human}
        if not rows:
            continue
        pairset = [(synthetic.get(name) or human[name], row) for name, row in rows.items()]
        groups = {}
        for fx, row in pairset:
            scenario = fx.get("scenario") or "synthetic-" + fx["group"]
            if scenario == "synthetic-control":
                continue
            key = scenario + (":" + fx["locale"] if scenario.startswith("human") else "")
            groups.setdefault(key, []).append((fx, row))
            groups.setdefault("short" if durations[row["fixture"]] <= 6 else "longer", []).append((fx, row))
            for tag in fx.get("tags", []):
                groups.setdefault("tag:" + tag, []).append((fx, row))
        resource = args.bench / (path.stem + ".stderr")
        timings = resource.read_text() if resource.exists() else ""
        rss = [int(x) for x in re.findall(r"(\d+)\s+maximum resident set size", timings)]
        footprint = [int(x) for x in re.findall(r"(\d+)\s+peak memory footprint", timings)]
        cold = [r["load_ms"] for r in raw if "load_ms" in r]
        if not cold:
            cold = [r["prepare_ms"] for r in raw if r.get("prepare_ms", 0) > 3]
        finish = [r["finish_ms"] for name, r in rows.items() if "finish_ms" in r and durations[name] <= 6
                  and (human.get(name) or synthetic[name])["reference"]]
        output[path.stem] = {
            "attempts": len(rows),
            "groups": {group: score(values) for group, values in sorted(groups.items())},
            "short_finish_ms": distribution(finish),
            "prepare_ms": [round(t, 2) for t in cold],
            "max_rss_mb": round(max(rss)/1e6, 1) if rss else None,
            "peak_os_footprint_mb": round(max(footprint)/1e6, 1) if footprint else None,
            "max_mlx_active_peak_mb": round(max(r["mlx_peak_bytes"] for r in raw if "mlx_peak_bytes" in r)/1e6, 1)
                if any("mlx_peak_bytes" in r for r in raw) else None,
            "no_speech": {name: item.get("transcript", item.get("error", ""))
                          for name, item in rows.items() if name in synthetic and not synthetic[name]["reference"]},
        }
    print(json.dumps(output, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Direct MLX batch comparison. All model directories must be staged first."""
import argparse
import json
import os
from pathlib import Path
import time
import resource

os.environ["HF_HUB_OFFLINE"] = "1"
os.environ["TRANSFORMERS_OFFLINE"] = "1"
import mlx.core as mx
from mlx_audio.stt.utils import load

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("engine")
parser.add_argument("model", type=Path)
parser.add_argument("files", type=Path, nargs="+")
args = parser.parse_args()
assert args.model.is_dir()
start = time.monotonic()
model = load(args.model, strict=True)
print(json.dumps(dict(event="load", engine=args.engine, load_ms=(time.monotonic()-start)*1000,
                      process_rss_bytes=resource.getrusage(resource.RUSAGE_SELF).ru_maxrss,
                      mlx_active_bytes=mx.get_active_memory())), flush=True)
for file in args.files:
    started = time.monotonic()
    mx.reset_peak_memory()
    try:
        result = model.generate(str(file))
        text = result.text
        row = dict(engine=args.engine, fixture=file.name, transcript=text, language=getattr(result, "language", None),
                   finish_ms=(time.monotonic()-started)*1000, mlx_peak_bytes=mx.get_peak_memory(),
                   process_rss_bytes=resource.getrusage(resource.RUSAGE_SELF).ru_maxrss)
    except Exception as err:
        row = dict(engine=args.engine, fixture=file.name, error=f"{type(err).__name__}: {err}")
    print(json.dumps(row, ensure_ascii=False, default=str), flush=True)

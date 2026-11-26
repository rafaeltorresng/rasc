#!/usr/bin/env python3
"""Download exact MLX study weights. Only model asset requests leave this process."""
import argparse
import json
from pathlib import Path

from huggingface_hub import snapshot_download

HERE = Path(__file__).resolve().parent
LOCK = json.loads((HERE / "results" / "model-lock.json").read_text())
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("model", choices=["qwen06", "qwen17", "granite", "cohere"])
parser.add_argument("output", type=Path)
args = parser.parse_args()
asset = LOCK[args.model]
snapshot_download(repo_id=asset["repo"], revision=asset["revision"], local_dir=args.output / args.model,
                  allow_patterns=["*.safetensors", "*.json", "*.txt", "*.model"], max_workers=4)

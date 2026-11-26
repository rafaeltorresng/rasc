#!/usr/bin/env python3
"""Download pinned, licensed Core ML weights only. Sends no audio or text."""
import concurrent.futures
import json
import subprocess
import sys
from pathlib import Path, PurePosixPath
from urllib.parse import quote

REPO = "https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v3-coreml"
REVISION = "7dd20fe6b1797d35f5e3307e8b1732d9a178edfe"
COMPONENTS = {"Encoder.mlmodelc", "Decoder.mlmodelc", "Preprocessor.mlmodelc", "JointDecisionv3.mlmodelc", "parakeet_vocab.json"}

def fetch(entry, root):
    relative = PurePosixPath(entry["path"])
    if relative.parts[0] not in COMPONENTS or entry["type"] != "file":
        return 0
    target = root.joinpath(*relative.parts)
    if target.exists() and target.stat().st_size == entry["size"]:
        return entry["size"]
    target.parent.mkdir(parents=True, exist_ok=True)
    partial = target.with_suffix(target.suffix + ".part")
    url = f"{REPO}/resolve/{REVISION}/{quote(str(relative))}?download=true"
    subprocess.run(["curl", "-fLsS", "--retry", "2", url, "-o", partial], check=True)
    if partial.stat().st_size != entry["size"]:
        raise ValueError(f"Incomplete download: {relative}")
    partial.replace(target)
    return entry["size"]

root = Path(sys.argv[1])
index = REPO.replace("huggingface.co/", "huggingface.co/api/models/", 1)
entries = json.loads(subprocess.check_output(["curl", "-fLsS", f"{index}/tree/{REVISION}?recursive=true&expand=false"]))
with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
    print(f"Staged {sum(pool.map(lambda row: fetch(row, root), entries))} bytes at revision {REVISION}")

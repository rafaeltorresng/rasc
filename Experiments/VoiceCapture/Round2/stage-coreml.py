#!/usr/bin/env python3
"""Stage pinned Core ML artifacts only. This script receives no speech."""
import concurrent.futures
import hashlib
import json
from pathlib import Path
import subprocess
import sys
from urllib.parse import quote

MODELS = {
    "fluid-pro": ("FluidVoice-Labs/fluid-speech-pro-coreml", "3b9d38a93d606f84011e5a0a669b7ea146375a22",
                  {"Encoder.mlmodelc", "Decoder.mlmodelc", "JointDecision.mlmodelc", "Preprocessor.mlmodelc", "parakeet_vocab.json", "config.json"}),
    "nemotron": ("FluidInference/Nemotron-3.5-ASR-Streaming-Multilingual-0.6b-CoreML",
                 "a70b9d1c33594f1f4cf3f4eca9b4a0a8f44a9f59", None),
    "ultra": ("FluidInference/parakeet-ultra-coreml", "95eaa59a39d4394f047a4dc5cce480388a60d1b6",
              {"Encoder.mlmodelc", "Decoder.mlmodelc", "JointDecisionv3.mlmodelc", "Preprocessor.mlmodelc", "parakeet_vocab.json"}),
}

def curl(url):
    return subprocess.check_output(["curl", "-fsSL", "--retry", "2", url])

def stage(name, out):
    repo, revision, wanted = MODELS[name]
    target = out / name
    target.mkdir(parents=True, exist_ok=True)
    listing = json.loads(curl(f"https://huggingface.co/api/models/{repo}/tree/{revision}?recursive=true"))
    prefix = "latin/560ms/" if name == "nemotron" else ""
    if prefix:
        files = [f for f in listing if f["type"] == "file" and f["path"].startswith(prefix)]
        assert files, "Nemotron 560 ms files missing"
    else:
        files = [f for f in listing if f["type"] == "file" and f["path"].split("/")[0] in wanted]
        assert {f["path"].split("/")[0] for f in files} == wanted, "Required artifacts missing"
    def download(f):
        path = target / f["path"].removeprefix(prefix)
        expected = f.get("lfs", {}).get("oid")
        def valid(p):
            if not p.exists() or p.stat().st_size != f["size"]:
                return False
            if not expected:
                return True
            with p.open("rb") as stream:
                return hashlib.file_digest(stream, "sha256").hexdigest() == expected
        if not valid(path):
            path.parent.mkdir(parents=True, exist_ok=True)
            partial = path.with_suffix(path.suffix + ".part")
            url = f"https://huggingface.co/{repo}/resolve/{revision}/{quote(f['path'])}?download=true"
            subprocess.run(["curl", "-fsSL", "--retry", "2", "--max-time", "1800", url, "-o", partial], check=True)
            if not valid(partial):
                raise RuntimeError(f"Integrity error for {f['path']}")
            partial.replace(path)
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
        list(pool.map(download, sorted(files, key=lambda f: -f["size"])))
    size = sum(f["size"] for f in files)
    (target / "provenance.json").write_text(json.dumps(dict(repo=repo, revision=revision, bytes=size), indent=2) + "\n")
    print(f"{name}: {size} bytes {revision}", flush=True)

if __name__ == "__main__":
    stage(sys.argv[1], Path(sys.argv[2]))

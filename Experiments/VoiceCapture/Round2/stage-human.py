#!/usr/bin/env python3
"""Fetch public benchmark clips for private local comparison. Outputs stay outside the repository."""
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path
import subprocess
import sys
from urllib.parse import urlencode

SOURCES = {
    "en": ("openslr/librispeech_asr", "clean", [0, 125, 295, 472], "en-US", "71cacbfb7e2354c4226d01e70d77d5fca3d04ba1"),
    "pt": ("nilc-nlp/TARSILA-ASR", "default", [0, 4000, 1830, 6000], "pt-BR", "2785788cf674adc35caf83c297942dab3592a1b8"),
}

def fetch_json(address):
    return json.loads(subprocess.check_output(["curl", "-fsSL", "--retry", "2", address]))

def digest(path):
    with path.open("rb") as file:
        return hashlib.file_digest(file, "sha256").hexdigest()

def check_staged(rows, output, pinned):
    ids = {row["id"] for row in rows}
    if ids != set(pinned):
        raise ValueError("Clip IDs differ from the archived manifest")
    for row in rows:
        expected = pinned[row["id"]]
        if {key: value for key, value in row.items() if key != "reference"} != expected:
            raise ValueError(f"Manifest mismatch: {row['id']}")
        if digest(output / (row["id"] + ".wav")) != expected["sha256"]:
            raise ValueError(f"Audio hash mismatch: {row['id']}")

def generate(output):
    output.mkdir(parents=True, exist_ok=True)
    manifest = output / "manifest.json"
    archived = Path(__file__).with_name("results") / "human-manifest-no-text.json"
    pinned = {row["id"]: row for row in json.loads(archived.read_text())}
    if manifest.exists():
        rows = json.loads(manifest.read_text())
        check_staged(rows, output, pinned)
        print(f"Verified {len(rows)} staged clips")
        return
    entries = []
    for language, (dataset, config, offsets, locale, revision) in SOURCES.items():
        metadata = fetch_json(f"https://huggingface.co/api/datasets/{dataset}")
        if metadata["sha"] != revision:
            raise ValueError(f"Dataset server may be serving a new revision of {dataset}")
        for index, offset in enumerate(offsets):
            args = urlencode(dict(dataset=dataset, config=config, split="test", offset=offset, length=16))
            block = fetch_json(f"https://datasets-server.huggingface.co/rows?{args}")["rows"]
            for cell in block:
                row = cell["row"]
                if language == "pt" and row["origin"] != "nurcsp":
                    continue
                row_id = cell["row_idx"]
                split = "screen" if index < 2 else "held"
                entries.append((dict(id=f"{language}-{row_id:05d}", dataset=dataset, revision=revision,
                                     config=config, row=row_id, locale=locale, split=split,
                                     scenario="human-conversation" if language == "pt" else "human-read",
                                     reference=row["text"]), row["audio"][0]["src"]))
    def save(item):
        row, url = item
        wav = output / (row["id"] + ".wav")
        raw = output / (row["id"] + ".original")
        if not wav.exists():
            subprocess.run(["curl","-fsSL","--retry","2",url,"-o",raw], check=True)
            subprocess.run(["ffmpeg","-v","error","-i",raw,"-ac","1","-ar","16000","-c:a","pcm_s16le",wav], check=True)
            raw.unlink()
        row["sha256"] = digest(wav)
        return row
    with ThreadPoolExecutor(max_workers=10) as pool:
        rows = list(pool.map(save, entries))
    check_staged(rows, output, pinned)
    manifest.write_text(json.dumps(rows, ensure_ascii=False, indent=2)+"\n")
    print(f"Staged {len(rows)} clips")
if __name__ == "__main__":
    generate(Path(sys.argv[1]))
